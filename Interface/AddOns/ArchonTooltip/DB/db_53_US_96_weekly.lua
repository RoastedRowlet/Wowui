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

local lookup = {'Mage-Frost','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Evoker-Preservation','Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Rogue-Assassination','Paladin-Protection','Warlock-Destruction','Priest-Shadow','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Guardian','Druid-Feral','Priest-Holy','Hunter-Survival','Druid-Balance','Monk-Brewmaster','Warrior-Arms','DeathKnight-Blood','Warrior-Protection','Priest-Discipline','DemonHunter-Havoc','Monk-Windwalker','Mage-Fire','Warlock-Affliction','DemonHunter-Devourer','Evoker-Devastation','Shaman-Enhancement','Monk-Mistweaver','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acanthiex:BAAANQAECgQIBQAAAA==.Ackbar:BAAANQAECgMJAwAAAA==.',
Ad='Adondias:BAABNQAECn8sAAIBAAgKcSQZAgBUAwABAAgKcSQZAgBUAwAAAA==.Adorias:BAAANQADCgYIBgAAAA==.',
Ae='Aelana:BAABNQAECn8hAAIBAAgKThQ4CgAjAgABAAgKThQ4CgAjAgAAAA==.',
Ag='Agrevail:BAAANQAECgYIDgAAAA==.',
Ak='Akryllic:BAABNQAECn8nAAICAAgKciI0CwATAwACAAgKciI0CwATAwAAAA==.',
Al='Alamora:BAABNQAECn8WAAMDAAgKWxqsdAAkAgADAAcK8hysdAAkAgAEAAgKGwwhNQChAQAAAA==.Aldari:BAACNQAFFH8PAAMFAAYK6BkmDgABAgAFAAYK6BkmDgABAgABAAEK+Bi4EQBLAAA1AAQKfyAAAgUACQqfI34qADsDAAUACQqfI34qADsDAAAA.Allydk:BAABNQAECn8rAAMGAAkKgCV9CgBnAwAGAAkKgCV9CgBnAwAHAAEKOwopqwAyAAAAAA==.Almorn:BAAANQAECgQIDgAAAA==.Alondrius:BAAANQADCgIIAgAAAA==.Altrag:BAABNQAECn85AAIDAAkKghkAPwCrAgADAAkKghkAPwCrAgAAAA==.Aluc:BAABNQAECn8eAAIIAAgKKAatKQBgAQAIAAgKKAatKQBgAQAAAA==.Alystae:BAAANQABCgUIBQAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECgcIEgAJAAAAAA==.Animaldude:BAAANQAECgcIEgAAAA==.Anslayer:BAAANQADCggIEQAAAA==.',
Ar='Archön:BAABNQAECn8iAAIKAAkKQBLASABBAgAKAAkKQBLASABBAgAAAA==.Arctodus:BAAANQADCggICAAAAA==.Arks:BAAANQAECgYIEAAAAA==.Arthùr:BAAANQADCgcIBwAAAA==.',
As='Asperges:BAABNQAECn8iAAMLAAgKVBqzcQDHAQALAAcKIRizcQDHAQAMAAcKmg9ggwB+AQAAAA==.Astrellia:BAAANQADCgUIEAABNQADCggICAAJAAAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECggIQQANAHEbAA==.Avralynia:BAAANQAECgYIEQAAAA==.Avrella:BAAANQADCgYICwABNQAECgYIEQAJAAAAAA==.',
['Aé']='Aéo:BAAANQABCgIIAgAAAA==.',
['Aü']='Aürther:BAAANQAECgEIAQAAAA==.',
Ba='Babydaddyx:BAACNQAFFH8UAAIDAAUKpSCrBQD0AQADAAUKpSCrBQD0AQA1AAQKfykAAgMACQppJrYFALMDAAMACQppJrYFALMDAAE1AAQKCAguAA4AqCQA.Baconn:BAACNQAFFH8JAAIPAAQKYxkLDwBUAQAPAAQKYxkLDwBUAQA1AAQKfx0AAg8ACQqbIwgdAE0DAA8ACQqbIwgdAE0DAAAA.Balun:BAAANQAECgcIEQAAAA==.Basalt:BAAANQAECggIBgAAAA==.',
Be='Beefdido:BAABNQAECn8eAAIQAAgKEA08PQDVAQAQAAgKEA08PQDVAQAAAA==.Beefstew:BAABNQAECn8fAAIDAAgKoh/DPACyAgADAAgKoh/DPACyAgAAAA==.Belithe:BAABNQAECn8ZAAIRAAYKRgbiQwDfAAARAAYKRgbiQwDfAAAAAA==.Belletrixya:BAABNQAECn8eAAIDAAcKiBGckQDiAQADAAcKiBGckQDiAQAAAA==.Belrandir:BAAANQADCgYICgAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bij:BAABNQAECn8fAAMSAAgK/Qx7LgAQAQANAAgKhgzHiQDJAQASAAUK+wx7LgAQAQAAAA==.Bingsoo:BAABNQAECn8rAAIFAAkKPxaAgAB9AgAFAAkKPxaAgAB9AgAAAA==.Birdlaw:BAAANQADCgYICQAAAA==.',
Bj='Bjarki:BAAANQADCgYIBgAAAA==.Bjorney:BAABNQAECn8lAAITAAgKqx9vEwDKAgATAAgKqx9vEwDKAgAAAA==.',
Bl='Blankspace:BAABNQAECn8XAAMUAAcKyBQ3HADvAQAUAAcKyBQ3HADvAQAQAAEK5Aw8oAA0AAAAAA==.Blasphemar:BAAANQADCggIHgAAAA==.Blindvngence:BAABNQAECn8cAAIVAAgKlRhhCgAyAgAVAAgKlRhhCgAyAgAAAA==.Bloodrayne:BAAANQAECgEJAgAAAA==.Bluedruid:BAABNQAECn8pAAMWAAkKTSTRAQC8AwAWAAkKTSTRAQC8AwAXAAEKAACQOQBOAAAAAA==.Blusloane:BAAANQAECgEIAQAAAA==.',
Bo='Bonkdeath:BAAANQADCgYJCgABNQAECgkJKQAWAE0kAA==.Booms:BAAANQADCgYICwAAAA==.Bowaz:BAAANQADCgIIAgABNQAECggIIgAPAMoeAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brewkake:BAAANQAECgYICwAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECggIJAAKAA4NAA==.Brobafett:BAABNQAECn8lAAMYAAYKxiRMOwB5AgAYAAYKxiRMOwB5AgATAAYKBRoNJwDwAQAAAA==.Brøx:BAABNQAECn8mAAIGAAgKRyCBKACVAgAGAAgKRyCBKACVAgAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bumfightbob:BAABNQAECn8ZAAIZAAcKEB58BACbAgAZAAcKEB58BACbAgAAAA==.Bunnyboy:BAAANQAECgEIAgAAAA==.Burlen:BAABNQAECn8uAAIFAAkKryRIDQCfAwAFAAkKryRIDQCfAwAAAA==.',
['Bê']='Bênitora:BAABNQAECn8sAAIaAAkKrRbSJwCTAgAaAAkKrRbSJwCTAgAAAA==.',
['Bî']='Bîrth:BAABNQAECn8rAAMBAAkKByOiAgA3AwABAAkKByOiAgA3AwAFAAgKrxlFmABPAgAAAA==.',
Ca='Calic:BAABNQAECn9BAAMNAAgKcRuAfgDlAQANAAYKJxuAfgDlAQASAAIKBRwFSQCjAAAAAA==.Calryuu:BAABNQAECn8cAAIbAAgKbRLhEQDFAQAbAAgKbRLhEQDFAQAAAA==.Caltrask:BAAANQAECgIIAgAAAA==.Cambiön:BAABNQAECn88AAIBAAkKlSA7AgBNAwABAAkKlSA7AgBNAwAAAA==.Capslock:BAAANQAECgQICQABNQAECgYIDwAJAAAAAA==.Catharsis:BAAANQAECggIBwAAAA==.',
Ce='Cenno:BAABNQAECn8gAAIGAAgK9hBqUADPAQAGAAgK9hBqUADPAQAAAA==.Cern:BAAANQAECgMIBAAAAA==.',
Ch='Chadaclysm:BAAANQADCggJEgAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chantyu:BAAANQADCggIHQABNQAECggIJAAKAA4NAA==.Chickenman:BAABNQAECn80AAIcAAgKRSGmQwC8AgAcAAgKRSGmQwC8AgAAAA==.Chinpokomon:BAAANQAECggILQAAAQ==.Choncc:BAAANQAECgYICQAAAA==.Chonkykong:BAABNQAECn8nAAIdAAgKJhErUQCtAQAdAAgKJhErUQCtAQAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECggIJAAKAA4NAA==.Chuppy:BAAANQADCgcIDAABNQAECggIJgAcAG0bAA==.',
Ci='Cinnapaw:BAAANQAECgEIAQAAAA==.',
Co='Codytwo:BAAANQAECgQIDAAAAA==.Coldstrype:BAABNQAECn9CAAIFAAkKmhRagQB7AgAFAAkKmhRagQB7AgABNQAECgcIEgAJAAAAAA==.Cole:BAABNQAECn8nAAMcAAgKaRozbwBCAgAcAAgKEhgzbwBCAgAeAAUKERmLHABwAQAAAA==.Collonel:BAAANQAECgQIDgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCggIDwABNQAECgIIAgAJAAAAAA==.Couchlocked:BAAANQAECgEIAQAAAA==.',
Cp='Cpt:BAAANQADCgQJBQAAAA==.Cptpeals:BAAANQADCggJDQAAAA==.Cptsneck:BAAANQADCgMJAwAAAA==.Cpttan:BAAANQAECgYICgAAAA==.',
Cr='Criticalmiss:BAAANQADCgMIAwABNQAFFAUIEQAGAFQaAA==.Critykity:BAABNQAECn8bAAQXAAkKrBgaCQC3AgAXAAkKrBgaCQC3AgAWAAIKQgv1UwBOAAAaAAEKSQ/urwAzAAAAAA==.Critymage:BAAANQADCgEJAQAAAA==.Critypally:BAAANQAECgYIDAAAAA==.Crunkpickles:BAAANQAECgUIBgAAAA==.',
Cv='Cvrcvss:BAAANQAECgcIDQAAAA==.',
Da='Dabadjuju:BAAANQADCgYIDAABNQAECgQIDAAJAAAAAA==.Daerik:BAABNQAECn8gAAIDAAkKbB/kNADKAgADAAkKbB/kNADKAgAAAA==.Dagoonfather:BAABNQAECn8sAAIQAAcKlRSDPwDKAQAQAAcKlRSDPwDKAQAAAA==.Damarkus:BAAANQAECgEIAQAAAA==.Dandochi:BAAANQAECgUICAABNQAFFAMICAAKAI8jAA==.Dandorllan:BAACNQAFFH8IAAMKAAMKjyMgGQDUAAAKAAIK5iQgGQDUAAAPAAEKAABIOgAzAAA1AAQKfzEAAwoACQo0JaQDALcDAAoACQo0JaQDALcDAA8ABQpEIfLPAHUBAAAA.Dandowaz:BAAANQAECgcIEgABNQAFFAMICAAKAI8jAA==.Dandyrandy:BAABNQAECn8rAAMKAAkKDRcWNACRAgAKAAkKDRcWNACRAgAPAAEKWAQUtQEqAAAAAA==.Dani:BAAANQAECgEIAgAAAA==.Dayday:BAAANQAECggICAAAAA==.Dazzazn:BAAANQAECgYIEQAAAA==.Dazzeus:BAAANQAECgUIBQAAAA==.',
De='Deadstal:BAAANQAFFAIIAwAAAA==.Deathmaw:BAAANQABCgUIBQAAAA==.Decious:BAAANQAECggIEAAAAA==.Dedoinmyass:BAAANQADCgQIBAAAAA==.Deeboh:BAAANQAECgYIBgAAAA==.Deepfist:BAABNQAECn8wAAIbAAgKPyVZAwBdAwAbAAgKPyVZAwBdAwAAAA==.Defjam:BAABNQAECn8qAAMFAAgKJBgQ3gDJAQAFAAYKeBkQ3gDJAQABAAIKfBVtLgCHAAAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQAECgIIAgAAAA==.Delicia:BAABNQAECn8aAAMfAAgKCQnaEAAZAQAfAAYKRwvaEAAZAQAYAAcKoQJhqwAOAQAAAA==.Dellbelphine:BAABNQAECn8tAAMPAAkKOBpyUQCdAgAPAAkKOBpyUQCdAgAKAAQKYAqs2QDGAAAAAA==.Demonskii:BAABNQAECn8lAAIgAAkKHhqiHACxAgAgAAkKHhqiHACxAgABNQAFFAIIBgADAB8YAA==.Demton:BAAANQAECgYIDgAAAA==.Deusdux:BAAANQADCgMIAwAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAABNQAECn8hAAIhAAkK/h5+CgAoAwAhAAkK/h5+CgAoAwAAAA==.Direkau:BAABNQAECn8rAAIeAAkKaCV3AQC5AwAeAAkKaCV3AQC5AwAAAA==.Discman:BAAANQADCgQIBAAAAA==.',
Do='Docroegames:BAAANQABCgcJDAAAAA==.Dojaz:BAABNQAECn8nAAIgAAkK5xBZMgATAgAgAAkK5xBZMgATAgAAAA==.Domerockk:BAAANQADCgQIBAABNQAECgkJLAAPAGAjAA==.Dontouch:BAAANQAECgIIAgAAAA==.Doomadin:BAAANQAECgEIAQAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgIIBAAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgUIEwAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Drakewarden:BAAANQADCgUIBQABNQAECgkJHAAYAIkiAA==.Draktha:BAAANQAECgUICQAAAA==.Dreddful:BAABNQAECn8pAAIiAAkKYxiMAQCaAgAiAAkKYxiMAQCaAgAAAA==.Drer:BAAANQADCgMIAwAAAA==.Drkelso:BAABNQAECn8fAAIBAAgKxwh2EgB9AQABAAgKxwh2EgB9AQAAAA==.',
Du='Duchalu:BAABNQAECn8oAAMcAAgKpg5umwDTAQAcAAgKpg5umwDTAQAOAAEKAAAwNAAxAAAAAA==.Durtbag:BAAANQABCgMIAwAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQAECgUICAAAAA==.',
Ei='Eione:BAABNQAECn8uAAIaAAgKORJKPgADAgAaAAgKORJKPgADAgAAAA==.',
El='Elend:BAAANQAECgYIDAAAAA==.Elinez:BAAANQAECgUIBgAAAA==.Ellcrys:BAAANQAECgQICgAAAA==.Elvinshiznic:BAAANQAECgcIEwAAAA==.',
Em='Emagine:BAABNQAECn8uAAIMAAkKWyLKDABYAwAMAAkKWyLKDABYAwAAAA==.Embra:BAAANQADCgcIDAAAAA==.Emeraldbeast:BAACNQAFFH8HAAICAAMKihCRDADjAAACAAMKihCRDADjAAA1AAQKfyEAAgIACQoqGCgZAG8CAAIACQoqGCgZAG8CAAAA.',
En='Endela:BAAANQADCggIBwABNQADCggICAAJAAAAAA==.Endelan:BAAANQADCgMIAwABNQADCggICAAJAAAAAA==.Endelen:BAAANQAECgEIAQAAAA==.',
Er='Erissra:BAAANQADCgMIAwAAAA==.Eroeda:BAABNQAECn8cAAIgAAgKYQZmTwBXAQAgAAgKYQZmTwBXAQAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECggINAAcAEUhAA==.',
Ev='Evilmustdie:BAAANQADCgMIAwAAAA==.',
Ex='Exo:BAABNQAECn8rAAICAAkKFSWVAgCjAwACAAkKFSWVAgCjAwAAAA==.Exylan:BAABNQAECn8oAAIPAAkKgBm5UgCaAgAPAAkKgBm5UgCaAgAAAA==.',
Ez='Ezsmash:BAAANQAECggIEQAAAA==.',
Fa='Fatgrlfriend:BAABNQAECn81AAIPAAkKKSXTCAC0AwAPAAkKKSXTCAC0AwABNQAECggILgAOAKgkAA==.',
Fe='Ferachio:BAAANQAECgIIAgAAAA==.',
Ff='Ffreshmage:BAAANQAECgQIBQABNQAFFAYIEQAjABYjAA==.',
Fh='Fhud:BAAANQADCgIIAwAAAA==.',
Fi='Fierysquish:BAAANQADCggIDAAAAA==.Filmnoir:BAABNQAECn8lAAIkAAgKtBWSIgAzAgAkAAgKtBWSIgAzAgAAAA==.Fistferge:BAAANQADCgEIAQABNQAECgkJJAARAH8iAA==.',
Fl='Flinah:BAAANQABCgIJAgAAAA==.',
Fo='Follia:BAAANQADCgYIBgAAAA==.Foosaa:BAAANQAECgMJAwAAAA==.Forbearance:BAABNQAECn8rAAIRAAkKACLTBgA4AwARAAkKACLTBgA4AwAAAA==.Forgotss:BAABNQAECn8YAAMNAAgK8gfAogCKAQANAAgKfAfAogCKAQASAAMKLAP8YABiAAAAAA==.',
Fr='Franco:BAABNQAECn8mAAIDAAkKXg4GeAAcAgADAAkKXg4GeAAcAgAAAA==.Freshfresh:BAAANQADCggICAABNQAFFAYIEQAjABYjAA==.Freshlock:BAACNQAFFH8RAAQjAAYKFiOgAQArAQAjAAMKNCGgAQArAQASAAIK+CTPAwDaAAANAAEKAABJOABxAAA1AAQKfyEABA0ACQq2I/xPAGECAA0ABwp7IPxPAGECABIABAq5IhUiAF8BACMAAgrSH+4ZALQAAAAA.Fright:BAAANQAECgYICAAAAA==.Friska:BAAANQAECgUIEwAAAA==.Frostyp:BAACNQAFFH8YAAITAAYKchPBBQDPAQATAAYKchPBBQDPAQA1AAQKfywAAxMACQprHVQXAJsCABMACQprHVQXAJsCABgAAQrCAS0FASIAAAAA.',
Fu='Fulldk:BAAANQADCggIEAAAAA==.Funken:BAAANQADCggIGgAAAA==.Funnel:BAAANQAECgMIAgAAAA==.',
Fy='Fyre:BAAANQADCgUIBgABNQAFFAQIBgAlAOoGAA==.Fyrebird:BAACNQAFFH8GAAMlAAQK6gaOCgCsAAAlAAMK6gaOCgCsAAAIAAEKsgFFGgA0AAA1AAQKfyQAAyUACQoCFjcNAIwCACUACQoCFjcNAIwCAAgABAqcCO89AKkAAAAA.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAABNQAECn8wAAICAAgKdiDSDQDwAgACAAgKdiDSDQDwAgAAAA==.Galadima:BAABNQAECn8rAAIKAAgKGSF3HgD2AgAKAAgKGSF3HgD2AgAAAA==.Ganador:BAABNQAECn8rAAMNAAkKhR9aKgDZAgANAAgKlB9aKgDZAgASAAIKMxwdTgCUAAAAAA==.Garglon:BAAANQADCggICgAAAA==.Gatorrc:BAAANQADCgMJAwAAAA==.Gazzerfroz:BAAANQADCgYIBgABNQAECgcIEQAJAAAAAA==.',
Gh='Ghostingyou:BAAANQAECgYICwABNQAECgkJKQAWAE0kAA==.',
Gi='Gilburt:BAACNQAFFH8dAAINAAcK8RtaAQCgAgANAAcK8RtaAQCgAgA1AAQKfxwAAg0ACAqPIF46AKICAA0ACAqPIF46AKICAAAA.Gileon:BAAANQAECgcIEAAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgYICwAAAA==.',
Go='Gomgar:BAAANQADCggIFgAAAA==.Gorg:BAABNQAECn8WAAMMAAkKSRxaPABrAgAMAAkKSRxaPABrAgALAAEKJApNLQE3AAAAAA==.',
Gr='Grashoppa:BAAANQADCgcIEQAAAA==.Greentide:BAABNQAECn8qAAIMAAkKWxfkSgA0AgAMAAkKWxfkSgA0AgAAAA==.Grimmothy:BAAANQADCggIFgAAAA==.Grimore:BAAANQAECgUICQAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAABNQAECn8eAAImAAgK2AxiFwDtAQAmAAgK2AxiFwDtAQAAAA==.',
Gw='Gwynastrasza:BAACNQAFFH8cAAIIAAgKMhUgAgCXAgAIAAgKMhUgAgCXAgA1AAQKfx0AAggACQrGHAcOAMYCAAgACQrGHAcOAMYCAAAA.Gwynneth:BAAANQAECgMJAwABNQAFFAgIHAAIADIVAA==.',
['Gü']='Güy:BAAANQAECgcIEQAAAA==.',
Ha='Haleluya:BAAANQADCgYIDgABNQAECgUIBwAJAAAAAA==.Halepurr:BAAANQAECgUIBwAAAA==.Halogenrofl:BAABNQAECn8rAAIkAAkKQR+DCQA+AwAkAAkKQR+DCQA+AwAAAA==.Hammerferge:BAABNQAECn8kAAIRAAkKfyJYCQAGAwARAAkKfyJYCQAGAwAAAA==.Hangezoë:BAAANQAECggIDgABNQAFFAcIHQANAPEbAQ==.Happa:BAABNQAECn8pAAIbAAkKfB3TBgDXAgAbAAkKfB3TBgDXAgAAAA==.Harbngerkhan:BAABNQAECn8cAAMGAAYKqhLzaABqAQAGAAYKqhLzaABqAQAdAAUKvAURlAC1AAAAAA==.Hardok:BAAANQADCgEIAQAAAA==.Hashishi:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQAECgEIAQAAAA==.Heidt:BAAANQAECgYIDgAAAA==.Hellica:BAAANQADCgcIDgAAAA==.',
Ho='Holibeef:BAABNQAECn8kAAMKAAgKDg2UcwC5AQAKAAgKDg2UcwC5AQAPAAEK2AFEzAEdAAAAAA==.Holysquish:BAACNQAFFH8QAAIPAAUKpRuhCgCaAQAPAAUKpRuhCgCaAQA1AAQKfy0AAg8ACQrSIRI0APoCAA8ACQrSIRI0APoCAAAA.Homoglobin:BAAANQAECgYICgAAAA==.Honeydemon:BAABNQAECn8rAAIgAAkKTBghKABaAgAgAAkKTBghKABaAgAAAA==.Honeydue:BAAANQADCgEJAwABNQAFFAQIBgAlAOoGAA==.Hongis:BAABNQAECn8jAAMFAAcKghqrvAAJAgAFAAcKghqrvAAJAgABAAEKTQWUUgAeAAAAAA==.Horsefuneral:BAAANQADCgQIBAABNQAECgUIBgAJAAAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECgcIDgAAAA==.Humi:BAAANQAECgUICgAAAA==.Huntskii:BAACNQAFFH8GAAIDAAIKHxhZIwCjAAADAAIKHxhZIwCjAAA1AAQKfyoAAgMACQqUIhcMAHwDAAMACQqUIhcMAHwDAAAA.',
Hw='Hwaryeong:BAAANQAECgQIDQAAAA==.',
Ia='Iamluck:BAACNQAFFH8FAAIkAAMKGxMaDQDYAAAkAAMKGxMaDQDYAAA1AAQKfyYAAiQACQqJHukSANECACQACQqJHukSANECAAAA.Iamluçk:BAACNQAFFH8KAAIFAAUKGw67HgCIAQAFAAUKGw67HgCIAQA1AAQKfx8AAgUACQphG3JVANUCAAUACQphG3JVANUCAAAA.',
Ic='Iceleaf:BAAANQAECgcIEQAAAA==.',
Ig='Igopew:BAAANQAECgQIBAAAAA==.',
Il='Ileinaa:BAABNQAECn9BAAIYAAkKXRauOACDAgAYAAkKXRauOACDAgAAAA==.Iliketrains:BAABNQAECn8iAAMLAAgKzxLSWwALAgALAAgKzxLSWwALAgAMAAUK0wL/0wC6AAAAAA==.Ilovegrizzly:BAAANQAECgYIBwABNQAECggIGAAPADslAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Introvert:BAAANQABCgMIAwAAAA==.Invvictis:BAABNQAECn8WAAIdAAgKUwgNbgA5AQAdAAgKUwgNbgA5AQAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggICAAJAAAAAA==.',
Ja='Jammyslammin:BAAANQABCgcIBwABNQAECggIKgAFACQYAA==.Jaymazing:BAAANQAECgMIBAABNQAECgkJIwAcADYZAA==.Jaysaurus:BAABNQAECn8jAAIcAAkKNhmWSgCmAgAcAAkKNhmWSgCmAgAAAA==.Jazzey:BAABNQAECn8dAAIGAAkKhRrWNQBOAgAGAAkKhRrWNQBOAgAAAA==.',
Jc='Jckie:BAAANQAECgQICAAAAA==.',
Je='Jestyrddk:BAAANQAECgUICgABNQAECggIFwAVAPQiAA==.',
Jo='Jodox:BAAANQADCgMIAQAAAA==.Joehendry:BAAANQADCgcIEAAAAA==.Johnathonn:BAAANQAECgMIBAAAAA==.Joj:BAABNQAECn8gAAMYAAgK9hxTPwBqAgAYAAgK9hxTPwBqAgAfAAIKHBvxGQCZAAAAAA==.Jojman:BAAANQAECgcIBwAAAA==.Jonthecron:BAAANQAECgUIEQAAAA==.Jormot:BAAANQADCgYJBwABNQAFFAQIBgAlAOoGAA==.Jowl:BAAANQADCgMIAwAAAA==.',
Ju='Juck:BAAANQAECggIDwAAAA==.Junkyo:BAAANQAECgUIDgAAAA==.Justamage:BAABNQAECn8oAAIFAAgKRhdimABPAgAFAAgKRhdimABPAgAAAA==.Juw:BAAANQAECgEIAQAAAA==.',
Ka='Kalundia:BAABNQAECn8dAAIaAAkKvBhNJwCXAgAaAAkKvBhNJwCXAgAAAA==.Karkshammy:BAACNQAFFH8HAAILAAQKogjeEwAwAQALAAQKogjeEwAwAQA1AAQKfx4AAgsACQr/HM8zAKYCAAsACQr/HM8zAKYCAAAA.Karlia:BAAANQADCgYICQAAAA==.',
Ke='Keane:BAABNQAECn8uAAIcAAkKIw+EhQAKAgAcAAkKIw+EhQAKAgAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.Kelpie:BAAANQAECgEIAwAAAA==.Kelwind:BAAANQAECgIIAgAAAA==.',
Kh='Khanquest:BAAANQAECgUIBwAAAA==.',
Ki='Killkillkill:BAAANQAECgIIAgAAAA==.Kindassuddy:BAABNQAECn8lAAIFAAkKKxc9hQBzAgAFAAkKKxc9hQBzAgAAAA==.Kindled:BAAANQAECgcIDgAAAA==.Kinvardar:BAAANQAECgYICQAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAFFAcIFAAKABsbAA==.Kirbislav:BAAANQAECggICwABNQAFFAcIFAAKABsbAA==.Kirbslav:BAACNQAFFH8UAAIKAAcKGxvAAgB3AgAKAAcKGxvAAgB3AgA1AAQKfywAAgoACQoVJDMGAJkDAAoACQoVJDMGAJkDAAAA.Kirklandbeef:BAAANQAECgIIAgAAAA==.Kittykillerr:BAAANQADCgcJBwABNQAECggILgAOAKgkAA==.',
Kn='Knata:BAAANQAECgMIAwAAAA==.Kniavez:BAABNQAECn8mAAIcAAgK2A5LlQDjAQAcAAgK2A5LlQDjAQAAAA==.',
Kr='Krack:BAABNQAECn8aAAILAAgKjxAbZQDuAQALAAgKjxAbZQDuAQAAAA==.Krak:BAAANQAECgEIAwABNQAECggIGgALAI8QAA==.Kruugh:BAAANQAECgcIEAAAAA==.',
Ku='Kuler:BAAANQAECgYIEwAAAA==.Kungfustuff:BAAANQADCgUIBQABNQAECgYIDQAJAAAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.Kurome:BAAANQAECgcICAAAAA==.',
['Kè']='Kèèn:BAABNQAECn8XAAIPAAcKGiHtiAAQAgAPAAcKGiHtiAAQAgAAAA==.',
['Kì']='Kìt:BAAANQAECgEIAgAAAA==.',
['Kí']='Kítkat:BAAANQADCgIIAgABNQAECgEIAgAJAAAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
La='Lavage:BAAANQAECgQIBwAAAA==.',
Le='Lectra:BAAANQABCgcICAAAAA==.Lengthypally:BAAANQAECgUIBgAAAA==.',
Li='Liakä:BAAANQAECgcIEAABNQAECgkJHgADAHATAA==.Lilbeaner:BAAANQAECggIBAAAAA==.Liratha:BAAANQAECgYIEQAAAA==.Lisá:BAAANQAECgIIAgAAAA==.',
Lo='Locholiday:BAAANQAECgQIBAABNQAECgcIHQAhAPQaAA==.Lodoss:BAACNQAFFH8FAAIMAAIKRxRQHwCRAAAMAAIKRxRQHwCRAAA1AAQKfxsAAgwACQqUF6dAAFsCAAwACQqUF6dAAFsCAAAA.Lokhidmartin:BAAANQAECgcIDQAAAA==.Lorienb:BAABNQAECn8oAAMTAAkKwA4sIwAWAgATAAkKwA4sIwAWAgAfAAUKIgXLFQDMAAAAAA==.Lorstin:BAAANQADCgEIAQAAAA==.',
Lu='Luckehlock:BAACNQAFFH8cAAMjAAcKGiYHAAAIAwAjAAcKGiYHAAAIAwASAAEKSBHoHABNAAA1AAQKfy4AAiMACQr2JgsAAAYEACMACQr2JgsAAAYEAAAA.Lunaea:BAABNQAECn8gAAMQAAgKoB06VQBfAQAQAAQKXRw6VQBfAQAUAAQK4x4rLABcAQAAAA==.Luxcn:BAAANQADCgUJBwAAAA==.',
['Lú']='Lúffy:BAAANQAECgcICwABNQAECggIEwAJAAAAAA==.',
Ma='Macdorn:BAAANQAECgYIBgAAAA==.Macgibbins:BAAANQAECgQIBAAAAA==.Macgillivray:BAABNQAECn8XAAMPAAgKrxskgwAdAgAPAAgKrxskgwAdAgARAAgKtweRNQA2AQAAAA==.Magewindu:BAABNQAECn8bAAIFAAkKTg5juAARAgAFAAkKTg5juAARAgAAAA==.Magus:BAAANQAECgQICwABNQAFFAMIBQAaAEAjAA==.Malakar:BAAANQAECgEIAQAAAA==.Mardin:BAAANQADCgEJAQAAAA==.Marhuon:BAAANQADCgEIAQAAAA==.Mats:BAAANQAECgEIAQAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQAECgIIAgAAAA==.',
Mi='Midgardsomr:BAAANQAECgYICgAAAA==.Mightbane:BAAANQAFFAEIAgAAAA==.Mikebroowwnn:BAAANQADCgIIAgAAAA==.Milkmytotems:BAABNQAECn8aAAMMAAkKjR4LFgAeAwAMAAkKjR4LFgAeAwALAAIKxAlGFwFZAAABNQAECggILgAOAKgkAA==.Minagozap:BAABNQAECn8YAAILAAcKbxFAdQC9AQALAAcKbxFAdQC9AQAAAA==.Mininine:BAAANQAECgQIBAAAAA==.Minityr:BAABNQAECn8nAAQKAAgK1Bw9NgCJAgAKAAgK1Bw9NgCJAgARAAgKwBJrJQCxAQAPAAQKLwXjRQGpAAAAAA==.Minoritee:BAAANQAFFAEIAQAAAA==.Minotron:BAAANQADCgUICgABNQAFFAYIDgAEACUYAA==.Mizukï:BAABNQAECn8kAAIYAAgKmx/pIQDkAgAYAAgKmx/pIQDkAgAAAA==.',
Mo='Molyver:BAABNQAECn8nAAMhAAkKvB21EQDPAgAhAAkKvB21EQDPAgAnAAEKBAOlUQAkAAAAAA==.Momak:BAAANQADCgUICAABNQAECggIKAALALwZAA==.Mommey:BAACNQAFFH8OAAIYAAUKQxfSDAC5AQAYAAUKQxfSDAC5AQA1AAQKfycABB8ACQrWH94DAJ4CAB8ACAomHt4DAJ4CABgABgrCHPNdAAQCABMABwozHIgnAOsBAAAA.Moonmellow:BAAANQAECgQIDQAAAA==.Moosin:BAAANQADCgYIBgAAAA==.Morel:BAAANQADCgYIBgAAAA==.Mositas:BAAANQABCgIIAgAAAA==.',
Mp='Mpatt:BAAANQADCgUIBgAAAA==.',
Mu='Munder:BAAANQAECgQIDwAAAA==.Murlockscry:BAAANQAECgIIAgAAAA==.Musculate:BAABNQAECn8rAAIEAAkKpSQ+BACSAwAEAAkKpSQ+BACSAwAAAA==.',
Mv='Mvdi:BAABNQAECn8ZAAIKAAcKyxxDPQBtAgAKAAcKyxxDPQBtAgAAAA==.',
My='Myranda:BAAANQADCgYIBgAAAA==.',
['Mï']='Mïssionary:BAAANQAECgIIAgAAAA==.',
Na='Nartou:BAAANQAECgcIEQAAAA==.',
Ne='Necrofearlia:BAAANQAECgYIEQAAAA==.Nekoashley:BAAANQAECgQIDQAAAA==.',
Ni='Nick:BAACNQAFFH8FAAIaAAMKQCOVFQAKAQAaAAMKQCOVFQAKAQA1AAQKfyAAAhoACQrMJrEDAMIDABoACQrMJrEDAMIDAAAA.Nightangelxx:BAAANQADCgYJEAAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAACNQAFFH8RAAMGAAUKVBr1CwBLAQAGAAQKVBr1CwBLAQAdAAEKAAAjOgAdAAA1AAQKfy4AAgYACQrvIsIXAP4CAAYACQrvIsIXAP4CAAAA.Nosferatu:BAAANQAECgIJAgAAAA==.Notrico:BAAANQADCgQIBAAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQAECggIJgALAJ8kAA==.Nurfshock:BAABNQAECn8mAAILAAgKnyTfEwBQAwALAAgKnyTfEwBQAwAAAA==.',
Nz='Nzo:BAAANQADCgYIBgAAAA==.',
Oa='Oasis:BAAANQADCgYICAAAAA==.',
Ok='Okaybutwhy:BAAANQADCgYIBgABNQAECgkJKwAPAKYlAA==.Okiedk:BAAANQAECgUIEwAAAA==.',
On='Onefelswoop:BAAANQAECgYIDgAAAA==.',
Or='Ortuk:BAAANQADCgMIAwAAAA==.',
Ox='Oxen:BAABNQAECn8fAAMdAAgKZyBrJwCBAgAdAAcKZyBrJwCBAgAGAAUK9AwfjADwAAAAAA==.',
Pe='Pegab:BAAANQAFFAIIAgAAAA==.Penniee:BAAANQADCggIDQAAAA==.Penniwing:BAABNQAECn8gAAQoAAgKgRfYBgBJAgAoAAgKgRfYBgBJAgAIAAYKCRFtLABAAQAlAAIKYQ7SNABjAAAAAA==.Percival:BAECNQAFFH8fAAMEAAcK/yS0AQCwAgAEAAcK/yS0AQCwAgAZAAEKAADbAgBEAAA1AAQKfywAAwQACQopJgsHAF4DAAQACQopJgsHAF4DAAMAAQoID+pUATkAAAAA.',
Ph='Phaedra:BAAANQAECggILQAAAQ==.Phaidra:BAAANQAECgQICAABNQAECggILQAJAAAAAQ==.Phealdh:BAABNQAECn8mAAMgAAgK1xuqJgBkAgAgAAgK1xuqJgBkAgAkAAYKawZwRwASAQAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.Pixr:BAAANQAECggICAAAAA==.',
Pl='Plague:BAABNQAECn8hAAIGAAkKzhz8NQBNAgAGAAkKzhz8NQBNAgAAAA==.',
Po='Police:BAAANQAECggICAAAAA==.',
Pu='Pudpull:BAAANQAECgEIAQAAAA==.Pullbarg:BAAANQAECgUICAAAAA==.',
Py='Pyru:BAAANQAECgQICgAAAA==.',
['Pï']='Pïng:BAABNQAECn8eAAIDAAkKcBN0UgB2AgADAAkKcBN0UgB2AgAAAA==.',
Qu='Quest:BAABNQAECn8cAAInAAkKhRjxDgCOAgAnAAkKhRjxDgCOAgAAAA==.Quickwinnter:BAABNQAECn8YAAMPAAgKOyVPJAAyAwAPAAgKOyVPJAAyAwAKAAEK2hRCFwE+AAAAAA==.Quickwinterg:BAABNQAECn8WAAMGAAgKyRedPAArAgAGAAgKyRedPAArAgAHAAgKxQRQgQCeAAABNQAECggIGAAPADslAA==.Quickwinterm:BAAANQAECggIDwABNQAECggIGAAPADslAA==.',
Ra='Raandok:BAAANQADCggIGAABNQAECgYIDwAJAAAAAA==.Raantok:BAAANQADCgYIBgABNQAECgYIDwAJAAAAAA==.Raantokdh:BAAANQADCgUICQABNQAECgYIDwAJAAAAAA==.Raantoks:BAAANQAECgYIDwAAAA==.Raantokx:BAAANQADCggICAABNQAECgYIDwAJAAAAAA==.Rachet:BAAANQAECgUIEgAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgQIBQAAAA==.Rakkdos:BAAANQAECgQIBAAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAABNQAECn8rAAMKAAkK1RK+SQA+AgAKAAkK1RK+SQA+AgAPAAEKFgVFtAErAAAAAA==.Rayadobane:BAAANQAECgQIBAAAAA==.Rayadosun:BAAANQADCgIIAgAAAA==.',
Re='Rebalanced:BAAANQAECgIJAgAAAA==.Rebelscum:BAAANQADCgUIBQAAAA==.Redbudz:BAAANQADCgYIBgAAAA==.Reggienoble:BAACNQAFFH8IAAIZAAQKVhzVAABwAQAZAAQKVhzVAABwAQA1AAQKfy4AAhkACQowJHsAAMADABkACQowJHsAAMADAAAA.Rekerî:BAAANQADCgEIAQABNQAFFAcIGAAEAAYeAA==.Resoran:BAAANQADCggJBgAAAA==.',
Ri='Rijit:BAAANQADCgYIDAAAAA==.Rineda:BAAANQADCgYICgAAAA==.Rinzee:BAAANQAECgEIAQAAAA==.Rinzlrr:BAABNQAECn8jAAImAAkKhR12CADvAgAmAAkKhR12CADvAgAAAA==.Rippinzynz:BAAANQADCgIIAgAAAA==.',
Ro='Rockyshocky:BAAANQABCgQIBAABNQAECgYICwAJAAAAAA==.Rohrn:BAABNQAECn8kAAIPAAgKlBcmeQA1AgAPAAgKlBcmeQA1AgAAAA==.Rol:BAAANQAECgQIBwAAAA==.Rosahugs:BAABNQAECn8XAAIYAAgKsSG1GQAMAwAYAAgKsSG1GQAMAwAAAA==.',
Ru='Ruggishbone:BAAANQAECgUIEgAAAA==.Ruinedmyth:BAABNQAECn8ZAAMcAAkK8AkCsgCbAQAcAAkKjAkCsgCbAQAeAAUKigy+KADxAAAAAA==.',
Sa='Saintsnetie:BAAANQAECgUIBwAAAA==.',
Sc='Scottyknows:BAABNQAECn8hAAMKAAgKphs8NgCJAgAKAAgKphs8NgCJAgAPAAYK6hCDygCAAQAAAA==.Scredwin:BAABNQAECn8tAAMSAAgKAxlfCAB3AgASAAgKAxlfCAB3AgANAAIKDAcdKwFfAAAAAA==.Scrubadub:BAABNQAECn8kAAMDAAgK0Rn7VwBpAgADAAgK0Rn7VwBpAgAEAAEKxweniwAyAAAAAA==.Scüffed:BAAANQADCgQICAAAAA==.',
Se='Sean:BAAANQADCgMIAwABNQAECgkJHAAnAIUYAA==.Seeks:BAAANQADCgQIBAAAAA==.Semizas:BAAANQADCgYIBgAAAA==.Senorbobo:BAABNQAECn8xAAMOAAkKeCBmAgBVAwAOAAkKeCBmAgBVAwAcAAgKUBifhgAHAgAAAA==.Senorxx:BAAANQAECgQIBgABNQAECgkJMQAOAHggAA==.Sern:BAAANQAECgQIBgAAAA==.Serni:BAAANQAECgMICAAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadora:BAAANQADCgYIBgAAAA==.Shadowslite:BAABNQAECn8YAAMQAAgKCg1qUwBoAQAQAAYKVA5qUwBoAQAUAAUKsQUtNwD6AAAAAA==.Shadowwolf:BAAANQADCgYIBgAAAA==.Sham:BAABNQAECn8zAAMNAAkKWCBoGwAWAwANAAkK1h9oGwAWAwASAAUKBxiKIABrAQAAAA==.Shamancheese:BAAANQADCgYICAABNQAECgIIAgAJAAAAAA==.Shammpaignn:BAAANQAFFAEIAQAAAA==.Shampayn:BAAANQAECgEIAQAAAA==.Shanksinatrá:BAACNQAFFH8bAAMQAAcKryEgBQDeAQAQAAUKsSAgBQDeAQAUAAQKAhNVCABtAQA1AAQKfy0ABBQACQoLJosOAI4CABQABgpbJosOAI4CABAABgpHIQUyABECACkAAgpwF8kXAGUAAAAA.Shatt:BAABNQAECn8eAAIFAAkKOBgiWwDJAgAFAAkKOBgiWwDJAgAAAA==.Shedari:BAABNQAECn8rAAMPAAkKhxUznwDeAQAPAAgKkRMznwDeAQARAAQK+xkcPgABAQAAAA==.Shiftyjd:BAAANQADCgQIBAABNQAECgQIBQAJAAAAAA==.Sholyver:BAAANQAECgUICQAAAA==.Shourix:BAABNQAECn8uAAIOAAgKqCRuAgBUAwAOAAgKqCRuAgBUAwAAAA==.',
Si='Sifushocks:BAABNQAECn8VAAILAAgKahajWgAPAgALAAgKahajWgAPAgAAAA==.Sihnn:BAABNQAECn8gAAIYAAkKNxxrHwDwAgAYAAkKNxxrHwDwAgAAAA==.Simzerker:BAACNQAFFH8LAAIcAAQKBRm8GQBDAQAcAAQKBRm8GQBDAQA1AAQKfyUAAxwACQojJOUcAEMDABwACQojJOUcAEMDAA4AAgoVAgAoAGkAAAAA.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQAECgUICwAAAA==.',
Sl='Slamina:BAABNQAECn8eAAIcAAkKph7WHABDAwAcAAkKph7WHABDAwAAAA==.Slowly:BAAANQAFFAIJAgAAAA==.',
Sm='Smarts:BAABNQAECn8iAAIFAAgKzw4S1QDaAQAFAAgKzw4S1QDaAQAAAA==.',
Sn='Sniiffle:BAABNQAECn8oAAICAAgKkhhKHABPAgACAAgKkhhKHABPAgAAAA==.Snowba:BAAANQADCgcICAAAAA==.',
Sp='Sparrowheart:BAAANQADCgYICAAAAA==.Spellcrackle:BAAANQADCggIDgABNQAECggIJAAKAA4NAA==.Sprucejenner:BAABNQAECn8vAAMaAAgKdxZxMQBTAgAaAAgKIRRxMQBTAgAWAAYKfxMAJgBgAQAAAA==.',
Sq='Squivify:BAABNQAFFH8GAAInAAUKlhYEBAChAQAnAAUKlhYEBAChAQAAAA==.',
Ss='Ssudds:BAAANQAECggIEwABNQAECgkJJQAFACsXAA==.Ssuddy:BAAANQADCgYIBgABNQAECgkJJQAFACsXAA==.',
St='Stankbeef:BAAANQADCgQIBAABNQAECggIJAADANEZAA==.Starkisses:BAABNQAECn8qAAIDAAkKuyOVEQBaAwADAAkKuyOVEQBaAwAAAA==.Storebrandps:BAAANQADCgEIAQABNQAECgIIAgAJAAAAAA==.Stormßella:BAAANQADCgYIBgAAAA==.Styrthe:BAACNQAFFH8XAAInAAYKIhgGAwDXAQAnAAYKIhgGAwDXAQA1AAQKfywAAycACQqXGdUPAH4CACcACQqXGdUPAH4CABsAAwo5Eb8kAKcAAAAA.',
Su='Surventval:BAAANQAECgUIDAABNQAECgkJIwAmAIUdAA==.',
Sw='Sweetpickles:BAAANQADCgYIFwABNQAECgUIBQAJAAAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECgkJIQAhAP4eAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAFFAUICQAKAEkHAA==.',
Ta='Taeka:BAAANQAECgQIDgAAAA==.Taeshira:BAACNQAFFH8FAAITAAIK9goVEwCTAAATAAIK9goVEwCTAAA1AAQKfyQAAhMACQouF0IVALQCABMACQouF0IVALQCAAAA.Talkimas:BAABNQAECn8wAAMDAAgKixoiVwBrAgADAAgKyRkiVwBrAgAEAAUKdQ1gSQAPAQAAAA==.Talvisota:BAABNQAECn8mAAIGAAgKqSJ8HgDSAgAGAAgKqSJ8HgDSAgAAAA==.Tarirn:BAABNQAECn8nAAMHAAgK5yWKBwBqAwAHAAgKByWKBwBqAwAGAAgKciQXFQAPAwAAAA==.Taunkaa:BAAANQAECgYIEQAAAA==.',
Te='Tekoslul:BAACNQAFFH8RAAIgAAYKIR3fBAAQAgAgAAYKIR3fBAAQAgA1AAQKfyAAAiAACQpaJGIKAFsDACAACQpaJGIKAFsDAAAA.Tekosmage:BAAANQABCgYICQAAAA==.Tekosxd:BAAANQAECgMIAwABNQAFFAYIEQAgACEdAA==.Tekosxo:BAAANQAECgQIBQABNQAFFAYIEQAgACEdAA==.Teldragoose:BAABNQAECn8oAAMCAAkKBRWUHABMAgACAAkKBRWUHABMAgAaAAIKage0oABXAAAAAA==.Tendeda:BAACNQAFFH8QAAMFAAYKcRoMDgACAgAFAAYKcRoMDgACAgABAAEKmgGaFgAyAAA1AAQKfyEAAwUACQrSH/9yAJcCAAUACAqXH/9yAJcCAAEAAgq/FUExAHMAAAAA.',
Th='Thalunar:BAABNQAECn8dAAIDAAgKqRakbQA0AgADAAgKqRakbQA0AgAAAA==.Thatonedruid:BAAANQADCgYIBgABNQAECgkJMQAOAHggAA==.Thelegendone:BAACNQAFFH8PAAIKAAQKwRroDwBfAQAKAAQKwRroDwBfAQA1AAQKfy0AAgoACQrdIUUPAE8DAAoACQrdIUUPAE8DAAAA.Thepenisadin:BAABNQAECn8iAAIPAAgKsRKcmADtAQAPAAgKsRKcmADtAQAAAA==.Thorck:BAABNQAECn8cAAIcAAgKNwrmrgCiAQAcAAgKNwrmrgCiAQAAAA==.Thrallzballz:BAAANQADCgYIBgAAAA==.Thugnakmunga:BAAANQAECgUIBQAAAA==.',
Ti='Tidens:BAAANQAECgEIAQAAAA==.Tinklewinkle:BAABNQAECn8rAAIFAAkKRhrATQDmAgAFAAkKRhrATQDmAgAAAA==.Tinygiant:BAAANQAECgUIBAAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAABNQAECn8iAAILAAgKISRGFQBHAwALAAgKISRGFQBHAwAAAA==.Topshelfelf:BAABNQAECn8eAAMYAAcK1B87PAB2AgAYAAcK1B87PAB2AgAfAAMK3wsbGgCXAAAAAA==.Totemferge:BAAANQAECgQIBAABNQAECgkJJAARAH8iAA==.',
Tr='Tresdin:BAABNQAECn8sAAIPAAkKBCJYFgBqAwAPAAkKBCJYFgBqAwAAAA==.Tresemme:BAABNQAECn8hAAIYAAkK5xkKJADZAgAYAAkK5xkKJADZAgAAAA==.',
Ts='Tsohg:BAAANQAECgUICAABNQAECgUICwAJAAAAAA==.',
Tu='Tul:BAABNQAECn8XAAMMAAkKmxWVQQBXAgAMAAkKmxWVQQBXAgALAAUKRB1JeQCyAQAAAA==.Tumlock:BAABNQAECn8gAAMSAAgKTQ9MEgDhAQASAAgKMA9MEgDhAQANAAEKjQT9QwEvAAAAAA==.Turrok:BAABNQAECn8sAAIUAAkKvR5cBwAFAwAUAAkKvR5cBwAFAwAAAA==.Turtletaunt:BAAANQADCgUICAAAAA==.',
['Tï']='Tïgra:BAABNQAECn8wAAIkAAgKWhr4GgB9AgAkAAgKWhr4GgB9AgAAAA==.',
Ua='Uandikillhim:BAACNQAFFH8HAAIYAAUKxw8EGQAiAQAYAAUKxw8EGQAiAQA1AAQKfywAAx8ACQrpHrEBACcDAB8ACQquHbEBACcDABgACAphE0lYABUCAAAA.',
Um='Umbrä:BAAANQABCgIIAgAAAA==.',
Un='Undeadbones:BAAANQAECgIIAgAAAA==.Unfading:BAABNQAECn8vAAIPAAgKuRk0XQB9AgAPAAgKuRk0XQB9AgAAAA==.Unholyknight:BAABNQAECn8oAAMGAAgKpg+ZWQCmAQAGAAgKpg+ZWQCmAQAdAAYKmgJFkADAAAAAAA==.',
Ur='Urban:BAACNQAFFH8JAAMBAAQKWQ0bCQCJAAAFAAMK1gz3OADcAAABAAIKWQ0bCQCJAAA1AAQKfyAAAgUACQoCJDs8AA4DAAUACQoCJDs8AA4DAAAA.Urtark:BAABNQAECn8rAAIOAAkKHR4/BAD5AgAOAAkKHR4/BAD5AgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQAECgQIEQAAAA==.Vail:BAAANQADCgEIAQABNQAECgkJKAAPAIAZAA==.Varalic:BAABNQAECn8bAAIQAAgKAx9uFwC9AgAQAAgKAx9uFwC9AgABNQAFFAYIEwAgAAobAA==.Varandra:BAAANQAECgYIDQABNQAECgkJKAAPAIAZAA==.Varidas:BAABNQAECn8bAAIBAAkKwQPvGgAXAQABAAkKwQPvGgAXAQAAAA==.Vasage:BAAANQADCgUIBQAAAA==.Vashet:BAAANQADCgcIBwAAAA==.',
Ve='Veleno:BAAANQABCgIIAgAAAA==.Ventrois:BAABNQAECn8WAAIhAAkK6RkoGwBgAgAhAAkK6RkoGwBgAgABNQAECgkJIwAmAIUdAA==.Vespera:BAAANQABCgQIAgAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vi='Vilienar:BAAANQAECgMIBAABNQAECgkJKAAPAIAZAA==.',
Vo='Voidalic:BAACNQAFFH8TAAIgAAYKChtABQACAgAgAAYKChtABQACAgA1AAQKfyQAAyQACQpcHjgeAFwCACQACQr7GTgeAFwCACAAAwpDIBJbABIBAAAA.Voidrend:BAACNQAFFH8fAAMkAAcKzxn0AQBkAgAkAAcKAxn0AQBkAgAgAAMKpQ6HEQDWAAA1AAQKfzAABCQACQrvIKkQAOkCACQACQqoIKkQAOkCACAABQpDFxVQAFMBABUAAQoAAOUxADIAAAAA.',
Vu='Vuldon:BAAANQADCgYIBgAAAA==.Vuloolu:BAAANQAECgYIDgAAAA==.',
Vy='Vynese:BAAANQADCgUIBwAAAA==.',
['Vø']='Vøgue:BAABNQAECn8qAAIQAAkKfQ3XMQASAgAQAAkKfQ3XMQASAgAAAA==.',
Wa='Warbidet:BAABNQAECn8iAAIPAAgKyh6uTwCiAgAPAAgKyh6uTwCiAgAAAA==.Warmason:BAABNQAECn8gAAIcAAYKQQbx6AAMAQAcAAYKQQbx6AAMAQAAAA==.Washed:BAABNQAECn8lAAQNAAgKTxYlpACHAQANAAYKRRYlpACHAQASAAMKrQ9URwCpAAAjAAIKLBFgHwB5AAAAAA==.',
We='Wealthy:BAABNQAECn8wAAIYAAgKlR0MMQChAgAYAAgKlR0MMQChAgAAAA==.',
Wh='Whispere:BAABNQAECn8YAAIFAAkKwRf4jwBfAgAFAAkKwRf4jwBfAgAAAA==.',
Wi='Wiiska:BAAANQADCgQIBAAAAA==.',
Wo='Word:BAAANQAECgQIDQAAAA==.',
Wr='Wrred:BAAANQAECgQIDgAAAA==.',
Xp='Xpredator:BAAANQADCgIIAgAAAA==.',
Ye='Yetifunk:BAAANQAECgQICwAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAABNQAECn8tAAIPAAgKAiBzOgDlAgAPAAgKAiBzOgDlAgAAAA==.',
Ze='Zemi:BAABNQAECn8qAAImAAkKHA+JEwAtAgAmAAkKHA+JEwAtAgAAAA==.Zenethrius:BAAANQABCgUJBAAAAA==.Zenlol:BAAANQAECgQIBAABNQAECgkJKwAkAEEfAA==.Zephang:BAABNQAECn8WAAIhAAgKew2rMACNAQAhAAgKew2rMACNAQABNQAFFAIIAwAJAAAAAA==.Zephiyre:BAAANQAECgIIAgABNQAFFAIIAwAJAAAAAA==.Zephyubi:BAAANQAFFAIIAwAAAA==.Zeros:BAAANQAECgQIBwAAAA==.Zevalia:BAABNQAECn8ZAAIbAAcKLBiXDQAeAgAbAAcKLBiXDQAeAgAAAA==.',
Zo='Zophia:BAAANQADCgUICQAAAA==.',
Zu='Zugrotic:BAABNQAECn8oAAILAAgKvBkrPACCAgALAAgKvBkrPACCAgAAAA==.Zumy:BAABNQAECn8cAAILAAgK7iOkJgDmAgALAAgK7iOkJgDmAgAAAA==.Zuzzy:BAAANQAECgEIAwAAAA==.',
['ße']='ßelle:BAAANQAECgcICwAAAA==.',
['ßi']='ßirth:BAAANQAECgcIBwABNQAECgkJKwABAAcjAA==.',
['ßl']='ßlade:BAAANQAECgUICAAAAA==.',
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
