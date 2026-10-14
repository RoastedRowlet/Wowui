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

local lookup = {'DeathKnight-Frost','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Priest-Holy','Priest-Discipline','Warrior-Protection','Mage-Arcane','Shaman-Elemental','DeathKnight-Blood','Hunter-Survival','Monk-Windwalker','Paladin-Retribution','Warlock-Demonology','Rogue-Outlaw','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Unholy','Warlock-Affliction','Warrior-Arms','Druid-Guardian','Druid-Restoration','Rogue-Assassination','Mage-Frost','Evoker-Augmentation','Hunter-Marksmanship','Priest-Shadow','Druid-Feral','Shaman-Enhancement','Druid-Balance','Monk-Brewmaster','Paladin-Protection','Evoker-Devastation','Rogue-Subtlety','Evoker-Preservation',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abajaba:BAAANQAECgQIBwAAAA==.Abractus:BAABNQAECn8bAAIBAAYK3hNbQwCvAQABAAYK3hNbQwCvAQAAAA==.',
Ad='Adaline:BAAANQADCgQIBAAAAA==.Aderrig:BAAANQADCgQIBAAAAA==.Adohlin:BAAANQABCgQIBgAAAA==.Adriana:BAABNQAECn8cAAICAAcKwRoUUQAlAgACAAcKwRoUUQAlAgAAAA==.Adrianix:BAAANQAECgQIDQAAAA==.Adru:BAAANQAECgYIEwAAAA==.',
Ae='Aeglos:BAACNQAFFH8IAAIBAAMKnQq0EADLAAABAAMKnQq0EADLAAA1AAQKfyYAAgEACQprIZMXAMoCAAEACQprIZMXAMoCAAAA.Aehrick:BAAANQAECgQIBwAAAA==.Aentharion:BAAANQAECgUIDQAAAA==.Aeyn:BAAANQABCggIHQAAAA==.',
Af='Afflixen:BAAANQAECgMIAwABNQAECgYIDQADAAAAAA==.',
Ai='Aileen:BAABNQAECn8aAAIEAAgK1ApNigDyAQAEAAgK1ApNigDyAQAAAA==.Aimshot:BAAANQAECgUICQAAAA==.',
Al='Alakaz:BAAANQAECgEIAQAAAA==.Aldehyde:BAAANQADCgYIBwAAAA==.Alidoro:BAAANQADCgEIAQAAAA==.Alisonia:BAAANQADCgMIBQAAAA==.Alitikar:BAAANQADCgQIBAAAAA==.Alleximage:BAAANQAECgIIAQAAAA==.Alliancepaly:BAAANQADCgMIAwAAAA==.Alloy:BAAANQAECggICAAAAA==.Alorren:BAABNQAECn8cAAIFAAcKQxfrawDEAQAFAAcKQxfrawDEAQAAAA==.Aludor:BAAANQADCgEIAQAAAA==.',
Am='Ammo:BAAANQAECgEIAQABNQAECggIJgAGADweAA==.Amo:BAAANQABCggIIQABNQAECggIJgAGADweAA==.Amodegas:BAAANQAECgQIBAABNQAECggIJgAGADweAA==.Amodillo:BAABNQAECn8mAAMGAAgKPB45OACEAgAGAAgKPB45OACEAgAHAAMKARMRFwC8AAAAAA==.Amoe:BAAANQADCggICwABNQAECggIJgAGADweAA==.Amoesh:BAAANQABCggIDwABNQAECggIJgAGADweAA==.Amonra:BAAANQADCgYICQAAAA==.Amynrar:BAAANQADCggIEAAAAA==.',
An='Andriia:BAAANQADCggIFwAAAA==.Anecia:BAAANQADCgQIBAABNQAECgUIEQADAAAAAA==.Angyaras:BAACNQAFFH8OAAIIAAYKLySMAABDAgAIAAYKLySMAABDAgA1AAQKfyAAAggACQpaJoMBALYDAAgACQpaJoMBALYDAAAA.Animos:BAAANQADCgMIAwAAAA==.',
Ap='Apiix:BAABNQAECn8kAAIJAAkKThdMkABeAgAJAAkKThdMkABeAgAAAA==.',
Ar='Araaras:BAAANQAFFAEIAQAAAA==.Araiguma:BAAANQAECgcIDQABNQAFFAgIKQAEAPseAA==.Arcaisme:BAAANQAECgYIDgAAAA==.Arcticsnow:BAAANQAECgUIEgAAAA==.Ariealla:BAAANQADCgUIBQAAAA==.Arkose:BAAANQAECgEIAQAAAA==.',
As='Aschen:BAAANQADCgIJAwAAAA==.Ashlyngrace:BAAANQAECgUIDwABNQAECgkJMQAFAOofAA==.Ashlynne:BAABNQAECn8xAAMFAAkK6h+kEwAtAwAFAAkK6h+kEwAtAwAKAAEKAABVQwEqAAAAAA==.Aspensong:BAAANQAECgUIDQAAAA==.Astracious:BAAANQAECgMIAwAAAA==.Astrayice:BAAANQADCgQIBQAAAA==.',
At='Atarkormu:BAAANQAECgQIDQABNQAECggIIAALAJsTAA==.Atax:BAAANQAECgUIDQAAAA==.Athená:BAAANQAECgQIBwAAAA==.Atulkan:BAAANQAECgQIDQAAAA==.',
Au='Aurelitrasza:BAAANQAECgEIAQAAAA==.',
Av='Avalar:BAAANQADCgYIBgAAAA==.Avrice:BAAANQAECgUIBwAAAA==.Avris:BAAANQAECgEIAQAAAA==.',
Ay='Ayayaras:BAAANQAFFAMIBAABNQAFFAYIDgAIAC8kAA==.Ayddayd:BAAANQADCgQICAAAAA==.Aylianya:BAAANQAECgUICQABNQAECgkJMQAFAOofAA==.',
Az='Azimuth:BAAANQADCgYIBgAAAA==.',
Ba='Badshot:BAAANQADCgYIBgAAAA==.Bambu:BAAANQADCggIEwABNQAECgUIDQADAAAAAA==.Bamdruid:BAAANQADCggICgABNQAECgUIDQADAAAAAA==.Bamevoker:BAAANQAECgUIDQAAAA==.Bariggs:BAABNQAECn8eAAIMAAkK8iBtAgAVAwAMAAkK8iBtAgAVAwAAAA==.Barilia:BAAANQADCgQIBgAAAA==.',
Be='Beals:BAAANQAECgYIDAAAAA==.Beladra:BAAANQADCgQIBQAAAA==.Ben:BAABNQAECn8hAAINAAkKZxuZDwDoAgANAAkKZxuZDwDoAgAAAA==.Beriadan:BAABNQAECn8oAAIKAAgKVyCTKQDYAgAKAAgKVyCTKQDYAgAAAA==.Bevee:BAABNQAECn8nAAMCAAkK5B/nDwBLAwACAAkK5B/nDwBLAwAOAAEKAACZqAEwAAAAAA==.',
Bi='Bigwheels:BAAANQADCgYIBAAAAA==.Bisque:BAAANQADCgUIBQAAAA==.Bitemare:BAAANQADCgIIAgABNQAECgUICgADAAAAAA==.Bixii:BAAANQADCgYIBgAAAA==.',
Bl='Bleddwen:BAAANQAECgUIEAAAAQ==.Blindseer:BAAANQABCgIIAgAAAA==.Bloodjustice:BAAANQAECgQIBAAAAA==.Blrsama:BAAANQAECgIIAwAAAA==.',
Bo='Bohrnir:BAAANQADCgUIBQAAAA==.Boozelee:BAAANQADCgMIAwAAAA==.Borealsnow:BAAANQADCgQIBAAAAA==.Bozo:BAAANQAECgcIDQAAAA==.Boüh:BAAANQAECgYIEQAAAA==.',
Br='Brutalix:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesonyou:BAABNQAECn8dAAMCAAgKMwyqfQCdAQACAAgKMwyqfQCdAQAOAAcKDwUYCQEJAQAAAA==.Burnadine:BAAANQAECgUICwAAAA==.Burnswhnpee:BAABNQAECn8bAAIPAAgKcROOeQDyAQAPAAgKcROOeQDyAQAAAA==.',
Ca='Caliie:BAAANQAECgQIDAAAAA==.Callektra:BAAANQADCggICwAAAA==.Callira:BAAANQADCgYIBgAAAA==.Calzypher:BAAANQADCgEIAQAAAA==.Captclamslam:BAAANQAECgIIAgAAAA==.Carhop:BAAANQADCgIIAgAAAA==.Caverick:BAAANQADCggICAAAAA==.Caw:BAAANQADCgMIAwABNQAECgIIAgADAAAAAA==.Cayuga:BAAANQADCgUICAAAAA==.',
Ch='Charå:BAAANQADCgUIBQAAAA==.Chintakari:BAABNQAECn8ZAAIEAAcKnwwcngDGAQAEAAcKnwwcngDGAQAAAA==.',
Cl='Clickër:BAAANQADCgIIAgABNQAECgcIFwACAO8gAA==.',
Co='Cocidiae:BAAANQADCggIEgAAAA==.Confusious:BAACNQAFFH8KAAIFAAUKGBLrDAB5AQAFAAUKGBLrDAB5AQA1AAQKfyQAAgUACQryHfMdAPICAAUACQryHfMdAPICAAAA.Coppers:BAAANQADCggIBAAAAA==.Coree:BAABNQAECn8YAAIQAAUKOBATEAAfAQAQAAUKOBATEAAfAQAAAA==.Cornflower:BAAANQAECgYICAABNQAECgcIIgAEAMsUAA==.Corvaan:BAABNQAECn8XAAIRAAkK2w6YKgDpAQARAAkK2w6YKgDpAQAAAA==.Corvhuunta:BAAANQAFFAIIAgAAAA==.',
Cr='Craft:BAAANQADCgMIAwAAAA==.Creg:BAAANQADCggIIgABNQAECgUICQADAAAAAA==.Crowbarr:BAAANQADCgYICwAAAA==.Cryostatic:BAAANQAECgQIBwABNQAECgUIDAADAAAAAA==.',
Cu='Cultel:BAABNQAECn8lAAISAAkKfhnRCABgAgASAAkKfhnRCABgAgAAAA==.Cuulon:BAAANQADCgQIBgAAAA==.',
Cy='Cyendia:BAABNQAECn8ZAAIKAAcKAQiRnABaAQAKAAcKAQiRnABaAQAAAA==.Cynlea:BAAANQADCgYJCgAAAA==.',
Da='Daddyraz:BAAANQAECgUIDQAAAA==.Daemonquiver:BAAANQAECgUICQAAAA==.Dahtotems:BAABNQAECn8fAAIKAAkKkyS+BgCyAwAKAAkKkyS+BgCyAwAAAA==.Daphcelyn:BAAANQAECgIIAwAAAA==.Dariusz:BAABNQAECn8bAAITAAcKvg7HQwCgAQATAAcKvg7HQwCgAQAAAA==.Darkalen:BAABNQAECn8gAAILAAgKmxMzQgDxAQALAAgKmxMzQgDxAQAAAA==.Darkfogg:BAAANQAECggICgAAAA==.Darklodus:BAAANQADCgYICwAAAA==.Darksethia:BAAANQADCgQIBAAAAA==.Darksoul:BAAANQADCgQIBAAAAA==.Dathea:BAACNQAFFH8aAAIFAAYKsiBCBAA4AgAFAAYKsiBCBAA4AgA1AAQKfzgAAgUACQpyIgYPAEkDAAUACQpyIgYPAEkDAAAA.Daxetanlock:BAABNQAECn8wAAMPAAkKWCOFIQD7AgAPAAgK6yKFIQD7AgAUAAQKdxzwKwAeAQAAAA==.Daxetans:BAAANQAECgIIAgABNQAECgkJMAAPAFgjAA==.',
De='Deathjingle:BAABNQAECn8uAAMVAAkK+BxDMwBbAgAVAAkKMBtDMwBbAgALAAcKMh44OQAfAgAAAA==.Deecayed:BAAANQAECgQIBQABNQAFFAIIBQAFAAIJAA==.Deecoy:BAAANQAECgQICAABNQAFFAIIBQAFAAIJAA==.Deemonic:BAAANQAECgQIBgABNQAFFAIIBQAFAAIJAA==.Deerslayer:BAAANQABCgIIAgAAAA==.Deetermined:BAACNQAFFH8FAAIFAAIKAgmeIwB7AAAFAAIKAgmeIwB7AAA1AAQKfzAAAgUACQp3IEMWABwDAAUACQp3IEMWABwDAAAA.Deloisela:BAABNQAECn8kAAIJAAkK3wuuwwD7AQAJAAkK3wuuwwD7AQAAAA==.Denalii:BAAANQADCggICAAAAA==.Denchy:BAAANQAECgUIDwAAAA==.Deylen:BAABNQAECn8dAAMCAAgKJwg6iQB9AQACAAgKJwg6iQB9AQAOAAEKAAC3xAEiAAAAAA==.Deyndine:BAABNQAECn8bAAMWAAYKphk8DgBsAQAWAAQKZB48DgBsAQAPAAUKOQwo1QAaAQAAAA==.',
Di='Dizzyglaive:BAAANQADCgYIDQAAAA==.',
Dl='Dlkffjj:BAAANQAECgEIAwAAAA==.',
Dm='Dmdk:BAABNQAFFH8HAAMBAAMKNSLzDAAGAQABAAMK6RrzDAAGAQAVAAIKIiF9FAC9AAAAAA==.Dmrwr:BAABNQAECn8ZAAIXAAgKdiRbHABFAwAXAAgKdiRbHABFAwAAAA==.',
Do='Dodson:BAAANQADCgEIAQAAAA==.Dorilax:BAAANQAECgIIBAABNQAECggIDwADAAAAAA==.Dottarus:BAAANQADCgUIBQABNQAECgUIBwADAAAAAA==.',
Dr='Draegloth:BAAANQAECggIAgAAAA==.Draelick:BAAANQABCgIIAgAAAA==.Driadora:BAAANQAECgYIDwAAAA==.Droataxm:BAABNQAECn8yAAIJAAkKcyCIPAANAwAJAAkKcyCIPAANAwAAAA==.Droataxpr:BAAANQAECgYIBgABNQAECgkJMgAJAHMgAA==.Drogath:BAAANQADCgcIDQAAAA==.',
Du='Duarraag:BAAANQADCgYICQAAAA==.',
['Dâ']='Dâvïd:BAABNQAECn8tAAIYAAgKExkaEgA7AgAYAAgKExkaEgA7AgAAAA==.',
['Dä']='Däß:BAAANQADCgEJAQAAAA==.',
['Dë']='Dëërez:BAABNQAECn8dAAIZAAcKIRWcKADXAQAZAAcKIRWcKADXAQABNQAFFAIIBQAFAAIJAA==.',
Ei='Eililis:BAAANQADCgYIBwAAAA==.',
El='Elani:BAAANQAECggIEwAAAA==.Elaynaa:BAAANQAECgUIEAAAAA==.Elidin:BAAANQADCgQIBAABNQABCggICgADAAAAAA==.Elishaunt:BAAANQAECgUIDAABNQABCggICgADAAAAAA==.Elleizah:BAAANQAECggICgABNQAECgkJLwAaAJIiAA==.Elleth:BAAANQAECgYICwAAAA==.Elliana:BAAANQAECgYIEwABNQAECgkJIAACACogAA==.Elogio:BAAANQADCgYIEAAAAA==.Elvoidra:BAAANQADCgUICQAAAA==.',
Em='Emanymton:BAAANQAECgIIAwAAAA==.Emiley:BAAANQAECgMIAwAAAA==.',
En='Envymeh:BAAANQADCggIGgAAAA==.',
Er='Erinn:BAAANQADCgYIBgAAAA==.Erisaria:BAAANQADCggICgAAAA==.Erixi:BAAANQAECgUIEAAAAA==.Eryn:BAAANQADCgEIAQAAAA==.',
Es='Esaria:BAAANQADCgEIAQAAAA==.',
Et='Etherns:BAAANQADCgIIAgAAAA==.',
Ev='Evissier:BAABNQAECn8nAAIWAAkK0iE2AQBVAwAWAAkK0iE2AQBVAwAAAA==.',
Ex='Excelimagust:BAAANQAECgUICgAAAA==.',
Fa='Faelada:BAAANQADCggIEgAAAA==.Faid:BAAANQAECgYIDQAAAA==.Failor:BAAANQADCgYIBgAAAA==.Faize:BAAANQADCgEIAQAAAA==.Falcdhruid:BAAANQAECgEIAQAAAA==.Farundi:BAAANQAECgQIBQAAAA==.',
Fe='Felana:BAAANQAECgQIBAABNQAECggIIAAIAOEaAA==.Felbutton:BAAANQAECgYICgAAAA==.Felsen:BAAANQAECgUICAABNQAECggIIAAIAOEaAA==.Felwit:BAABNQAECn8gAAIIAAgK4RroDABhAgAIAAgK4RroDABhAgAAAA==.Fennec:BAAANQAECgYIEgAAAA==.Feralie:BAAANQADCgYIBgAAAA==.Ferroz:BAAANQAECgQIEAABNQAECggIIAALAJsTAA==.Ferrozious:BAAANQAECgQICAABNQAECggIIAALAJsTAA==.',
Fl='Flamos:BAAANQAECgQIBAAAAA==.Flatline:BAAANQAECgQICQAAAA==.Florabelle:BAABNQAECn8iAAIEAAcKyxSYiQD0AQAEAAcKyxSYiQD0AQAAAA==.Florid:BAAANQADCggIHAAAAA==.',
Fo='Foshomomo:BAAANQAECgUIDQAAAA==.Fozzle:BAABNQAECn8lAAIbAAgKqhSECgAcAgAbAAgKqhSECgAcAgAAAA==.',
Fr='Frenndi:BAAANQAECgEIAQAAAA==.',
Fu='Fuknazuga:BAAANQAECgQIBwAAAA==.Furroz:BAAANQAECgQICAABNQAECggIIAALAJsTAA==.',
Fy='Fynedge:BAABNQAECn8fAAIOAAcKaggK5QBLAQAOAAcKaggK5QBLAQAAAA==.Fynnyntyss:BAABNQAECn8dAAIcAAgKYQxODACPAQAcAAgKYQxODACPAQAAAA==.Fyrè:BAABNQAECn8mAAIEAAgKtB3FLgDfAgAEAAgKtB3FLgDfAgAAAA==.',
Ga='Garthe:BAAANQADCgEIAQAAAA==.',
Ge='Gelilla:BAAANQADCgUIAgAAAA==.Geoma:BAAANQAECgMIAwAAAA==.Gerlock:BAAANQAECgUIBQAAAA==.',
Gh='Ghastrider:BAAANQABCgEIAQAAAA==.Ghostlyt:BAAANQABCgEJAQAAAA==.',
Gi='Gigatin:BAABNQAECn8cAAILAAcKhR8IKQB3AgALAAcKhR8IKQB3AgAAAA==.Githnor:BAABNQAECn8mAAIOAAgKNwimyQCCAQAOAAgKNwimyQCCAQAAAA==.',
Go='Goldal:BAAANQAECgQICQAAAA==.Gorellan:BAAANQADCgYIEgAAAA==.',
Gr='Grimwharf:BAAANQAECgEIAQAAAA==.Grum:BAAANQADCgQIBgAAAA==.Grunaelyn:BAAANQAECgYIEgAAAA==.',
Gu='Guerrier:BAABNQAECn8cAAIdAAgKYAnnNwCMAQAdAAgKYAnnNwCMAQAAAA==.Guiong:BAAANQADCgYICgAAAA==.',
Gy='Gynx:BAAANQAECgEIAQAAAA==.',
['Gö']='Göttlich:BAAANQADCgUIBQABNQADCgUIBwADAAAAAA==.',
Ha='Haidas:BAAANQAECgYIBgAAAA==.Hardcheese:BAAANQADCgQIBAAAAA==.Hasuna:BAAANQADCgQIBAAAAA==.',
He='Heikuro:BAAANQAECgUIEgAAAA==.Heybestie:BAAANQADCggICAAAAA==.',
Hi='Hillo:BAAANQAECgEIAQAAAA==.',
Ho='Holychonks:BAAANQADCgcIEAAAAA==.Hommy:BAAANQADCggIEQAAAA==.Honadain:BAAANQAECgQIBgAAAA==.Honornight:BAAANQADCggJDgAAAA==.Hordestalker:BAAANQADCgUIBQAAAA==.Houtu:BAABNQAECn8oAAIFAAgKbBLSbADBAQAFAAgKbBLSbADBAQAAAA==.',
Hw='Hweilan:BAAANQADCgYIDAAAAA==.Hwil:BAAANQADCgYIBgAAAA==.',
Hy='Hydrokill:BAAANQADCggICAAAAA==.Hypnos:BAAANQAECgUICgAAAA==.',
['Hö']='Hölyföx:BAAANQAECgEIAQAAAA==.',
Ia='Iamearl:BAAANQAECgUIEQAAAA==.',
In='Incidental:BAABNQAECn8xAAINAAkKISIxCQA8AwANAAkKISIxCQA8AwAAAA==.Inconell:BAAANQAECgQIDgAAAA==.Invega:BAAANQAECgIJAwAAAA==.',
Ir='Iric:BAAANQADCgQIBgAAAA==.Irino:BAAANQADCgUIBQAAAA==.',
Is='Isabelle:BAAANQAECgYIDwAAAA==.',
It='Itsredbush:BAAANQADCgQIBAAAAA==.',
Iz='Izaer:BAAANQAECgQIDgAAAA==.Iziel:BAAANQAECgYIDgAAAA==.Izumex:BAAANQAECgMIAwAAAA==.',
Ja='Jabzaklok:BAAANQAECgUICQAAAA==.Jacky:BAAANQAFFAEIAQABNQAFFAUIDAAeAMMYAA==.Jahirah:BAABNQAECn8cAAIJAAcKZhNq4wC/AQAJAAcKZhNq4wC/AQABNQAECgcIGwAVAJ8MAA==.Jahmunkey:BAAANQADCggICAABNQAECgkJGQAOAOAaAA==.Jaida:BAAANQAECgQIDAAAAA==.Jaleika:BAABNQAECn8dAAMJAAgKiAqa2wDNAQAJAAgKiAqa2wDNAQAbAAEKAACVTAAsAAAAAA==.Jarius:BAAANQAECgQICAABNQAECgUIBQADAAAAAA==.Jayabalard:BAAANQAECgIIAwABNQAECggIIAALAJsTAA==.',
Je='Jean:BAABNQAECn8yAAIEAAgKHiHKHwAXAwAEAAgKHiHKHwAXAwAAAA==.Jeez:BAABNQAECn8WAAIfAAkKQRoYCgCaAgAfAAkKQRoYCgCaAgAAAA==.Jesmaríe:BAAANQAECgQICgAAAA==.',
Jo='Johadd:BAAANQADCgEIAQAAAA==.Jonnathen:BAAANQAECgUIBQAAAA==.Jonyy:BAAANQADCgYIDgAAAA==.Jorianna:BAAANQAECgUIDQAAAA==.Joru:BAACNQAFFH8cAAIgAAcKeBhyAACPAgAgAAcKeBhyAACPAgA1AAQKfzIAAiAACQqTJiYCAI0DACAACQqTJiYCAI0DAAAA.',
Ju='Jurauth:BAAANQABCgQIBAAAAA==.Justyna:BAAANQAECgYIDgAAAA==.Juze:BAAANQAECgQICQABNQAECgMIAQADAAAAAQ==.',
Ka='Kaai:BAAANQAECgYIDQAAAA==.Kabaul:BAABNQAECn8yAAIXAAkKziTMDgCEAwAXAAkKziTMDgCEAwAAAA==.Kabir:BAABNQAECn8XAAIJAAcKWQwj3wDHAQAJAAcKWQwj3wDHAQAAAA==.Kadria:BAAANQAECgUIEAAAAA==.Kailanii:BAAANQAECgQIBQABNQAECgUICgADAAAAAA==.Kaiyne:BAAANQAECgMIAwAAAA==.Kalagon:BAAANQADCgEIAQAAAA==.Kalaman:BAAANQADCgQICAAAAA==.Kalito:BAAANQADCgMIAwAAAA==.Kallivar:BAAANQAECgQIDgABNQAECgkJNwALAJUjAA==.Kamb:BAAANQAECgUIDQAAAA==.Karalee:BAAANQAECgQIDAAAAA==.Katieey:BAACNQAFFH8cAAIFAAcK7iPhAQCbAgAFAAcK7iPhAQCbAgA1AAQKfyQAAgUACQrzJg0DALYDAAUACQrzJg0DALYDAAAA.Kaybee:BAAANQAECgUICgAAAA==.Kayil:BAABNQAECn8mAAIeAAkKFRR9HABeAgAeAAkKFRR9HABeAgAAAA==.',
Ke='Kedalin:BAAANQAECgEIAQAAAA==.Kennyloggy:BAACNQAFFH8RAAIhAAcKtxc4BQBMAgAhAAcKtxc4BQBMAgA1AAQKfzQAAiEACQoLJWYGAKEDACEACQoLJWYGAKEDAAAA.Kevris:BAAANQAECgYIDwABNQAECgcIGwAVAJ8MAA==.Keydan:BAAANQAECgUIDAAAAA==.',
Kh='Khalunna:BAAANQADCgYIBgAAAA==.Khyn:BAAANQAECgQIBAABNQAECgUIBwADAAAAAA==.',
Ki='Kianni:BAAANQAECgIIAgAAAA==.Kirafrayen:BAAANQAECgEJAQABNQAECggIDQADAAAAAA==.',
Kl='Klassy:BAABNQAECn8cAAIMAAgKuw58BwD4AQAMAAgKuw58BwD4AQAAAA==.',
Ko='Koppi:BAAANQAECgQICAAAAA==.Korru:BAAANQAECgQIBgAAAA==.Kotie:BAAANQAECgUIBQAAAA==.',
Kr='Kramz:BAAANQADCgcIDQAAAA==.Kreoss:BAAANQADCgQIBAABNQAECgkJJwAFALQPAA==.Kronar:BAABNQAECn8sAAIEAAcK4gvRtgCSAQAEAAcK4gvRtgCSAQAAAA==.Krongar:BAAANQADCgQIBAAAAA==.Krumblo:BAEANQAECgUIDwABNQAECgcIHwAJAFEQAA==.Kryztof:BAAANQADCgYIBgAAAA==.',
Ku='Kuiraptor:BAAANQADCgcIDgAAAA==.Kumojo:BAAANQADCgEIAQAAAA==.Kunea:BAAANQADCgYIBgAAAA==.Kungfujace:BAAANQADCgYICwAAAA==.',
Ky='Kyrgune:BAAANQAECgQICAAAAA==.',
['Kà']='Kàhlan:BAAANQADCgYIBgAAAA==.',
La='Lahabreaa:BAAANQAECgEIAQAAAA==.Laoftey:BAABNQAECn8gAAIFAAkK9CCaDwBFAwAFAAkK9CCaDwBFAwAAAA==.Larquin:BAABNQAECn8bAAMVAAcKnwzRbABcAQAVAAcKnwzRbABcAQABAAUKdgbgdQDDAAAAAA==.Lasmori:BAAANQAECgYIDwABNQAECggIEwADAAAAAA==.Laurenorder:BAAANQAECgUICgAAAA==.Laxxbroo:BAAANQAECgMIAwAAAA==.',
Le='Leam:BAAANQAECgUIEQAAAA==.Leglock:BAABNQAECn8bAAMRAAcKWBICLQDWAQARAAcKWBICLQDWAQATAAIKjQPWhgBVAAAAAA==.Leiff:BAAANQADCggIEQAAAA==.Leprhicon:BAAANQAECgMIBAAAAA==.Lesbihonest:BAAANQAECggIDQAAAA==.',
Li='Liendria:BAABNQAECn8dAAIEAAcKAhlfgwACAgAEAAcKAhlfgwACAgAAAA==.Lifensoftpaw:BAACNQAFFH8WAAINAAYKZxl1BAD2AQANAAYKZxl1BAD2AQA1AAQKfy4AAw0ACQr1IssOAPMCAA0ACQr1IssOAPMCACIABQoYILQSALYBAAAA.Lightemup:BAAANQAECgMIBQAAAA==.Lightkeeper:BAAANQABCgQIAgAAAA==.Likkash:BAAANQAECgQIBgABNQAECggIIAALAJsTAA==.Limildea:BAAANQADCgQIBgAAAA==.Linthabeela:BAAANQADCgEIAQAAAA==.Liquidchiken:BAAANQAECgQIBAAAAA==.Lishalthen:BAAANQADCggJFwAAAA==.Littletouch:BAAANQADCgIIAgAAAA==.Livicecia:BAAANQAECgcIEgAAAA==.',
Lu='Lucciana:BAAANQAECgQICAAAAA==.Lucielinna:BAAANQADCgUIBQABNQAECgQIBwADAAAAAA==.Luckiiem:BAABNQAECn8mAAIJAAkKWyExLwAuAwAJAAkKWyExLwAuAwAAAA==.Luisfriendsn:BAABNQAECn8aAAIJAAkKFBFajgBiAgAJAAkKFBFajgBiAgABNQAECgkJKwAJAAwZAA==.Lumbo:BAEBNQAECn8fAAMJAAcKURAs5gC6AQAJAAcKURAs5gC6AQAbAAEK0gT1SAAxAAAAAA==.Lunare:BAAANQADCgUJBQAAAA==.Lunarkin:BAAANQAECgQIBQAAAA==.Luthane:BAAANQAECgUIEAAAAA==.',
Ly='Lykinea:BAAANQADCgYIBgAAAA==.Lyono:BAAANQADCggIDgABNQAECggIIAALAJsTAA==.Lytebrite:BAABNQAECn8qAAICAAkK7xLzSQA+AgACAAkK7xLzSQA+AgAAAA==.',
['Lí']='Líu:BAAANQADCggICAAAAA==.',
['Lü']='Lümßo:BAEANQAECgYIDQABNQAECgcIHwAJAFEQAA==.',
Ma='Mainos:BAAANQADCgUIBwAAAA==.Maiyr:BAAANQAECgIIAgAAAA==.Makanai:BAAANQAECgYIDgAAAA==.Makishi:BAABNQAECn8XAAISAAcKSR29CABjAgASAAcKSB29CABjAgAAAA==.Malakenjin:BAAANQABCgUIBAAAAA==.Malferious:BAAANQADCgIIAgAAAA==.Malfura:BAAANQAECgUIDgAAAA==.Malário:BAAANQAECgYIDQAAAA==.Manamontana:BAAANQADCgYIEwABNQAECgUICgADAAAAAA==.Mandragoria:BAAANQADCgQIBAABNQAECgYIGwAWAKYZAA==.Mattedfurry:BAAANQAECgIIAgAAAA==.Maube:BAAANQAECgEIAQABNQAFFAUICgAjAHoNAA==.Mazzarzul:BAAANQAECgMIAQABNQAECgkJPgAMAO4fAA==.',
Me='Meebles:BAABNQAECn8mAAIYAAgKGQ1yIwB1AQAYAAgKGQ1yIwB1AQAAAA==.Meiana:BAABNQAECn8dAAIkAAgKohZfEwAWAgAkAAgKohZfEwAWAgAAAA==.Melasmus:BAAANQADCgYIBgAAAA==.Mes:BAAANQAECgcIDQAAAA==.',
Mi='Micklaa:BAAANQAECgUIEwAAAA==.Midgeto:BAAANQADCgUIBQAAAA==.Miebi:BAAANQADCgYICwABNQAECggINAAiAOghAA==.Milkbunny:BAAANQADCgUICQAAAA==.Mingtai:BAAANQAECgUIEAAAAA==.Misskaitlyn:BAAANQADCgcIBwAAAA==.Mixen:BAAANQAECgQIBAABNQAECgYIDQADAAAAAA==.',
Mo='Moirrah:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Moonriver:BAABNQAECn8aAAIFAAgKrRoORQBKAgAFAAgKrRoORQBKAgAAAA==.Moonsinde:BAAANQAECggICQAAAA==.Moranta:BAABNQAECn8XAAMGAAcK8hMlewCkAQAGAAcK8hMlewCkAQAeAAYK5gVDSQDxAAAAAA==.Moressandra:BAAANQAECgQIAwAAAA==.Morfina:BAAANQAECgMIAgABNQAECgQIBQADAAAAAA==.Morgaes:BAAANQAECgQICwAAAA==.Mortannon:BAABNQAECn8ZAAIEAAcKExPXegAVAgAEAAcKExPXegAVAgAAAA==.Morîarty:BAAANQADCgIIAgAAAA==.Mozzare:BAAANQADCgYIBgABNQAECggIJgAYABkNAA==.',
Mu='Mushy:BAAANQADCgEIAQAAAA==.',
My='Mydruid:BAAANQAECggIDgABNQAECgkJLwAaAJIiAA==.Mysticarc:BAAANQADCgYIBgAAAA==.Mysticmurv:BAABNQAECn8mAAIJAAkK5AmkxQD3AQAJAAkK5AmkxQD3AQAAAA==.Mystieren:BAAANQAECgQICQABNQAECgkJHwAWADIRAA==.Mywarlock:BAABNQAECn8vAAMaAAkKkiJ3CQBBAwAaAAkKBCJ3CQBBAwAlAAcKYBlvHgDbAQAAAA==.',
Na='Nalgotica:BAAANQAFFAEIAQAAAA==.Nalynahwe:BAAANQADCggJGwAAAA==.Narima:BAAANQAECgUIEAAAAA==.Nathronso:BAAANQADCgUIBQAAAA==.Nauticâ:BAAANQABCgYIDAAAAA==.Navirose:BAAANQAECgUIBQAAAA==.',
Ne='Necromos:BAAANQAECggICAAAAA==.Neltheron:BAAANQADCgMIAwAAAA==.',
Nh='Nhala:BAAANQADCgUICAABNQAECgUIBwADAAAAAA==.',
Ni='Niavarr:BAAANQAECgYIBwAAAA==.Nibblefluff:BAAANQADCgMIAwAAAA==.Nightestrike:BAAANQAECgQICgAAAA==.Ninali:BAAANQAECgYIDgAAAA==.Nivek:BAAANQADCgUICQAAAA==.',
No='Noralai:BAAANQADCgUIBAAAAA==.Nore:BAAANQAECgQICgAAAA==.',
Nt='Ntviss:BAAANQADCgYIBgAAAA==.',
Ny='Nyali:BAAANQAECgUIBQABNQAECgUICgADAAAAAA==.',
['Nà']='Nàdya:BAABNQAECn8xAAMFAAkKbBy4JwDDAgAFAAkKbBy4JwDDAgAKAAEKRg+3LQE3AAAAAA==.',
['Nî']='Nîghtshade:BAAANQADCgYIBwAAAA==.',
Ob='Obidin:BAAANQADCggICAABNQAECgQIDQADAAAAAA==.Oblivions:BAABNQAECn8jAAIXAAkKEyAJMQD4AgAXAAkKEyAJMQD4AgAAAA==.',
Od='Odasa:BAAANQAECgUIEwAAAA==.',
Og='Ogion:BAAANQADCggICAAAAA==.',
Ol='Olahn:BAAANQAECgUIBwAAAA==.',
On='Onekark:BAABNQAECn8YAAIFAAgKMRbfUwAUAgAFAAgKMRbfUwAUAgAAAA==.Onlysins:BAAANQADCggIGwAAAA==.',
Or='Orckus:BAAANQAECgUICAAAAA==.Oreosbunny:BAABNQAECn8fAAIOAAcK+x77cgBEAgAOAAcK+x77cgBEAgAAAA==.Orìhimè:BAAANQABCgQIBAAAAA==.',
Pa='Padma:BAAANQADCgUIBAAAAA==.Pandaburn:BAABNQAECn8aAAIJAAcKjRhOogA8AgAJAAcKjRhOogA8AgAAAA==.Pandalock:BAAANQADCgYIBgAAAA==.Pandsome:BAAANQADCgYICwAAAA==.Paroxism:BAACNQAFFH8KAAIhAAUKBxcLDwB0AQAhAAUKBxcLDwB0AQA1AAQKfygAAiEACQrpI6ARADgDACEACQrpI6ARADgDAAAA.Parzival:BAAANQAECgMIAwABNQAECgYIDQADAAAAAA==.Pawsome:BAAANQADCggIDgAAAA==.',
Pe='Peanût:BAABNQAECn8ZAAMZAAkK1ByxEgC2AgAZAAgKbx2xEgC2AgAhAAIK8wdRmwBoAAAAAA==.Peautiful:BAAANQAECgUIBgAAAA==.',
Ph='Phaket:BAABNQAECn8gAAIEAAkK4ByxQQCkAgAEAAkK4ByxQQCkAgAAAA==.',
Pi='Picaduro:BAAANQADCgYICQAAAA==.Picture:BAAANQADCgcIEgABNQAFFAUICgAFABgSAA==.Pika:BAABNQAECn8dAAQfAAgKSQ8lFAC1AQAfAAcK0hAlFAC1AQAhAAUKXgiOcwD4AAAZAAQK8QPmXgCFAAAAAA==.Pingvinas:BAAANQADCgQIBAAAAA==.Pippá:BAAANQAECgUIBwAAAA==.',
Po='Pockethealer:BAAANQAECgEIAQAAAA==.Polonius:BAAANQAECgYIEAAAAA==.Potato:BAAANQADCgIIAgAAAA==.',
Pr='Priss:BAAANQADCgYIBgAAAA==.Probation:BAAANQADCgUICAAAAA==.',
Pu='Puchideperro:BAAANQAECgIIBAAAAA==.Pujo:BAAANQABCggIDgAAAA==.',
Pw='Pwil:BAAANQABCgMIAgABNQADCgYIBgADAAAAAA==.',
Py='Pythe:BAABNQAECn8mAAIOAAgKdSG5NwDuAgAOAAgKdSG5NwDuAgAAAA==.',
Qa='Qap:BAAANQAECgIIAwAAAA==.',
Qi='Qingu:BAABNQAECn8kAAQcAAkKOA7ICQDeAQAcAAgKWA/ICQDeAQAkAAcKTActIgA3AQAmAAcKAwTqMQAGAQAAAA==.',
Qu='Qualnorr:BAAANQAECgQICAAAAA==.Quelastraaza:BAAANQADCgQIBAAAAA==.Queldraayan:BAAANQAECgUIDQAAAA==.Quinnter:BAEANQAECgUICgAAAA==.Quixii:BAEANQADCgQIBAABNQAECgUICgADAAAAAA==.Quixxie:BAEANQAECgQIBAABNQAECgUICgADAAAAAA==.',
Qw='Qwil:BAAANQABCgYICgABNQADCgYIBgADAAAAAA==.',
Ra='Radagon:BAABNQAECn8gAAMCAAkKbA2QYgDuAQACAAkKbA2QYgDuAQAOAAcKSRNwygCAAQABNQAECggIJgADAAAAAA==.Radalas:BAABNQAECn8dAAIjAAcKIx9YEwBrAgAjAAcKIx9YEwBrAgAAAA==.Radreliris:BAAANQAECgQICQAAAA==.Raelithi:BAAANQABCgUIAwAAAA==.Rahdalas:BAAANQADCgEIAQABNQAECgcIHQAjACMfAA==.Rainfall:BAAANQADCgYIBgAAAA==.Rally:BAAANQAECgYIDgAAAA==.Ramcco:BAEBNQAECn8fAAIeAAcKaR1THABfAgAeAAcKaR1THABfAgAAAA==.Ranelle:BAABNQAECn8mAAIGAAgKPhnbRgBOAgAGAAgKPhnbRgBOAgAAAA==.Rasmira:BAAANQAECgEIAwAAAA==.Ravenis:BAACNQAFFH8MAAIlAAUKmxMyBwCXAQAlAAUKmxMyBwCXAQA1AAQKfyUAAiUACQpmIhUEAFcDACUACQpmIhUEAFcDAAAA.',
Re='Reanette:BAAANQADCgQIBAABNQAFFAEIAQADAAAAAA==.Rebekkah:BAAANQADCgQIBAAAAA==.Reedem:BAAANQAECgYIEAAAAA==.Regilock:BAACNQAFFH8cAAQPAAcKDyJhAQCeAgAPAAcKDyJhAQCeAgAUAAIKqhIgDwCZAAAWAAEKAAAgDgBIAAA1AAQKf4kABA8ACQruJh4AABQEAA8ACQruJh4AABQEABQABAplJT8bAJIBABYAAgp7Gl0ZALsAAAAA.Reikí:BAAANQAECgQIBgABNQAECggIKAAKAFcgAA==.Relarria:BAAANQAECgEIAQAAAA==.Renbe:BAAANQADCgEIAQAAAA==.Revgard:BAAANQAECgQICwAAAA==.',
Rh='Rhaenyrra:BAABNQAECn8YAAIbAAgK2QUnGAA2AQAbAAgK2QUnGAA2AQAAAA==.Rhaily:BAAANQADCgIIAgAAAA==.Rhallin:BAAANQAECgUIBwAAAA==.Rhasalgul:BAAANQAECgQIBAAAAA==.',
Ro='Ronso:BAAANQADCgQJBAAAAA==.Rosiel:BAAANQABCgQIBAAAAA==.Rowain:BAABNQAECn8mAAMfAAgKBxC5HwAWAQAfAAYKCwm5HwAWAQAZAAgKFgOkRQD9AAAAAA==.Rozemary:BAAANQADCggICAAAAA==.',
Ry='Rylacus:BAAANQAECgUIEAAAAA==.Rylii:BAAANQAECgUICgAAAA==.',
Sa='Saanda:BAAANQADCggIEAAAAA==.Safael:BAAANQADCggIDgAAAA==.Salandre:BAAANQAECgQIBAAAAA==.Sarlef:BAABNQAECn8cAAIIAAcK5gc2IgA0AQAIAAcK5gc2IgA0AQAAAA==.',
Sc='Scarm:BAABNQAECn8mAAIPAAkKlx6cEgBBAwAPAAkKlx6cEgBBAwAAAA==.Scathed:BAAANQAECggIDAAAAA==.Scorpix:BAAANQAECgIIAgAAAA==.',
Se='Seaflower:BAAANQAECgIIAQAAAA==.Seig:BAAANQADCgQIBAAAAA==.Sellidra:BAABNQAECn8dAAIEAAcKDQnWrQCkAQAEAAcKDQnWrQCkAQAAAA==.Serenitara:BAAANQADCggIEwAAAA==.Serharimia:BAAANQADCgQIBAAAAA==.Serifanlord:BAAANQAECgQIBgAAAA==.Seyana:BAAANQAECgUIDgAAAA==.',
Sh='Shaaddow:BAAANQAECgEIBQAAAA==.Shaffer:BAAANQAECgYIDAAAAA==.Shamanlady:BAAANQAECgQIBAAAAA==.Shamwhoa:BAAANQABCgQIBwAAAA==.Shellshocker:BAABNQAECn8aAAIKAAkKxiWHBgC0AwAKAAkKxiWHBgC0AwAAAA==.Sheng:BAAANQADCgUJBQAAAA==.Shermantånk:BAAANQADCgYICAAAAA==.Shey:BAAANQADCggIDAAAAA==.Sheydon:BAAANQADCggICgAAAA==.Shikigamï:BAAANQAECgEJAQABNQAECggIIwAeACUkAA==.Shikï:BAABNQAECn8jAAMeAAgKJSSuCQBDAwAeAAgKJSSuCQBDAwAGAAQKxBu2jgBlAQAAAA==.Shivermoón:BAABNQAECn8kAAIZAAgKFQyBMgCCAQAZAAgKFQyBMgCCAQAAAA==.',
Si='Siegbane:BAAANQAECgMIAwAAAA==.Sigesar:BAAANQADCggIIwAAAA==.Sigrún:BAAANQAECgYIDgAAAA==.Simpforsouls:BAAANQADCgMIAwAAAA==.Sinsimella:BAAANQAECgEIAQAAAA==.',
Sk='Skullash:BAAANQADCgcIBwAAAA==.Skywatcher:BAABNQAECn8XAAIEAAcKZgPh2gBGAQAEAAcKZgPh2gBGAQAAAA==.',
Sl='Slaughtering:BAAANQAECgIIAgAAAA==.',
Sm='Smitemare:BAAANQAECgMIAwABNQAECgUICgADAAAAAA==.',
Sn='Sneakmode:BAAANQAECgIIAgAAAA==.Sneakyz:BAAANQAECgQIBAAAAA==.Snicky:BAAANQAECgEJAQAAAA==.',
So='Solare:BAAANQAECggIAgAAAA==.Sonwarr:BAABNQAECn8fAAIGAAkKaRhPMwCYAgAGAAkKaRhPMwCYAgAAAA==.',
Sp='Spliphtoker:BAAANQAECgEIAQAAAA==.',
St='Stabsolutely:BAAANQADCgUJBQABNQAECgUICgADAAAAAA==.Steelpen:BAAANQAECgQIBQAAAA==.Stenston:BAAANQAECgYIEQAAAA==.Sterede:BAAANQAECgEIAQAAAA==.Stitchwhich:BAAANQAECgYICQAAAA==.Stonehenge:BAABNQAECn8dAAIOAAcKsws8xgCJAQAOAAcKsws8xgCJAQAAAA==.Stormb:BAAANQAECggIBAAAAA==.Stormwolves:BAAANQAECgQIBAAAAA==.',
Su='Summers:BAAANQAECggIDwAAAA==.Surfclub:BAAANQAECgYIBAAAAA==.',
Sy='Sylphr:BAAANQAECgEIAQABNQAFFAEIAQADAAAAAA==.Sylphrená:BAAANQAECgEIAQABNQAECggIKAAKAFcgAA==.Sylphwild:BAABNQAECn8XAAMYAAkK6hPPEgAwAgAYAAkK6hPPEgAwAgAhAAMKxArekQCKAAABNQAFFAEIAQADAAAAAA==.Sylvara:BAAANQAECgQICgAAAA==.Synkinz:BAABNQAECn8XAAIKAAcKkhWgbADWAQAKAAcKkhWgbADWAQAAAA==.Syntec:BAAANQABCgMIAgAAAA==.Syreite:BAABNQAECn8ZAAIYAAcKKxZMGADmAQAYAAcKKxZMGADmAQAAAA==.',
Ta='Tacori:BAAANQAECgMIBAABNQAECgQICAADAAAAAA==.Taessa:BAAANQAECgIIAgAAAA==.Tainipuni:BAAANQADCgYIBgAAAA==.Tallic:BAABNQAECn8lAAIjAAkKCxunEQCDAgAjAAkKCxunEQCDAgAAAA==.Talynayl:BAAANQADCgUIBwAAAA==.Tamarah:BAAANQAECgEIAQAAAA==.Tandemonium:BAAANQAECgYIDAABNQAFFAIIBwATAH8eAA==.Taniz:BAABNQAECn8iAAMEAAkKchuBOQC7AgAEAAkKchuBOQC7AgAdAAcKaRM+MgC3AQAAAA==.Tarsi:BAAANQAECgUIEAAAAA==.Taseg:BAAANQABCggICgAAAA==.',
Td='Td:BAABNQAFFH8bAAIKAAcKoyWOAAAKAwAKAAcKoyWOAAAKAwABNQAFFAkJLgAdAKAmAA==.',
Te='Tearinurside:BAAANQAECgYIDgAAAA==.Telidrel:BAAANQADCgIIAwAAAA==.',
Tg='Tgi:BAAANQAECgQICAAAAA==.',
Th='Thaddeaus:BAABNQAECn8rAAIIAAgKlRr0CwB2AgAIAAgKlRr0CwB2AgAAAA==.Thaddeus:BAAANQAECgUIDQAAAA==.Thealin:BAAANQAECgQIBQAAAA==.Thebeefyone:BAAANQAECgQIDgAAAA==.Thecanadian:BAAANQADCgQIBAAAAA==.Thegreatmel:BAAANQADCgIIAgAAAA==.Therizin:BAAANQAECgQIBwAAAA==.Thesummoner:BAAANQAECgEIAQAAAA==.Thornel:BAAANQADCgEIAQAAAA==.Thorrek:BAAANQAECggIEQAAAA==.Thrallete:BAAANQADCgUIBQAAAA==.Thugnificent:BAAANQABCggIDwAAAA==.Thumpette:BAAANQAECgQIDgAAAA==.',
Ti='Tierant:BAAANQADCggIFwAAAA==.Tinaris:BAAANQADCgUICQABNQAECgcIHAALAIUfAA==.Tizaria:BAAANQAECgUIDgAAAA==.',
Tm='Tmai:BAAANQAECgYICwAAAA==.',
To='Tominaetor:BAAANQAECgQIBAAAAA==.Tookans:BAAANQABCgUIBQAAAA==.Tosoto:BAABNQAECn8pAAMIAAgKyxsXEgACAgAXAAgKjRPkggAQAgAIAAcK1xwXEgACAgAAAA==.Toxica:BAAANQADCgMIAwAAAA==.',
Tr='Travcula:BAABNQAECn8cAAIVAAgKtReLOwAwAgAVAAgKtReLOwAwAgAAAA==.Treefiddy:BAAANQADCgEIAgAAAA==.Trumpd:BAAANQADCgUIBQABNQAECgEIAQADAAAAAA==.',
Ts='Tso:BAAANQADCgEIAQAAAA==.',
Tt='Ttriton:BAAANQADCgEIAQAAAA==.',
Tu='Tuuwa:BAAANQADCgMIAwAAAA==.',
Ty='Tyernan:BAABNQAECn8fAAIOAAgKKAa04wBNAQAOAAgKKAa04wBNAQAAAA==.Tyrioz:BAABNQAECn8cAAMCAAcK0Rz3RwBEAgACAAcK0Rz3RwBEAgAOAAIKZQgiZQF1AAAAAA==.',
Tz='Tzavcat:BAABNQAECn8ZAAIZAAcK1wVKQwAMAQAZAAcK1wVKQwAMAQAAAA==.',
Uh='Uhtred:BAAANQAECggIAgAAAA==.',
Un='Unknownmage:BAAANQABCgIIAgAAAA==.',
Ur='Urbi:BAABNQAECn8VAAIXAAYKyg+ZzQBTAQAXAAYKyg+ZzQBTAQAAAA==.',
Uv='Uvsol:BAAANQAECgUICAAAAA==.',
Va='Vadailla:BAAANQAECgUIEQAAAA==.Vahrik:BAAANQADCgMIAwAAAA==.Valeirra:BAAANQADCgMIBQAAAA==.Valius:BAABNQAECn8cAAIkAAcKEyCqDACWAgAkAAcKEyCqDACWAgAAAA==.Valkyrae:BAAANQADCgQIBAAAAA==.Valornor:BAAANQAECgIJAgAAAA==.Vandill:BAABNQAECn8pAAIJAAgKIhbJsAAgAgAJAAgKIhbJsAAgAgAAAA==.Vaxis:BAAANQADCgcIEwAAAA==.',
Ve='Veasnacool:BAABNQAECn8lAAIEAAcKbxn4dgAeAgAEAAcKbxn4dgAeAgAAAA==.Vestrit:BAAANQADCgIIAgABNQAECggIKAAKAFcgAA==.',
Vi='Visren:BAAANQADCgIIAgAAAA==.',
Vo='Vongoethe:BAAANQABCgIIAgAAAA==.Vontote:BAABNQAECn8cAAILAAcKVBrYMwA7AgALAAcKVBrYMwA7AgAAAA==.Vorix:BAAANQAECgIIAgAAAA==.',
Vy='Vyluna:BAAANQADCggILgAAAA==.',
['Ví']='Víc:BAABNQAECn8XAAICAAcK7yDPMQCcAgACAAcK7yDPMQCcAgAAAA==.',
Wa='Wandorf:BAEANQAECgUIDQAAAA==.Warwolfe:BAABNQAECn8hAAMPAAkKTgnRmwCbAQAPAAkKxwjRmwCbAQAWAAIKHAqvHwB2AAAAAA==.Wayler:BAAANQADCggICAAAAA==.',
Wh='Whitewâlker:BAAANQABCgUIBQAAAA==.Whumpus:BAAANQADCgIIAgAAAA==.Whyn:BAAANQAECgUICQAAAA==.',
Wi='Willei:BAAANQADCgUICwAAAA==.Wixen:BAAANQAECgYIBgABNQAECgYIDQADAAAAAA==.',
Wo='Wolferunner:BAAANQAECgQICgAAAA==.Wondermang:BAAANQAECgMICQAAAA==.Woofhoof:BAAANQADCgQIBAAAAA==.Worgenwebb:BAAANQAECgUIDQABNQAECgkJIgAXAOofAA==.',
Xa='Xaiden:BAAANQADCgcJBwAAAA==.Xaldora:BAAANQADCgEIAQAAAA==.Xali:BAAANQAECgIIBAAAAA==.Xandrake:BAAANQAECgcIBwAAAA==.Xanthrens:BAAANQADCgQIBgAAAA==.',
Xd='Xdxvuu:BAAANQAECgUIDAAAAA==.',
Xe='Xerimok:BAAANQAECgUIEAAAAA==.',
Xi='Xinya:BAAANQAECgUIEAAAAA==.',
Xl='Xladykahlron:BAAANQADCgYIBgAAAA==.',
Xs='Xsavior:BAAANQAECggICgAAAA==.Xshando:BAAANQAECgMIBgAAAA==.Xsmkmonk:BAAANQAECgEIAQAAAA==.',
Xz='Xzephyr:BAABNQAECn8hAAIhAAgKlyIwEwAsAwAhAAgKlyIwEwAsAwAAAA==.',
Ya='Yamato:BAAANQAECgcIDQAAAA==.',
Ye='Yesmín:BAABNQAECn8dAAIGAAkKDxNSSgBDAgAGAAkKDxNSSgBDAgAAAA==.',
Yi='Yil:BAABNQAECn8fAAIGAAgKkBpARQBUAgAGAAgKkBpARQBUAgAAAA==.',
Yo='Youwas:BAAANQAECgUICAAAAA==.',
Ys='Yshtola:BAAANQADCgYICwAAAA==.',
Yu='Yukmouf:BAABNQAECn8ZAAIOAAkK4BrGQgDJAgAOAAkK4BrGQgDJAgAAAA==.Yukshadow:BAAANQAECgQIBAAAAA==.Yuriika:BAAANQADCgYIBwAAAA==.Yuukmouf:BAAANQAECgYICgABNQAECgkJGQAOAOAaAA==.',
Za='Zakaris:BAABNQAECn8aAAIBAAYKWBDjVQBOAQABAAYKWBDjVQBOAQAAAA==.Zaladin:BAAANQADCgUIBQAAAA==.Zarrove:BAABNQAECn8kAAINAAkKJh1bEQDTAgANAAkKJh1bEQDTAgAAAA==.Zawl:BAAANQAECgMIBQAAAA==.',
Ze='Zea:BAAANQADCgMIAwAAAA==.Zedael:BAAANQAECgYIDAAAAA==.Zellgadis:BAAANQADCgMIAgAAAA==.Zeltri:BAABNQAECn81AAIeAAgKtQjsNQBwAQAeAAgKtQjsNQBwAQAAAA==.Zerg:BAAANQAECgUIEgAAAA==.',
Zh='Zhatva:BAACNQAFFH8JAAIEAAQKnhV5EABOAQAEAAQKnhV5EABOAQA1AAQKfy4AAwQACQqfIcUeABsDAAQACQqfIcUeABsDAB0AAwosEp5bALMAAAAA.Zhöe:BAAANQAECgYICgAAAA==.',
Zi='Zimzhealz:BAAANQADCgcIDQAAAA==.Zimzorzz:BAAANQADCgUIBwABNQADCgcIDQADAAAAAA==.',
Zo='Zoelera:BAAANQAECgQIBgAAAA==.Zoldor:BAABNQAECn8YAAMPAAcKcg/nlgCoAQAPAAcKcg/nlgCoAQAUAAEK8whYewAxAAAAAA==.Zoleia:BAAANQADCgMIAwAAAA==.Zorellion:BAABNQAECn8aAAIPAAcKDwV9wwA/AQAPAAcKDwV9wwA/AQAAAA==.',
Zu='Zuay:BAAANQADCgIIAgABNQAECgkJNAARAI4hAA==.Zulianguy:BAACNQAFFH8GAAIOAAIKpw9rJQCKAAAOAAIKpw9rJQCKAAA1AAQKfyUAAyMACQq8InIWAEcCACMABgq3InIWAEcCAA4ABAriIwjQAHUBAAAA.',
Zy='Zycorr:BAAANQAECgIIBAAAAA==.Zytrex:BAAANQAECgUICAAAAA==.',
['Zá']='Zátsu:BAAANQABCgEIAQAAAA==.',
['Äm']='Ämaterasu:BAAANQAECgQIBgABNQAECggIIwAeACUkAA==.',
['Ñÿ']='Ñÿx:BAAANQAECgYIEQAAAA==.',
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
