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

local lookup = {'Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Holy','Druid-Guardian','Druid-Restoration','Druid-Feral','Monk-Mistweaver','Druid-Balance','Mage-Frost','Mage-Arcane','Warrior-Protection','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Fury','Evoker-Preservation','Hunter-BeastMastery','Hunter-Survival','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','DeathKnight-Blood','Warrior-Arms','DemonHunter-Devourer','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Holy','Priest-Discipline','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaragon:BAABNQAECn8WAAQBAAkKJxIcHQAXAQABAAkKJxIcHQAXAQACAAQK9A8iEgDnAAADAAEKhxHllgA8AAABNQAFFAoKLAAEAJ8jAA==.',
Ab='Abysmal:BAABNQAECn8dAAMFAAgKixG8kABeAQAFAAgKixG8kABeAQAGAAEKAAAYSAEqAAAAAA==.',
Ad='Adame:BAAANQAECgEIAQAAAA==.Adjudicator:BAAANQAECgQIBAABNQAECgQIBQAHAAAAAA==.',
Ae='Aeriona:BAABNQAECn84AAIIAAoKVh2mKABfAgAIAAoKVh2mKABfAgAAAA==.Aerobear:BAAANQAECgQIBAABNQAFFAUIBwAJAEUFAA==.Aerolock:BAAANQAECgUICwABNQAFFAUIBwAJAEUFAA==.Aerosong:BAACNQAFFH8HAAMJAAUKRQVcFACvAAAJAAQKRQVcFACvAAAKAAEKAABqBgAAAAA1AAQKfyMAAgkACgrrEhExACACAAkACgrrEhExACACAAAA.',
Af='Affalon:BAAANQAECgQICAAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Aine:BAABNQAECn8fAAILAAkKMxSvRgCWAQALAAkKMxSvRgCWAQAAAA==.Ainkor:BAAANQAECgYIDAABNQAFFAEIAQAHAAAAAA==.',
Ak='Akyospirit:BAABNQAECn8+AAIFAAoK0w1WQACWAQAFAAoK0w1WQACWAQAAAA==.',
Al='Alava:BAAANQAECgQIBAAAAA==.Alchemised:BAABNQAECn8YAAQMAAoKpQSmPQBoAAAMAAoKVgSmPQBoAAANAAMKDQOCaQBfAAAOAAUKZQTkPQBCAAABNQAECgoKHQAPAJscAA==.Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAABNQAECn8tAAIQAAcK2gpDOADoAAAQAAcK2gpDOADoAAAAAA==.Allumin:BAAANQADCggIFAAAAA==.Alpha:BAABNQAECn86AAMRAAoKvRiaCABVAgARAAgKQBiaCABVAgASAAoKBBgbMQAtAgAAAA==.',
Am='Amamonk:BAABNQAECn8gAAIEAAoKMBX6DwDoAQAEAAoKMBX6DwDoAQAAAA==.Amathore:BAAANQADCgcIBwAAAA==.Ammert:BAAANQAECgQIBAAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAgIGgATAOoXAA==.Angliko:BAAANQADCgMJAwABNQAECgoKLwAKAHYZAA==.Annei:BAABNQAECn8zAAMLAAoKMCN6EgA2AwALAAoKMCN6EgA2AwAUAAYKoBJyOwBOAQABNQAFFAIIBQAVANcNAA==.Anomandaris:BAABNQAECn8bAAMGAAgKkA0ujACGAQAGAAgKkA0ujACGAQAFAAQKTAjhoQB0AAAAAA==.Anquan:BAABNQAECn8WAAMWAAYKbxF6QwAJAQAWAAYKngt6QwAJAQAVAAQKgxO8jgDrAAAAAA==.Anya:BAABNQAECn8rAAIDAAoKYBOwJQD4AQADAAoKYBOwJQD4AQAAAA==.',
Ap='Apedemak:BAAANQAECgcICgAAAA==.Apothica:BAABNQAECn8tAAISAAoKsw0cSADaAQASAAoKsw0cSADaAQAAAA==.Apothicc:BAAANQAECgUICgABNQAECgoKLQASALMNAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUJDAAAAA==.',
Aq='Aquae:BAAANQAECgYICAABNQAECggIGQAXAIQaAA==.',
Ar='Arcohunt:BAAANQADCgcJBwABNQAECgUJDAAHAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argobow:BAAANQADCgQIBAAAAA==.Argodin:BAABNQAECn8bAAIIAAkKyxhlhgAaAgAIAAkKyxhlhgAaAgAAAA==.Argonaut:BAAANQADCggIEAAAAA==.Artarius:BAAANQABCgQIBQAAAA==.',
As='Asheritâ:BAAANQAECgUIDgAAAA==.Ashvalis:BAABNQAECn8fAAIYAAcKQCF3FgBPAgAYAAcKQCF3FgBPAgAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECggIDwAAAA==.Askr:BAABNQAECn8bAAIZAAcKngxoeABEAQAZAAcKngxoeABEAQAAAA==.Asphar:BAABNQAECn8fAAIZAAoK3SEPKAD4AgAZAAoK3SEPKAD4AgAAAA==.Astria:BAAANQADCgYICwAAAA==.Asynic:BAAANQADCgYIEAABNQAECgcIFgAaAGsYAA==.',
Au='Aung:BAACNQAFFH8GAAIJAAIKRx9vCgDAAAAJAAIKRx9vCgDAAAA1AAQKf0QAAgkACQqOJZEJAGYDAAkACQqOJZEJAGYDAAAA.Auri:BAAANQAECgIIAgAAAA==.',
Av='Avitarkorra:BAAANQAECgUICAAAAA==.',
Ax='Axex:BAABNQAECn8YAAIIAAgKAA3AxwCMAQAIAAgKAA3AxwCMAQAAAA==.',
Az='Azamii:BAABNQAECn8wAAMFAAoKNxw4JgAcAgAFAAkKERs4JgAcAgAGAAUKIh7DXgDxAAABNQAECgoKPwALAIUfAA==.Azarion:BAACNQAFFH8FAAMbAAMKrgmdKABHAAAbAAIKcwqdKABHAAAcAAEK6gjSDwBDAAA1AAQKfzUAAxsACgodFMA4AMYBABsACQovE8A4AMYBABwABQrmEtMmAEABAAAA.Azill:BAACNQAFFH8WAAIEAAYKqhGoAwAvAQAEAAYKqhGoAwAvAQA1AAQKfyYAAgQACgoAH0oRANYCAAQACgoAH0oRANYCAAAA.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAwAAAA==.Azurefury:BAABNQAECn8iAAIdAAcKBwjWHQCEAQAdAAcKBwjWHQCEAQAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.Azzrael:BAAANQAECgcIBwAAAA==.',
Ba='Bandi:BAABNQAECn8rAAIbAAoKDRSeOwC6AQAbAAoKDRSeOwC6AQAAAA==.Bartrak:BAAANQADCgIJAgABNQAECggICgAHAAAAAA==.Battôsai:BAAANQAECgQIEAAAAA==.',
Be='Bearfucius:BAABNQAECn8uAAMEAAkKERT7EgC2AQAEAAkKERT7EgC2AQAPAAgKuwz+MADiAAAAAA==.Bearrific:BAABNQAECn8jAAMDAAgKGRHUQgBUAQADAAgKGRHUQgBUAQABAAEKXwUDpwAuAAAAAA==.Beefypriest:BAAANQABCgEIAQAAAA==.Behomadra:BAAANQAECgYIBgAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAABNQAECn8kAAMeAAoKEiDfDwAuAwAeAAoKEiDfDwAuAwAVAAEKzgHc/QAaAAAAAA==.Beyond:BAAANQAECgUIBwAAAA==.',
Bi='Billthekid:BAAANQADCgcIBwAAAA==.Binksy:BAACNQAFFH8LAAIfAAMKsBENEwDLAAAfAAMKsBENEwDLAAA1AAQKfzcAAh8ACgrQHqo4AOICAB8ACgrQHqo4AOICAAAA.Biscuit:BAACNQAFFH8aAAMTAAgK6hdMAQDeAQATAAcKgxxMAQDeAQAfAAEK7gA1PABJAAA1AAQKf0AAAxMACgoFJhIBAMkDABMACgoFJhIBAMkDAB8ABQrFG7K6AIoBAAAA.',
Bl='Blaam:BAAANQAECgEIBAAAAA==.Blazin:BAACNQAFFH8VAAMSAAUK5xmBFAD4AAASAAUK5xmBFAD4AAARAAEKnBCOEwBHAAA1AAQKfy0AAxIACgqrIEtGAPYCABIACgo/IEtGAPYCABEABQpqG6wTAG4BAAAA.Blinkzy:BAAANQADCgUICQABNQAFFAMICwAfALARAA==.Blitzoria:BAAANQADCgYIBgABNQAECgYIEgAHAAAAAA==.Bloui:BAAANQADCgYIFwAAAA==.Blueknight:BAABNQAECn8jAAMeAAcKlQabcgArAQAeAAcKlQabcgArAQAVAAIKUAaJzQBSAAAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgYIDAAAAA==.Bonythumper:BAAANQADCgQIBAAAAA==.Borlok:BAAANQAECggIMAAAAQ==.',
Br='Brannigan:BAABNQAECn8+AAIfAAoKUCH+IQAwAwAfAAoKUCH+IQAwAwAAAA==.Brannigandh:BAABNQAECn8hAAQKAAgKoRgHCwAjAgAKAAgKfBgHCwAjAgAgAAYKvQ1+QABIAQAJAAEKAAAojgA/AAABNQAECgoKPgAfAFAhAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQAECgEIAQAAAA==.Briantu:BAAANQADCggJCAAAAA==.Brickfelt:BAAANQADCgQIBAAAAA==.Brickitphil:BAABNQAECn8kAAIWAAoK1h0HEgD9AgAWAAoK1h0HEgD9AgAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Bruaimiamh:BAAANQADCgMIAwABNQAECgIIAgAHAAAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIIAgAHAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAABNQAECn8ZAAMXAAgKhBqYCgAfAgAXAAcKxxuYCgAfAgAfAAMK4QuVJgGLAAAAAA==.Bulldan:BAAANQAECgQICwAAAA==.Bullvi:BAAANQAECgQIBgAAAA==.',
['Bä']='Bärkler:BAAANQAECgUJBgAAAA==.',
['Bé']='Béckléy:BAABNQAECn8XAAIOAAkKiCHJBAA7AwAOAAkKiCHJBAA7AwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cannïbal:BAAANQAECgYICQAAAA==.Caprichos:BAAANQADCgYIBgAAAA==.Cara:BAAANQADCgMIBAAAAA==.Carra:BAABNQAECn8vAAIZAAgKYBh8XABgAgAZAAgKYBh8XABgAgAAAA==.Cassiopeía:BAEANQAECggIDwAAAA==.Catriona:BAABNQAECn8kAAIZAAgK6QiCygBsAQAZAAgK6QiCygBsAQAAAA==.',
Ch='Charcuterie:BAACNQAFFH8YAAIhAAcKMQ+yAQD4AQAhAAcKMQ+yAQD4AQA1AAQKfyAAAiEACgpAH8YGANkCACEACgpAH8YGANkCAAAA.Chartou:BAAANQADCggICAAAAA==.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheeze:BAAANQABCgUIBQABNQAECgcIIQAZANcQAA==.Cheezeburg:BAABNQAECn8hAAMZAAcK1xAwdgBIAQAZAAcK1xAwdgBIAQAiAAYKpQlnRgAnAQAAAA==.Chicken:BAAANQAECgcICQABNQAFFAgIGgATAOoXAA==.Chikindalf:BAAANQADCgEJAQAAAA==.Chillainkor:BAAANQAECggIDQABNQAFFAEIAQAHAAAAAA==.Chillidán:BAABNQAECn8pAAIgAAkKNgQgQABLAQAgAAkKNgQgQABLAQAAAA==.Choggie:BAABNQAECn85AAMjAAoK8xx6CABBAwAjAAoK8xx6CABBAwAIAAYKawNQOAHGAAAAAA==.Chulainn:BAABNQAECn8cAAIQAAkKKA2sIgBvAQAQAAkKKA2sIgBvAQAAAA==.',
Co='Cons:BAABNQAECn8/AAMLAAoKUR4/FgAhAwALAAoKUR4/FgAhAwAkAAMKPhEGCwB8AAAAAA==.Corellon:BAABNQAECn80AAIZAAkK2RwVMADcAgAZAAkK2RwVMADcAgAAAA==.',
Cr='Cranee:BAABNQAECn9VAAMbAAoK4xbuKAAPAgAbAAoKYxbuKAAPAgAcAAMKTA2wEwB8AAAAAA==.Cranium:BAABNQAECn8gAAIWAAgK4yFhDACfAgAWAAgK4yFhDACfAgAAAA==.Crazytasty:BAABNQAECn86AAIZAAoKLCFwHQAiAwAZAAoKLCFwHQAiAwAAAA==.',
Cy='Cyndel:BAAANQABCgIIAgAAAA==.',
Da='Dabora:BAABNQAECn9IAAMBAAoK0yK5AQAmAwABAAoK0yK5AQAmAwACAAIKEg4yGABhAAAAAA==.Damassan:BAAANQABCgYIBgAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECggIKQAZANMIAA==.Darige:BAABNQAECn8YAAIRAAgKnw+PFQBUAQARAAgKnw+PFQBUAQAAAA==.Darim:BAABNQAECn88AAIIAAoKYyScCQCwAwAIAAoKYyScCQCwAwABNQADCgYIBgAHAAAAAA==.Darthshob:BAAANQAECgcIBwAAAA==.Darthspawn:BAABNQAECn8kAAIWAAcK4QenTgDbAAAWAAcK4QenTgDbAAAAAA==.Daryn:BAAANQAECgEIAQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIIAgAHAAAAAA==.',
De='Deadchops:BAAANQAECgQIBQABNQAECgYICgAHAAAAAA==.Deadlock:BAAANQABCgIIAgAAAA==.Demonainkor:BAAANQAFFAEIAQAAAA==.Demonicfury:BAAANQAECgIIAgAAAA==.Dencity:BAABNQAECn9CAAMLAAoKhhztKADFAgALAAoKhhztKADFAgAkAAEK3wOLMAAjAAAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQAECgMIAwABNQAECggIGwAfABcbAA==.Devitodevour:BAABNQAECn86AAMbAAoKjh07OADIAQAbAAgKPRw7OADIAQAcAAIKgiHHDwCfAAAAAA==.Devwarr:BAABNQAECn8bAAIfAAgKFxuMjQD6AQAfAAgKFxuMjQD6AQAAAA==.Dezard:BAAANQABCgIIAgAAAA==.',
Dh='Dhbert:BAAANQAECgIIAgAAAA==.Dhomeli:BAAANQAECgIIAwAAAA==.Dhometri:BAAANQADCgIIAgAAAA==.',
Di='Dicbswellin:BAAANQAECgIIAQAAAA==.Dirtchez:BAAANQAECgUIBgAAAA==.Disastrophy:BAAANQAECgYICgAAAA==.Disturbed:BAABNQAECn88AAQbAAoKLRkISQB4AgAbAAkKCxgISQB4AgAcAAMKIxYpOQDcAAAlAAEKkwScNAAoAAAAAA==.',
Dk='Dkson:BAACNQAFFH8NAAIeAAUK/xpRCwCgAQAeAAUK/xpRCwCgAQA1AAQKfzsAAx4ACgq3IR0IAHsDAB4ACgq3IR0IAHsDABUAAQrUGmhfAE0AAAAA.',
Do='Docen:BAAANQAECgUIDAAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.Download:BAAANQADCggICAABNQAECggICAAHAAAAAA==.',
Dr='Dragonfist:BAABNQAECn8WAAMEAAkKGhO6EwCsAQAEAAkKGhO6EwCsAQAPAAEKrwU5UQAnAAAAAA==.Dragthyr:BAAANQADCgYIEgAAAA==.Druiaier:BAAANQAECgUIBwAAAA==.Druknatsu:BAAANQAECgUIDgAAAA==.',
Du='Dustyknight:BAABNQAECn8YAAIeAAgKTgoAPwDlAAAeAAgKTgoAPwDlAAAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgcIEAAAAA==.',
Ec='Ecthan:BAAANQADCgQIBAAAAA==.',
Ed='Edge:BAABNQAECn8jAAIFAAgK2x1UPABuAgAFAAgK2x1UPABuAgAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elicio:BAAANQADCgQIBQAAAA==.Elidoria:BAEBNQAECn9FAAISAAoKTR5sFQC2AgASAAoKTR5sFQC2AgAAAA==.Elphinia:BAAANQADCgYJBgABNQAECgoKOwAGAMIbAA==.',
En='Enoki:BAABNQAECn8aAAMGAAoKoB1IIwD6AgAGAAoKoB1IIwD6AgAFAAIKhwt9+gB2AAABNQAFFAgIGAAjAPESAA==.',
Ep='Ephodess:BAAANQAECggIEAAAAA==.',
Er='Eraduckated:BAABNQAECn8aAAMBAAgKRx94IQB4AgABAAcKRx94IQB4AgACAAUKNhFQEAAbAQAAAA==.Erde:BAAANQAECgIIAwAAAA==.',
Es='Esco:BAAANQAECgQIBwAAAA==.Esile:BAABNQAECn8sAAImAAgKTQqJDAAVAQAmAAgKTQqJDAAVAQAAAA==.Esoryn:BAABNQAECn82AAIIAAoKvyICEAD3AgAIAAoKvyICEAD3AgAAAA==.',
Ev='Everlife:BAAANQAECgEIBQAAAA==.Evilainkor:BAABNQAECn8cAAIeAAoKbhiLJgCJAgAeAAoKbhiLJgCJAgABNQAFFAEIAQAHAAAAAA==.',
Ex='Exia:BAACNQAFFH8XAAIfAAYK+RL2DADjAQAfAAYK+RL2DADjAQA1AAQKfx0AAh8ACgooFPR4ACwCAB8ACgooFPR4ACwCAAAA.',
Fa='Fallnphoenix:BAAANQAECgIIAgAAAA==.Fauzzie:BAAANQAECgUIDgAAAA==.Fayrel:BAABNQAECn8gAAIGAAcKfwo/lgBtAQAGAAcKfwo/lgBtAQAAAA==.',
Fe='Fedders:BAABNQAECn81AAIIAAoKQyaVBADVAwAIAAoKQyaVBADVAwAAAA==.Felaids:BAABNQAECn8sAAQbAAgKIx/NWABMAgAbAAcKeh/NWABMAgAcAAIKTRhvTwCRAAAlAAIKWhDQIgBmAAAAAA==.Felnyx:BAAANQADCgYJCgAAAA==.Feor:BAABNQAECn8cAAINAAoKRBaPCgCUAgANAAoKRBaPCgCUAgAAAA==.Feralyn:BAAANQAECgIIAQAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAACNQAFFH8NAAIIAAQKhyCVDwBTAQAIAAQKhyCVDwBTAQA1AAQKfyMAAggACQriIRk4AO8CAAgACQriIRk4AO8CAAAA.Fionas:BAAANQAECgUIDQAAAA==.Firexcracker:BAAANQAECgEIAQAAAA==.Fishfood:BAABNQAECn86AAIVAAoKgBmyDgAxAgAVAAoKgBmyDgAxAgAAAA==.Fixer:BAAANQAECgEIAQAAAA==.',
Fl='Flappysnail:BAAANQADCgYICwAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fo='Foondin:BAAANQAECgQICAAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frazzle:BAAANQADCgMIAwABNQAECgQIDAAHAAAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAABNQAECn8sAAISAAoKvBMUjABnAgASAAoKvBMUjABnAgAAAA==.',
Fu='Fujitora:BAAANQAECgQIEAAAAA==.Funbunz:BAAANQAECgEIAQAAAA==.',
['Fø']='Førd:BAACNQAFFH8LAAImAAMKTBrTAQDpAAAmAAMKTBrTAQDpAAA1AAQKfzMABCYACgrsG/ELAKcCACYACQoOGvELAKcCACcACQoUF4kIAAkCABgABQoqBc86AMIAAAAA.',
Ga='Gahv:BAAANQAECgUICAAAAA==.Gahza:BAAANQAECgIIAgAAAA==.Galyte:BAAANQADCgQIBwAAAA==.Gangrene:BAABNQAECn81AAIVAAoKlxJqEwDxAQAVAAoKlxJqEwDxAQAAAA==.Gaspasser:BAAANQAECgcIDgAAAA==.Gaviin:BAABNQAECn8wAAIBAAoKUh92AwC7AgABAAoKUh92AwC7AgAAAA==.Gazamiseh:BAAANQABCgIIAgAAAA==.',
Ge='Gearador:BAAANQADCgMIBAAAAA==.Genovia:BAAANQADCgQIBAABNQAECggIBAAHAAAAAA==.Gerhart:BAABNQAECn88AAMJAAoKVhyyEwABAwAJAAkKRR6yEwABAwAKAAkK4hj+CQA+AgAAAA==.',
Gi='Gigarius:BAABNQAECn8vAAMoAAgKFRvfFwA6AgAoAAgKFRvfFwA6AgAIAAUK7A46SQExAAAAAA==.Gizelia:BAAANQADCgMIBAAAAA==.',
Gl='Gleya:BAAANQADCgYIBwAAAA==.Gloomy:BAAANQADCgYIBgAAAA==.',
Gn='Gnomestomper:BAAANQABCgIIAQAAAA==.',
Go='Goblinsrhot:BAAANQADCggIIQAAAA==.Goncor:BAABNQAFFH8FAAIVAAIK1w1RCACYAAAVAAIK1w1RCACYAAAAAA==.Gorrelord:BAAANQADCgIIAgABNQAFFAUIFQASAOcZAA==.',
Gr='Gracze:BAAANQAECgYIBwAAAA==.Gramadingg:BAAANQADCgEIAQAAAA==.Granolah:BAAANQAECgQIDwABNQAECgoKSAABANMiAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgcIDAAAAA==.Greyback:BAAANQADCgMIAwAAAA==.Griffmonk:BAABNQAECn8zAAIPAAoKex85BgCiAgAPAAoKex85BgCiAgAAAA==.Grimoire:BAAANQAECgQIBAABNQAECgYICgAHAAAAAA==.Grimstep:BAAANQADCgEIAQAAAA==.Grumpymage:BAABNQAECn8pAAIRAAgK9SBfBADoAgARAAgK9SBfBADoAgAAAA==.',
Gu='Gunjamomma:BAAANQAECgMIAwAAAA==.',
Ha='Hafsac:BAABNQAECn8bAAIJAAoKRRMIOgDkAQAJAAoKRRMIOgDkAQAAAA==.Hamasakura:BAAANQADCggIDwAAAA==.Hardord:BAABNQAECn8bAAIDAAYKfhO+IwCrAQADAAYKfhO+IwCrAQAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAABNQAECn81AAITAAoKLBmYBgAMAgATAAoKLBmYBgAMAgAAAA==.',
He='Healchucky:BAAANQAECgIIAgAAAA==.Healzjoogewd:BAAANQAECgQIDAAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.Hexflex:BAAANQAECgEIAQAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAABNQAECn8vAAILAAoKUBWrKAApAgALAAoKUBWrKAApAgAAAA==.Holikow:BAABNQAECn8bAAIIAAgKeg9wjQA2AQAIAAgKeg9wjQA2AQAAAA==.Holyherpies:BAAANQAECgIIAgAAAA==.Holyness:BAABNQAECn8fAAIoAAcK/ByiEACWAQAoAAcK/ByiEACWAQAAAA==.Honeybunz:BAAANQADCgMIBAAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAABNQAECn8aAAMoAAgK4xInJwClAQAoAAgKoBInJwClAQAIAAcKQAyY6gBHAQABNQAFFAUIEAAYAKgcAA==.',
Hu='Hurano:BAABNQAECn8bAAIjAAoKBSJvEgC3AgAjAAoKBSJvEgC3AgAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Ic='Icekel:BAAANQADCgUIBQAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
Ih='Ihsan:BAABNQAECn8XAAIIAAoKGwxQZQCNAQAIAAoKGwxQZQCNAQAAAA==.',
Il='Ilharess:BAAANQADCggICAAAAA==.Illusiõn:BAAANQAECgQIBAAAAA==.',
In='Inducktive:BAAANQAECgYICwABNQAECggIGgABAEcfAA==.Inkdot:BAABNQAECn8+AAMjAAoKRCK9AgDGAwAjAAoKRCK9AgDGAwAIAAgKVxUboQDfAQAAAA==.Inkshield:BAAANQADCgYICAABNQAECgoKHQAPAJscAA==.Inkwell:BAAANQAECgIIAgABNQAECgoKPgAjAEQiAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Io='Io:BAAANQAECgUIBQABNQAECgoKJQAeACQkAA==.Iomedáe:BAAANQADCgMIAwAAAA==.',
Ir='Irishnight:BAAANQADCgQICgABNQAECgoKMgAMAKYQAA==.Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQAECgEIAQAAAA==.',
Ja='Jakobo:BAABNQAECn8WAAMIAAoKmyDyzQB/AQAIAAUKDSDyzQB/AQAjAAYKwA4KowA+AQAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarkus:BAAANQADCgYIBwAAAA==.Jarthas:BAAANQADCgYIDQAAAA==.Jazlynel:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAACNQAFFH8YAAIjAAgK8RJdBABAAgAjAAgK8RJdBABAAgA1AAQKfyoAAyMACgokIIQOAFYDACMACgokIIQOAFYDAAgAAwrMGmoxAdAAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.Jenni:BAAANQADCgcIBwAAAA==.',
Ji='Jimbostein:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyblaze:BAAANQADCgIIAgAAAA==.Jozalin:BAAANQADCgQIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgMICQAAAA==.Junknthtrunk:BAAANQAECgMIBgAAAA==.',
Ka='Kaelana:BAAANQABCgQIBQAAAA==.Kamahl:BAABNQAECn8mAAIfAAkKdRUJYQBgAQAfAAkKdRUJYQBgAQAAAA==.',
Ke='Keanew:BAABNQAECn8wAAMJAAoK1RLzGQDQAQAJAAoK1RLzGQDQAQAKAAEKAAC6MwAtAAAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIIgAAAA==.Keonna:BAAANQADCgYIEwAAAA==.Keppra:BAAANQAECgQIBwAAAA==.Kerlin:BAABNQAECn8wAAINAAoKbBxtDABsAgANAAoKbBxtDABsAgAAAA==.',
Kh='Kheilah:BAAANQADCgEIAQAAAA==.Khurst:BAAANQAECgQIBAAAAA==.',
Ki='Kialis:BAEANQAECgMIAwABNQAECgkJGAAWAFUXAA==.Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgMIBAAAAA==.Kinoxo:BAACNQAFFH8XAAIfAAcKSxx5BACPAgAfAAcKSxx5BACPAgA1AAQKf0AAAx8ACgouJZoHADIDAB8ACgouJZoHADIDABcAAQpIIWgrAFgAAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kitina:BAAANQABCgIIAQAAAA==.Kitsunë:BAAANQADCgYIBgAAAA==.Kittyclysm:BAAANQAECgIIAgAAAA==.',
Ko='Kossuth:BAAANQABCgEIAQAAAA==.Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQAECgUIBAAAAA==.Krampusnacht:BAAANQADCgYIBgAAAA==.Krissycat:BAABNQAECn8VAAIQAAkKegOdPADUAAAQAAkKegOdPADUAAAAAA==.',
La='Ladeydeb:BAAANQADCgcIBAABNQAECgcIIQAeAD0IAA==.Langris:BAAANQAECgEIAQABNQAECgYICgAHAAAAAA==.Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgYIDgABNQAFFAMICwAfALARAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAABNQAECn8/AAMLAAoKhR+fBwBlAwALAAoKhR+fBwBlAwAkAAEKaRjqDgBJAAAAAA==.Leiche:BAABNQAECn8YAAIbAAoKxhPvKQALAgAbAAoKxhPvKQALAgAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Lichma:BAAANQABCgEIAQAAAA==.Liferia:BAAANQAECgYICAABNQAECgcIDAAHAAAAAA==.Ligerzero:BAAANQAECgEIAQAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgMIBAAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECggIHQAFAIsRAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Littlefry:BAAANQABCgEIAQAAAA==.Livesey:BAABNQAECn8hAAMYAAkKrRPIDgCGAQAYAAkKrRPIDgCGAQAnAAEKAAAGJgAsAAAAAA==.',
Lo='Lockpie:BAAANQADCgQIBAAAAA==.Longshañk:BAABNQAECn8jAAIaAAoKuxhGBACmAgAaAAoKuxhGBACmAgAAAA==.',
Lu='Lucibrew:BAABNQAECn8eAAMEAAoK+Rw2FAC1AgAEAAoK9Bo2FAC1AgAhAAcK1h4uDABCAgAAAA==.Lunaar:BAAANQADCgUIBQAAAA==.Luto:BAAANQAECggIDAAAAA==.Luuko:BAAANQADCgMIAwAAAA==.',
Ma='Mackaveli:BAAANQADCgYIBgAAAA==.Macpreizy:BAAANQADCgQIFQAAAA==.Macshorty:BAAANQADCgMIAwAAAA==.Mattydruid:BAAANQAFFAEIAQAAAA==.Mavelor:BAAANQADCgcIBwAAAA==.Mavramune:BAABNQAECn8nAAIZAAkK1Bh2UwB2AgAZAAkK1Bh2UwB2AgAAAA==.',
Mc='Mcfizzertz:BAAANQAECggIBAAAAA==.Mcfürry:BAAANQAECgQIBAAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECgoKPQAdAJYeAA==.Mendinna:BAAANQADCggIHQABNQAECgkJIwAQAIkNAA==.Mendool:BAAANQADCgcIBwABNQAECgkJIwAQAIkNAA==.Mendoon:BAABNQAECn8jAAIQAAkKiQ23HwCIAQAQAAkKiQ23HwCIAQAAAA==.Methir:BAAANQAECgcICgABNQAECggIMAAHAAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAACNQAFFH8aAAIZAAYKERkCBQAHAgAZAAYKERkCBQAHAgA1AAQKf0EAAhkACgpiJnQDAM8DABkACgpiJnQDAM8DAAAA.Mininetty:BAAANQADCggICAABNQAECgUIDgAHAAAAAA==.Mistborn:BAAANQAECggICQABNQAECgoKHQAPAJscAA==.',
Mo='Moistmaker:BAAANQAECgQIBQAAAA==.Moneygame:BAABNQAECn8cAAISAAoKQhabmwBJAgASAAoKQhabmwBJAgABNQAFFAIIBgAJAEcfAA==.Montebrew:BAAANQADCgYIBgABNQADCgcIDAAHAAAAAA==.Montecane:BAAANQADCgcIDAAAAA==.Mooferrigno:BAAANQAFFAIIAgAAAA==.Mooky:BAABNQAECn8iAAIQAAgKvAn9UACYAQAQAAgKvAn9UACYAQAAAA==.Moonfire:BAAANQAECggJCAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.Moshicat:BAAANQAECgYIDQAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAABNQAECn8ZAAMlAAgKQA45EABKAQAlAAcKQA45EABKAQAbAAUKMwuJ9wDcAAAAAA==.Mythallas:BAAANQADCgIIAgAAAA==.',
Na='Nadezda:BAAANQAECgYIDAAAAA==.Nakir:BAAANQAECgUIDgAAAA==.Nalka:BAAANQAECgIIAgAAAA==.Naraku:BAABNQAECn8/AAMcAAoKfyG9IgBcAQAbAAkKmB1hWwBFAgAcAAQKUSK9IgBcAQAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAABNQAECn8xAAIbAAoK2xFOMgDjAQAbAAoK2xFOMgDjAQAAAA==.Nehemez:BAAANQADCggICAABNQAECgEIAQAHAAAAAA==.Nersing:BAAANQADCgQIBAAAAA==.Neshock:BAAANQAECgIIAgABNQAECgoKIQAQANMTAA==.Nettie:BAAANQAECgUIDgAAAA==.Netty:BAAANQAECgQIBgABNQAECgUIDgAHAAAAAA==.',
No='Nobodygnomes:BAAANQAECggICgAAAA==.Noc:BAAANQADCgYIEwAAAA==.Novakayne:BAAANQADCgMIBAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.Nusy:BAAANQAECgMIAwAAAA==.',
Ny='Nymphetamine:BAABNQAECn8oAAILAAgK2hXMQQCrAQALAAgK2hXMQQCrAQAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAABNQAECn89AAIiAAoKow9KEADBAQAiAAoKow9KEADBAQAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgcIIQAZANcQAA==.',
Ow='Owenwilson:BAAANQAECgEIAQAAAA==.',
Pa='Pandaloco:BAAANQAECgMIAwAAAA==.Pandalôc:BAAANQAECgUIDgAAAA==.Pandoe:BAACNQAFFH8dAAIMAAcK0SBoAABjAgAMAAcK0SBoAABjAgA1AAQKf0IAAgwACgqRJlgAAI8DAAwACgqRJlgAAI8DAAAA.',
Pe='Penelopea:BAABNQAECn8fAAMRAAkKnxN4CACWAQARAAgKrBV4CACWAQASAAcKnwrKCQF8AQAAAA==.Perun:BAABNQAECn8VAAMGAAcK0ht0cgDJAQAGAAYKhRp0cgDJAQAFAAIKuQSfDgFLAAAAAA==.',
Ph='Phaithfulnes:BAAANQADCgUIBQABNQAECgcIHwAoAPwcAA==.Phenomenal:BAABNQAECn8XAAIiAAgK1hhFJgAaAgAiAAgK1hhFJgAaAgAAAA==.Pheonyx:BAAANQAECgUIBQAAAA==.',
Pi='Picarus:BAAANQAECgQIBgAAAA==.Picklerìck:BAABNQAECn8UAAISAAgK0ww4jQAoAQASAAgK0ww4jQAoAQAAAA==.',
Pl='Planb:BAAANQAECgYICwABNQAECgoKVQAbAOMWAA==.',
Pn='Pneumonya:BAAANQAECggICwAAAA==.',
Po='Porteagarder:BAAANQAECgcIEQABNQAECgcIEwAHAAAAAA==.',
Pr='Preparedpie:BAACNQAFFH8aAAMJAAcKjRC4BAA/AQAJAAcKjRC4BAA/AQAgAAQKRAwjCwAXAQA1AAQKf0kAAwkACgoTIl4NAD0DAAkACQpJIl4NAD0DACAACQqfIC0LACoDAAAA.Priarace:BAABNQAECn8XAAMIAAoKMBZSdwBkAQAIAAcKNRFSdwBkAQAjAAcKwwylzQDgAAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAgIGgATAOoXAA==.Producktive:BAAANQAECgMIAwABNQAECggIGgABAEcfAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQAECgQIBAABNQAECggILAAmAE0KAA==.Príestly:BAAANQAECgcIDQAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgUIBAAAAA==.',
Py='Pyatt:BAABNQAECn8uAAIlAAoKQBlwAgAwAgAlAAoKQBlwAgAwAgAAAA==.Pyromaniacal:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändaloc:BAAANQAECgEIAQAAAA==.',
Qe='Qe:BAAANQADCgQIBAAAAA==.',
Qu='Quack:BAAANQAECggIDAAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECggIDAAHAAAAAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCggILQABNQAECgcIEwAHAAAAAA==.Quëën:BAAANQAECgMIAwAAAA==.',
Qy='Qyburn:BAABNQAECn8ZAAMBAAkKbx0UGAC7AgABAAkKbx0UGAC7AgADAAMKixqJPQDMAAAAAA==.',
Ra='Radacast:BAAANQABCgIIAgAAAA==.Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQADCgcIBwABNQAECgUIFwASAH0PAA==.Ragecage:BAAANQAECgIIAgABNQAECgkJIAAbAIQXAA==.Ragga:BAAANQADCgcICgAAAA==.Randivh:BAAANQADCgYIDAAAAA==.Rassputin:BAABNQAECn8bAAISAAcKXBWKYACMAQASAAcKXBWKYACMAQAAAA==.Raye:BAAANQADCgYIBgAAAA==.',
Re='Recipes:BAABNQAECn8dAAMPAAoKmxxyDQCtAgAPAAoKmxxyDQCtAgAhAAEKAADlIwAAAAAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgABNQAECgoKGwAJAEUTAA==.Rendezvous:BAAANQAECgIIAQAAAA==.Renkà:BAABNQAECn87AAIGAAoKwhu2KwDQAgAGAAoKwhu2KwDQAgAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECn89AAIVAAoK1B4pHADjAgAVAAoK1B4pHADjAgAAAA==.Reyanne:BAAANQAECgMIAwABNQAECgQICgAHAAAAAA==.',
Rh='Rheas:BAAANQADCgYIDAABNQAECggIBAAHAAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAgIGgATAOoXAA==.',
Rn='Rn:BAAANQADCgQIBAAAAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEJAQABNQAECggIBAAHAAAAAA==.Roflthump:BAAANQADCgcJBwAAAA==.Roketraccoon:BAAANQAECgIIBAAAAA==.Rolenstrong:BAAANQADCgEIAQAAAA==.Rootbreaker:BAAANQAECgEIAQABNQAECgYICgAHAAAAAA==.Rosamyna:BAEANQADCgQIBwABNQAECgUIFwASAH0PAA==.Roshamandes:BAABNQAECn8vAAIKAAoKdhljAwBTAgAKAAoKdhljAwBTAgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgcIIwAeAJUGAA==.Runep:BAAANQAECgEIAQAAAA==.Runstupid:BAAANQADCgcICwAAAA==.',
['Rè']='Rèi:BAAANQAECgMICAABNQAECgoKOgAZACwhAA==.',
Sa='Sabermage:BAAANQAECgYICQAAAA==.Sacredchikín:BAABNQAECn8hAAMbAAkKlhyvKwDWAgAbAAkKlhyvKwDWAgAcAAEKuBQwdgA4AAAAAA==.Sagris:BAAANQADCgcICAAAAA==.Samuel:BAAANQAECgIIBwAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgcIDAAAAA==.Saxa:BAABNQAECn85AAIgAAoKVCLTBADaAgAgAAoKVCLTBADaAgAAAA==.',
Sc='Screamsoda:BAAANQAECgUICgABNQAECgoKHQAPAJscAA==.Scrubzz:BAAANQAECgYIDAAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekobrew:BAAANQADCgYICQAAAA==.Seyekolock:BAABNQAECn8YAAIbAAgKKhECXABQAQAbAAgKKhECXABQAQAAAA==.Seyekosis:BAABNQAECn8pAAIgAAkKJBpoDwDyAQAgAAkKJBpoDwDyAQAAAA==.',
Sg='Sgathaich:BAEANQAECgUIBwABNQAECgYIBwAHAAAAAA==.',
Sh='Shadowzform:BAAANQABCgYIBAABNQAECgQICAAHAAAAAA==.Shallistiah:BAABNQAECn8iAAMQAAgKnwy0TQCqAQAQAAgKnwy0TQCqAQANAAYKwQxAQwASAQAAAA==.Shamadin:BAAANQAECgMIAwAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdh:BAAANQAECgYIDAAAAA==.Shamdwarf:BAAANQAECggIDAAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQAECgIIAgAAAA==.Shobadon:BAAANQAECggIDQAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgQICAAAAA==.',
Si='Siatral:BAACNQAFFH8QAAIYAAUKqBzLBQB3AQAYAAUKqBzLBQB3AQA1AAQKfzkABBgACgp5JOoEAF8DABgACgp5JOoEAF8DACcABgr/Gt0JAPIAACYAAQqTEKcbAEAAAAAA.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQAECgMIBAABNQAECggIBAAHAAAAAA==.Sigvolden:BAAANQAECgEJAQABNQAECggIBAAHAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAABNQAECn8yAAMRAAoKZBhOBAAuAgARAAoKZBhOBAAuAgASAAYKwQL6VgEAAQAAAA==.Silver:BAAANQAECgIIAgABNQAECgoKMgARAGQYAA==.Siona:BAABNQAECn81AAIZAAoKFAlSTAC4AQAZAAoKFAlSTAC4AQAAAA==.Sixpaths:BAAANQAECgYIEwABNQAECgoKHQAPAJscAA==.Siyunkai:BAEANQAECgMIBAABNQAECgUICQAHAAAAAA==.Siyunprai:BAEANQAECgUICQAAAA==.Siyunzu:BAEANQAECgIIAgABNQAECgUICQAHAAAAAA==.',
Sk='Skadie:BAABNQAECn81AAIZAAoKPRYtKgA4AgAZAAoKPRYtKgA4AgAAAA==.Skittellz:BAAANQABCgMIAwAAAA==.Skiye:BAAANQADCgcICgAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgAHAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgAHAAAAAA==.Skwup:BAABNQAECn8tAAMjAAoKvBeBLgCsAgAjAAoKvBeBLgCsAgAIAAQKpxaMGgHzAAAAAA==.',
Sl='Slackness:BAAANQAECgEIAQAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slappygilmor:BAAANQADCgcIBwABNQAECgQIDAAHAAAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggJCQABNQAFFAUIFQASAOcZAA==.Sleepybeard:BAAANQAECgQICAAAAA==.Slubadub:BAABNQAECn8aAAQKAAkKmx0XDQDxAQAgAAgKThtpHwBUAgAKAAUKySIXDQDxAQAJAAUKHhNVVgAzAQABNQAFFAIIAgAHAAAAAA==.',
Sm='Smiteslay:BAAANQAECgUICgABNQAFFAUIFQASAOcZAA==.',
Sn='Snivels:BAABNQAECn8VAAMQAAcKKQwwWAB0AQAQAAcKKQwwWAB0AQAOAAMKjgyULwCVAAAAAA==.Snïpe:BAAANQABCgQIBAAAAA==.',
So='So:BAABNQAECn8gAAILAAoKVSEPDgAJAwALAAoKVSEPDgAJAwAAAA==.Soggycat:BAEANQADCgEIAQAAAA==.Soil:BAABNQAECn8uAAIlAAoKwSH/AABqAwAlAAoKwSH/AABqAwAAAA==.Somna:BAAANQAECgUJCwAAAA==.',
Sp='Sparrkle:BAABNQAECn84AAIcAAoKNgi0BgAUAQAcAAoKNgi0BgAUAQAAAA==.Spawnkis:BAAANQADCggIEAAAAA==.Spayme:BAAANQAECgEIAQAAAA==.Spida:BAAANQADCgIIAgAAAA==.Spinecrawler:BAABNQAECn8gAAIbAAkKhBeuSwBwAgAbAAkKhBeuSwBwAgAAAA==.Spyro:BAAANQAECgIIAwAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIIAgAHAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgMIBAAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stickshamm:BAAANQAECgEIAQAAAA==.Stiick:BAABNQAECn81AAIoAAoKWRlqCgAPAgAoAAoKWRlqCgAPAgAAAA==.Stonecracker:BAAANQADCgMIBAAAAA==.Stöut:BAAANQAECgIIAgABNQAECgYICgAHAAAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.Sudsy:BAAANQADCgUICAABNQAECggIGQAXAIQaAA==.Supadupaman:BAABNQAECn8VAAIIAAoKOwNgHwHrAAAIAAoKOwNgHwHrAAAAAA==.Supaman:BAAANQABCgUIBwAAAA==.',
Sw='Sweetbippy:BAABNQAECn8XAAIRAAkKpAXUHgD0AAARAAkKpAXUHgD0AAAAAA==.Swifthealss:BAABNQAECn8bAAMMAAgKURGLJgBhAQAMAAgKURGLJgBhAQAOAAEKDQX8NwAZAAAAAA==.Swirls:BAAANQAECgMIBAAAAA==.',
Sy='Sylunae:BAAANQAECgEIAQABNQAECgcIEwAHAAAAAA==.Syluné:BAAANQAECgcIEwAAAA==.',
Ta='Tabasco:BAAANQAECgcIDAABNQAFFAgIGgATAOoXAA==.Tacoshaman:BAAANQADCgIJAgABNQAECgMIAwAHAAAAAA==.Tacozpriest:BAAANQAECgIIAgABNQAECgMIAwAHAAAAAA==.Taelyx:BAAANQAECgYIEwAAAA==.Taishyoo:BAAANQADCgUIBgAAAA==.Tamago:BAAANQAECgYIBgABNQAFFAgIGAAjAPESAA==.Tambot:BAAANQAECgcICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgYIEQAAAA==.Tazmina:BAABNQAECn8hAAIJAAYKwB6eQgCtAQAJAAYKwB6eQgCtAQAAAA==.',
Te='Teddykgb:BAAANQAECgYICAAAAA==.Teenieweenie:BAAANQADCgcICgAAAA==.Tequilàrose:BAAANQADCgYIBwABNQAECgQIDAAHAAAAAA==.Tessa:BAABNQAECn81AAIGAAoK7RJzJwDJAQAGAAoK7RJzJwDJAQAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAABNQAECn8zAAQLAAoKAx5UMQCjAgALAAkKDB9UMQCjAgAUAAoKUxiQCgBGAgAkAAEKvQkRLQAqAAAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Thejudge:BAABNQAECn8XAAIoAAkKzR+ABADUAgAoAAkKzR+ABADUAgABNQAFFAIIAgAHAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinkey:BAAANQAECgMIAwAAAA==.Tinyjapeto:BAAANQAECgUIDgAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAABNQAECn81AAIZAAoKCyB6EgC8AgAZAAoKCyB6EgC8AgAAAA==.Tortapounder:BAAANQAECgUIDQAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgUICwAAAA==.',
Tu='Turin:BAABNQAECn84AAITAAoKAAsJDQBnAQATAAoKAAsJDQBnAQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twiggysmalls:BAAANQADCgUIBAAAAA==.Twilghtdawn:BAAANQADCgUIBQAAAA==.Twotone:BAAANQAECggICAAAAA==.',
Ty='Tybo:BAABNQAECn8cAAIdAAcK5R2gDADLAQAdAAcK5R2gDADLAQAAAA==.Tycho:BAAANQADCgYIDQAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.Tydros:BAAANQADCggICAAAAA==.Tyriondale:BAAANQADCgEIAQAAAA==.',
Un='Uncás:BAABNQAECn8nAAIZAAcKVQsQvQCJAQAZAAcKVQsQvQCJAQAAAA==.Undyinggnome:BAAANQAECgQIBwAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.Update:BAAANQAECggICAAAAA==.',
Ur='Urza:BAAANQADCgQIBAAAAA==.',
Va='Vaelock:BAABNQAECn8nAAQlAAgKiw+iCgDrAAAbAAgKnA7ppgCGAQAlAAUKSguiCgDrAAAcAAIKwQVidgA3AAAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQAECgQIBAAAAA==.Valorman:BAAANQADCgQIBAAAAA==.Valoryan:BAABNQAECn81AAINAAoKeBxmCwCCAgANAAoKeBxmCwCCAgAAAA==.Valy:BAAANQADCgcIBwAAAA==.Valyteilssra:BAAANQAECgQIBAAAAA==.Vasoline:BAAANQAECggIDQABNQAECgoKJAAeABIgAA==.Vaxtur:BAAANQAECggICAAAAA==.',
Ve='Vegà:BAABNQAECn8jAAMhAAYKzQ89GgBBAQAhAAYKzQ89GgBBAQAEAAQKOgs/VgCSAAAAAA==.Vendettis:BAAANQAECgEIAQAAAA==.Veracious:BAAANQAECgQIBAAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYJBgABNQAECgUIBwAHAAAAAA==.Veylyn:BAABNQAECn8cAAIIAAYKFgjMAQEcAQAIAAYKFgjMAQEcAQAAAA==.Veztaroth:BAABNQAECn8lAAIVAAgKixDwKwAiAQAVAAgKixDwKwAiAQAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQAECgIIAgAAAA==.Voidyo:BAABNQAECn89AAMgAAoKGiUFAwCpAwAgAAoKGiUFAwCpAwAJAAgKYR6mHwCdAgAAAA==.',
['Vë']='Vëngeåncelöt:BAAANQADCgQIBAAAAA==.',
Wa='War:BAAANQADCggICAABNQAECggIKAAOAIUTAA==.',
We='Weißenacht:BAAANQAECgMIAwAAAA==.Wenno:BAAANQAECgYIDAAAAA==.',
Wh='Whiskeyjak:BAABNQAECn8qAAMTAAoKfBhOCwCIAgATAAgKcx1OCwCIAgAfAAoK4gxvrACuAQAAAA==.Whycatihealu:BAAANQADCggIGQAAAA==.',
Wi='Willowbark:BAAANQADCgYIEwAAAA==.Willowest:BAABNQAECn9IAAIZAAoKoyEcEABkAwAZAAoKoyEcEABkAwAAAA==.Wizbizzler:BAABNQAECn8UAAISAAkKWSHUeACMAgASAAkKWSHUeACMAgAAAA==.',
Wr='Wrathstorm:BAABNQAECn89AAIdAAoKlh67BABGAwAdAAoKlh67BABGAwAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanier:BAAANQADCgYIGAABNQAECgcIJQAlAMQQAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAABNQAECn8XAAIhAAkKoQMFHgAGAQAhAAkKoQMFHgAGAQAAAA==.Xithia:BAEBNQAECn8YAAMWAAkKVRdeJwCXAQAWAAkKVRdeJwCXAQAeAAEKAACS1wAmAAAAAA==.',
Xo='Xorm:BAAANQAECggICAAAAA==.',
Xx='Xxcor:BAAANQAECgYIBgAAAA==.',
Xy='Xyndylyne:BAAANQADCgcIBwAAAA==.',
Ya='Yahtze:BAAANQADCgYIBgAAAA==.Yanella:BAABNQAECn8yAAILAAoK+RolGAChAgALAAoK+RolGAChAgAAAA==.',
Yi='Yisdk:BAAANQAECgUICQAAAA==.Yispally:BAAANQAECgQICQAAAA==.Yisshaman:BAAANQAECgcIEQAAAA==.',
Yo='Yogibearz:BAAANQAECgEIAQABNQAECgQICQAHAAAAAA==.',
Yu='Yunbao:BAAANQAECgEIAwAAAA==.',
Za='Zaijr:BAAANQAECgMIAwAAAA==.Zanax:BAABNQAECn8WAAIbAAcKvgydjwDRAAAbAAcKvgydjwDRAAAAAA==.Zandarbribbs:BAAANQAECgIIAwAAAA==.Zanrelia:BAAANQADCgQIBAAAAA==.Zarrah:BAAANQABCgYICgAAAA==.',
Ze='Zennya:BAABNQAECn8sAAINAAoKvx8rCQC3AgANAAoKvx8rCQC3AgAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.Zeon:BAAANQABCgcICQAAAA==.',
Zo='Zoldyck:BAAANQADCggIKAAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zynnitar:BAAANQADCggICQAAAA==.Zyrx:BAAANQADCggIDwAAAA==.',
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
