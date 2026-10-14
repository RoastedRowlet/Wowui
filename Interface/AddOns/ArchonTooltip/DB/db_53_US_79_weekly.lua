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

local lookup = {'Druid-Balance','Mage-Arcane','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Paladin-Retribution','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Devastation','Unknown-Unknown','Druid-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Augmentation','DemonHunter-Havoc','Priest-Holy','DemonHunter-Devourer','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Druid-Feral','Warrior-Protection','Druid-Guardian','Rogue-Outlaw','Hunter-Survival',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaronius:BAAANQAECgUIDAAAAA==.',
Ac='Acceptance:BAAANQAECgEIAQAAAA==.',
Ad='Adoe:BAAANQAECgYIEQAAAA==.Adora:BAAANQAECgMJBQAAAA==.',
Ae='Aeveen:BAAANQADCggIDwAAAA==.',
Ag='Agaliarept:BAAANQADCgMIAwAAAA==.Agathos:BAAANQADCggIFQAAAA==.',
Ai='Aidenator:BAAANQAECgYIEQAAAA==.',
Al='Aluni:BAAANQADCgEIAQAAAA==.',
Am='Ammastin:BAAANQABCgMIAwAAAA==.',
An='Andorix:BAAANQAECgMIAwAAAA==.Andretta:BAAANQAECgIIAgAAAA==.Angelneko:BAABNQAECn8fAAIBAAYKrgZgcQAAAQABAAYKrgZgcQAAAQAAAA==.',
Ar='Arinthian:BAAANQAECgQIBAAAAA==.Artrian:BAAANQAECgYIDwAAAA==.',
At='Atetoomuch:BAAANQABCgYIBgAAAA==.Atthis:BAAANQADCgEIAQAAAA==.',
Au='Auroraa:BAAANQAECgQIDQAAAA==.',
Av='Avalectra:BAAANQAECgEIAQAAAA==.',
Az='Azmodeaz:BAABNQAECn8nAAICAAcKJA587QCsAQACAAcKJA587QCsAQAAAA==.Azraely:BAAANQADCgcIBwAAAA==.Aztrik:BAABNQAECn8ZAAQDAAcKQx+aVgBPAgADAAYKaR+aVgBPAgAEAAEKAAA0IQBtAAAFAAEKrR74ZABYAAAAAA==.',
Ba='Bajapanti:BAABNQAECn8cAAIGAAgK4g4EMgC6AQAGAAgK4g4EMgC6AQAAAA==.Ballyhøø:BAAANQAFFAEIAQAAAA==.Bandaron:BAAANQADCgYIBgAAAA==.Baxstab:BAABNQAECn8jAAMHAAgKQxZCKQBEAgAHAAgKQxZCKQBEAgAIAAIKMgo8SABwAAAAAA==.',
Be='Belladeon:BAABNQAECn8eAAMJAAkKABZ/CwAFAgAJAAcKlxd/CwAFAgACAAgK0Qd38QClAQAAAA==.',
Bh='Bhagee:BAAANQADCgUICgAAAA==.',
Bl='Blackpatch:BAABNQAECn8fAAMKAAgKMxt3GACAAgAKAAgKMxt3GACAAgALAAQKXAP4JgCOAAAAAA==.Blacksheep:BAAANQADCggIAQAAAA==.Blaqkid:BAAANQADCgYIBgAAAA==.Blaqsun:BAABNQAECn8dAAIMAAcK6BDRhgCPAQAMAAcK6BDRhgCPAQAAAA==.Blargg:BAAANQAECgUIBwAAAA==.Bleeda:BAAANQADCggIAQAAAA==.Bloomhammer:BAAANQAECgEIAQAAAA==.Blooming:BAABNQAECn8gAAINAAcKkh0VQQBeAgANAAcKkh0VQQBeAgAAAA==.',
Bo='Booneboy:BAAANQAECgUIEAAAAA==.Botemedel:BAABNQAECn8bAAIOAAcK3RgmHgD1AQAOAAcK3RgmHgD1AQABNQAECgkJIQAPACARAA==.',
Br='Brennor:BAABNQAECn8jAAIQAAgK5QcwzgB5AQAQAAgK5QcwzgB5AQAAAA==.Brewslunt:BAABNQAECn8bAAIRAAkKDxnbDgCPAgARAAkKDxnbDgCPAgABNQAFFAYIFAASAIIVAA==.Bronamaly:BAAANQADCgYICAAAAA==.',
Ca='Cabbagehunt:BAAANQADCgcIDQAAAA==.Caeden:BAABNQAECn8eAAISAAgK1QxOgQCEAQASAAgK1QxOgQCEAQAAAA==.Cairyan:BAABNQAECn8iAAITAAkKNxh+CABrAgATAAkKNxh+CABrAgAAAA==.Caiya:BAAANQADCgcIBwABNQAECgcIGQAHALQiAA==.Cassin:BAAANQADCgUIBwAAAA==.Castalia:BAAANQAECgUIEAAAAA==.Cattilina:BAAANQADCggIEAAAAA==.',
Ce='Celenara:BAACNQAFFH8HAAICAAMK4hTYNQDpAAACAAMK4hTYNQDpAAA1AAQKfycAAwIACQqwHalfAMACAAIACQqwHalfAMACAAkAAgohC+c3AFsAAAAA.Celendil:BAAANQADCgUIBQABNQAFFAMIBwACAOIUAA==.Celinne:BAAANQADCgUIBQAAAA==.Celithe:BAAANQAECgIIBQAAAA==.',
Ch='Charlereaux:BAAANQADCggICQAAAA==.Charmcaster:BAABNQAECn8YAAICAAgKRBenpQA1AgACAAgKRBenpQA1AgAAAA==.Charmstrike:BAAANQAECgIIBAAAAA==.Chedissa:BAAANQADCgQIBAAAAA==.Chleo:BAAANQAECgQIDwAAAA==.Choco:BAACNQAFFH8dAAIUAAcKBSAIAgCbAgAUAAcKBSAIAgCbAgA1AAQKfywAAxQACQrOIf4IABIDABQACQrOIf4IABIDABUAAgpUF2syAHkAAAAA.Chocolat:BAAANQADCggICAABNQAFFAcIHQAUAAUgAA==.Chudfox:BAAANQADCgEJAQAAAA==.',
Co='Coggler:BAAANQAECgUIDAAAAA==.Conqueror:BAAANQAECgQIBwABNQAECgcIDgAWAAAAAA==.Corcia:BAAANQAECgEIAQAAAA==.',
Cr='Creatlach:BAAANQAECgIIAgABNQAFFAYIFAASAIIVAA==.Crotchpox:BAAANQADCgQIBAAAAA==.Crualti:BAAANQAECgcIEgAAAA==.',
Cu='Cuppajoe:BAAANQADCgMIAwAAAA==.Cupper:BAAANQABCgcJCQABNQAECgUIDAAWAAAAAA==.Curmudge:BAABNQAECn8qAAIXAAgKxhfXHgAzAgAXAAgKxhfXHgAzAgAAAA==.',
Da='Dabtoomuch:BAAANQABCgIIAgAAAA==.Dalectra:BAAANQAECgQICAAAAA==.Darachane:BAAANQAECgIIAgAAAA==.Darkpriest:BAAANQAECgIIAgAAAA==.Darovan:BAAANQADCggJEAABNQAECgYIIgAYAPYfAA==.Darthnater:BAAANQAECggIEAAAAA==.Dauglow:BAABNQAECn8jAAMZAAgKiA8XdQAjAgAZAAgKiA8XdQAjAgAGAAEKhwkdhAA4AAAAAA==.',
De='Deathball:BAAANQAECgEIAQAAAA==.Deathstars:BAAANQADCgcIDQAAAA==.Deboss:BAAANQAECggICQAAAA==.Dellianne:BAAANQABCgEIAQAAAA==.Delritha:BAAANQAECgQICAAAAA==.Deltithrax:BAABNQAECn8fAAMaAAYKPxHeDgBRAQAaAAYKPxHeDgBRAQAVAAIK1w5FNQBgAAAAAA==.Demonagent:BAAANQAECgUIDAAAAA==.Desdh:BAACNQAFFH8IAAIbAAMKXBWEEQDWAAAbAAMKXBWEEQDWAAA1AAQKfykAAhsACApsIVUaAMQCABsACApsIVUaAMQCAAAA.Devious:BAAANQAECgYIBgABNQAECgcIIAANAJIdAA==.',
Di='Dinö:BAAANQAECgMJBAABNQAECggIFwAZAKMRAA==.',
Dm='Dmnslyer:BAAANQADCggIDQAAAA==.',
Do='Docspades:BAABNQAECn8cAAIcAAcKbBOiegCmAQAcAAcKbBOiegCmAQAAAA==.Dohane:BAAANQADCgQIBAABNQAECgYICgAWAAAAAA==.Domrogue:BAAANQAECgIIAgAAAA==.Dornoch:BAAANQADCggIHAAAAA==.',
Dr='Dramine:BAAANQADCgQIBwAAAA==.Draone:BAABNQAECn8dAAICAAcKbQscBAGDAQACAAcKbQscBAGDAQAAAA==.Dreabolic:BAAANQADCgYICwAAAA==.Dreamss:BAABNQAECn8nAAMbAAkKnBMVLwApAgAbAAgK3RQVLwApAgAdAAgKvAaMOAB7AQAAAA==.Drhkillinger:BAAANQAECgUIBQABNQAECgUIDAAWAAAAAA==.Drspades:BAAANQAECgEIAQAAAA==.',
Du='Dugosh:BAAANQADCggICAAAAA==.Duzz:BAAANQABCggIFwAAAA==.',
['Dé']='Démetal:BAAANQADCggIDgAAAA==.',
Ei='Einherja:BAABNQAECn8WAAQeAAgKPRj4aABqAQAeAAYKexj4aABqAQAfAAYK1RHuWgA2AQAYAAEKAABWtgBYAAAAAA==.',
El='Elessaria:BAAANQAECgUIEAAAAA==.Elfatheàrt:BAAANQADCggIHAAAAA==.Elidrus:BAAANQADCgYICgABNQAECgYICgAWAAAAAA==.',
En='Enodlo:BAAANQADCgUIBQAAAA==.',
Er='Erora:BAABNQAECn8iAAIgAAkKixfEGQB9AgAgAAkKixfEGQB9AgAAAA==.',
Es='Estherras:BAAANQAECgYIEgAAAA==.',
Fe='Feardotrun:BAABNQAECn8bAAMFAAYKHxEcOADfAAADAAYKHxEyrQByAQAFAAQKewscOADfAAAAAA==.Felicious:BAAANQADCggIHAAAAA==.',
Fi='Finally:BAAANQADCggIHAAAAA==.Firemage:BAABNQAECn8kAAMDAAkKYySAJgDnAgADAAcKjCSAJgDnAgAFAAQKuSLNHwBwAQAAAA==.Fizzanelf:BAAANQAECgEIAQAAAA==.',
Fl='Flokíe:BAAANQADCggICAAAAA==.',
Fo='Fortytwo:BAAANQAECggIEAAAAA==.',
Fr='Freyá:BAAANQAECgEIAgAAAA==.Friendo:BAABNQAECn8bAAMBAAgKkAqsUQCRAQABAAgKkAqsUQCRAQAhAAEK8AjPRgAoAAAAAA==.Frostbight:BAABNQAECn8jAAICAAgKaBaglwBQAgACAAgKaBaglwBQAgAAAA==.Frostied:BAAANQAECgYIDgAAAA==.',
Fu='Futnuraz:BAAANQADCggIFQAAAA==.',
Fy='Fyrakkobama:BAAANQAECgYIBgABNQAECggIDQAWAAAAAA==.Fyriat:BAAANQAECgYIEgAAAA==.',
Ga='Galathel:BAABNQAECn8gAAIOAAcKUxRGKQCPAQAOAAcKUxRGKQCPAQABNQAECggIHAASACkcAA==.Gazardiel:BAAANQAECgQIEQAAAA==.',
Ge='Gelinia:BAAANQAECgYIEgAAAA==.Gerrald:BAAANQADCgQIBAABNQAECggIFwAZAKMRAA==.Getafix:BAAANQAECgQIBAABNQAECggIHAASACkcAA==.',
Gi='Girthquakes:BAAANQAECgEIAQAAAA==.',
Gl='Glorbo:BAAANQAECgYIEgAAAA==.',
Go='Goldstorm:BAAANQADCggIDwAAAA==.Goliath:BAABNQAECn8XAAMSAAYKtRXZiwBoAQASAAYKtRXZiwBoAQAMAAUKWBCHsgApAQAAAA==.',
Gr='Gregoron:BAAANQABCgYIBgAAAA==.Grimfelborn:BAACNQAFFH8GAAMDAAMKqw31MACXAAADAAIKqw31MACXAAAEAAEKAADXEgA6AAA1AAQKfycAAwMACQo1GQlMAGwCAAMACQo1GQlMAGwCAAQAAQoAAMomAE8AAAAA.Grimosh:BAAANQAECgEIAQAAAA==.Grondosh:BAAANQAECgQIBwAAAA==.Gryphindor:BAAANQAECgYIEAAAAA==.',
['Gì']='Gìorgìa:BAAANQABCgIIAwAAAA==.',
Ha='Hahwe:BAAANQADCgIIAgABNQAECgYICgAWAAAAAA==.Haljo:BAAANQADCgQJBAAAAA==.Hanoverfiste:BAAANQAECgUIDAAAAA==.Hapsburg:BAABNQAECn8jAAMRAAgKfw/gIwBcAQARAAcKfA7gIwBcAQAKAAcKIghTPAAuAQAAAA==.Havince:BAABNQAECn8aAAIYAAgKbiLJGADlAgAYAAgKbiLJGADlAgAAAA==.Hawktuah:BAAANQAECgEIAgAAAA==.Haylee:BAAANQABCgIIAgAAAA==.',
He='Helle:BAAANQAECgIIAgAAAA==.Hercboyy:BAABNQAECn8hAAMNAAgKZCMXGgANAwANAAcKgSYXGgANAwAOAAEKAADVYABVAAAAAA==.',
Hi='Higgs:BAAANQADCggICQABNQAECgcIHAANACITAA==.Higgspally:BAABNQAECn8cAAINAAcKIhNXeACsAQANAAcKIhNXeACsAQAAAA==.',
Ho='Holyball:BAABNQAECn8fAAIQAAkKcRa7XQB7AgAQAAkKcRa7XQB7AgAAAA==.Holytalon:BAAANQADCgIIAgAAAA==.Hotak:BAAANQABCgYIBAAAAA==.',
Hu='Hughjahsol:BAAANQADCgIIAgAAAA==.Hukaru:BAAANQABCgIIAgABNQAECggIGgAYAG4iAA==.Huuken:BAAANQADCggIDgAAAA==.Huulkster:BAAANQADCgQIBAAAAA==.',
Hy='Hydra:BAAANQAECgEJAQAAAA==.',
Il='Ilovehunter:BAAANQADCggICAAAAA==.Ilyndra:BAABNQAECn8fAAIiAAYKbyVUCwCFAgAiAAYKbyVUCwCFAgAAAA==.',
In='Infernella:BAAANQADCgMIAwAAAA==.',
Ir='Ironskin:BAAANQAECgQIBwAAAA==.',
Is='Iselilja:BAAANQAECgYIEgAAAA==.',
It='Ithea:BAABNQAECn8lAAICAAkKJRS0fACFAgACAAkKJRS0fACFAgAAAA==.',
Ja='Jackshots:BAAANQADCgIIAgAAAA==.Jaeson:BAEANQAECgUIDQAAAA==.Jakaro:BAACNQAFFH8JAAMFAAMK2gcdEgCJAAAFAAIK/AQdEgCJAAADAAEKlg1IPwBLAAA1AAQKfxoAAwUACAq1EewqACUBAAMABgrjETSmAIIBAAUABQovEewqACUBAAAA.Javoren:BAAANQADCgcIBwAAAA==.',
Je='Jeefgpt:BAAANQAECgEIAQABNQAECggIDQAWAAAAAA==.Jeefrenzy:BAAANQAECggIDQAAAA==.Jeefwrld:BAAANQAECgYICQAAAA==.Jeffers:BAAANQAECgEIAgABNQAECggIDQAWAAAAAA==.Jeffha:BAAANQADCggICAAAAA==.',
Ji='Jiinx:BAABNQAECn8fAAMZAAYKSRmDfwAKAgAZAAYKSRmDfwAKAgAGAAUKrwuBTAD8AAAAAA==.',
Jo='Joap:BAAANQADCgcIBwAAAA==.Joejr:BAABNQAECn8eAAMcAAgKHRaCbADUAQAcAAcKMheCbADUAQAgAAUK7RE0PABFAQAAAA==.Jonald:BAABNQAECn8YAAIdAAgKTQ7pMgCmAQAdAAgKTQ7pMgCmAQAAAA==.',
Jt='Jtizlfrizl:BAAANQAECgUIEAAAAA==.',
Ju='Juniperz:BAAANQAECgYIEgAAAA==.',
Jw='Jwise:BAAANQADCgQIBAAAAA==.',
Ka='Kaaydenn:BAAANQAECgUIEwAAAA==.Kaghro:BAAANQADCgcICAAAAA==.Kalaziel:BAAANQAECgcIBwAAAA==.Kalierix:BAAANQAECggIDAAAAA==.Kamus:BAAANQADCgcIDAAAAA==.Karawyn:BAAANQAECgEIAgABNQADCgQICAAWAAAAAA==.Karelix:BAAANQADCgIIAgAAAA==.Katrichi:BAAANQAECgIIAwAAAA==.Katrishy:BAACNQAFFH8IAAIgAAMK9xdeDgDoAAAgAAMK9xdeDgDoAAA1AAQKfycAAiAACQoKHcESANMCACAACQoKHcESANMCAAAA.Kayde:BAAANQAECgQIBQAAAA==.',
Ke='Keedrid:BAABNQAECn8eAAIeAAgK/R75JgCdAgAeAAgK/R75JgCdAgAAAA==.Kelaeno:BAABNQAECn8cAAIMAAgK/AykbgDRAQAMAAgK/AykbgDRAQAAAA==.Kev:BAACNQAFFH8LAAINAAMKeRumFQD/AAANAAMKeRumFQD/AAA1AAQKfyUAAg0ACQqqJJIEAKwDAA0ACQqqJJIEAKwDAAAA.',
Ki='Kirima:BAAANQADCggICAAAAA==.Kirmit:BAAANQAECgQIBAAAAA==.',
Kl='Klevege:BAAANQADCgUIBQAAAA==.',
Kn='Knoll:BAAANQAECgIIBAAAAA==.',
Kr='Kreeona:BAABNQAECn8cAAISAAgKKRyINwB+AgASAAgKKRyINwB+AgAAAA==.Kruàlty:BAABNQAECn8dAAMhAAgKXhY6DQBGAgAhAAgKXhY6DQBGAgABAAMKewiMkACPAAAAAA==.',
La='Laird:BAAANQADCgcICwAAAA==.',
Le='Legreecast:BAAANQADCgcIGgAAAA==.',
Li='Liare:BAACNQAFFH8VAAQEAAYKpiDFAwCyAAADAAMKNyIRGgApAQAFAAIKsSDkBwC0AAAEAAIKlRzFAwCyAAA1AAQKfysABAMACQqjJWMKAHgDAAMACQqjJWMKAHgDAAUABgoxH+AWALQBAAQAAgqZJTQXANQAAAAA.Liasong:BAAANQAECgIIAgAAAA==.Litheliice:BAABNQAECn8jAAIcAAgKhRYnVQAgAgAcAAgKhRYnVQAgAgAAAA==.',
Lo='Lodur:BAAANQAECgUIEAAAAA==.Lonen:BAAANQAECgYIDAAAAA==.Losat:BAABNQAECn8aAAIiAAcKXwd3JAAeAQAiAAcKXwd3JAAeAQAAAA==.',
Lu='Lukeluke:BAAANQADCgQIBwAAAA==.',
['Lî']='Lîîght:BAAANQADCggIHgAAAA==.',
Ma='Machiato:BAAANQADCggIEAAAAA==.Mackkie:BAABNQAECn8cAAMRAAYKWhLKJABSAQARAAYKWhLKJABSAQAKAAYKZQV7RwDeAAAAAA==.Madonkadonk:BAABNQAECn8fAAIVAAgK/gXtHAB8AQAVAAgK/gXtHAB8AQAAAA==.Maedai:BAAANQAECgUIDgAAAA==.Maeli:BAAANQAECgEIAQAAAA==.Magladroth:BAAANQABCgQJBAAAAA==.Maldive:BAABNQAECn8YAAQEAAgKAhHwDQBzAQAEAAYKMQ/wDQBzAQADAAYKMw37ugBSAQAFAAMKnwujTQCVAAAAAA==.Maligasia:BAAANQADCgIIAwAAAA==.Mallicia:BAABNQAECn8rAAIcAAkKXyHXDgBNAwAcAAkKXyHXDgBNAwAAAA==.Mallika:BAAANQAECgEIAQABNQAECgkJKwAcAF8hAA==.Mallistra:BAABNQAECn8cAAIRAAgK9hRNFwAEAgARAAgK9hRNFwAEAgABNQAECgkJKwAcAF8hAA==.Mallwizard:BAAANQAECgUJCgAAAA==.Mandible:BAAANQABCgIIAgAAAA==.Martris:BAAANQAECgQIBwAAAA==.Maryjane:BAAANQAECgMJAwAAAA==.Mashma:BAAANQADCggICAAAAA==.Massoflice:BAAANQAECgYIDwAAAA==.Mawkt:BAAANQADCggIAQAAAA==.Maxblaide:BAAANQADCggIGAAAAA==.Maxentia:BAAANQADCggICwAAAA==.',
Me='Melovania:BAAANQADCgIIAgAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIFwAVAHwaAA==.Milah:BAAANQABCgIIAgAAAA==.Missile:BAAANQAECgMIAwAAAA==.Misstangy:BAAANQADCgcIFwAAAA==.',
Mo='Moct:BAABNQAECn8dAAIOAAgKiyBbCgD0AgAOAAgKiyBbCgD0AgAAAA==.Monikal:BAAANQAECgIIAgAAAA==.',
Mu='Musashi:BAABNQAECn8vAAIZAAkKtCTGBAC/AwAZAAkKtCTGBAC/AwABNQAECgkJLwAZAO8mAA==.Muskeg:BAABNQAECn8gAAIYAAcKghI2VgCYAQAYAAcKghI2VgCYAQAAAA==.Mustardhunt:BAAANQADCgYICgAAAA==.',
['Mü']='Münchkiné:BAAANQABCggIFQAAAA==.',
Na='Namanari:BAAANQABCgIJAgAAAA==.Naris:BAAANQAECgYICgAAAA==.',
Ne='Necrochade:BAAANQAECgEIAQAAAA==.Neptune:BAABNQAECn8kAAICAAkKbBdbXQDFAgACAAkKbBdbXQDFAgAAAA==.',
Ni='Nightstew:BAAANQADCgcICgAAAA==.Nikra:BAAANQAECgQIBAAAAA==.Nishal:BAAANQADCggIGwAAAA==.',
Ny='Nyxaries:BAAANQAECgUIBwAAAA==.',
['Né']='Néwby:BAABNQAECn8jAAIjAAkKqR3XBwABAwAjAAkKqR3XBwABAwAAAA==.',
Op='Opalynn:BAAANQAECgEIAQAAAA==.Ophirra:BAAANQABCgYIDgAAAA==.',
Oz='Ozempic:BAAANQAECgQIBAABNQAFFAcIHQAUAAUgAA==.',
Pa='Pablo:BAABNQAECn8WAAIQAAkKthhWZABqAgAQAAkKthhWZABqAgAAAA==.Pannacea:BAAANQAECgQIBAABNQAECggIHAASACkcAA==.Patriot:BAAANQADCgYICQAAAA==.Pawinurbutt:BAAANQADCgQIBAAAAA==.',
Pe='Peppert:BAAANQAECgUICQAAAA==.',
Ph='Phane:BAAANQAECgQIBwAAAA==.',
Po='Pocketheals:BAAANQAECgMIAwAAAA==.Poon:BAAANQAECgQIBAAAAA==.',
Pu='Puffer:BAAANQAECgQICQAAAA==.',
Px='Pxry:BAAANQAECgQIBAAAAA==.',
Ra='Rabone:BAAANQADCgIJAgAAAA==.Raevyn:BAAANQADCgYIBgAAAA==.Raito:BAAANQAECgYIDAAAAA==.Rakshasa:BAABNQAECn8wAAMDAAkK4SH3DgBXAwADAAkK4SH3DgBXAwAFAAMK3w/tRgCqAAAAAA==.Rano:BAAANQAECgEIAQAAAA==.Rasetsungo:BAAANQAECgcIEQAAAA==.Raura:BAAANQADCggIHAAAAA==.Rayala:BAAANQAECggICQAAAA==.',
Re='Redblueblurr:BAAANQAECgUIDQAAAA==.Remi:BAAANQAECgYIEQAAAA==.Rev:BAAANQADCgUIBQAAAA==.Reveillark:BAAANQAECgIIAgAAAA==.Revelaiden:BAAANQABCgIIAgABNQAECgYIEQAWAAAAAA==.',
Ri='Rise:BAAANQAECgcIDQAAAA==.',
Ro='Rolan:BAABNQAECn8rAAQfAAgKqiW4FQDbAgAfAAcKOyW4FQDbAgAeAAgK2SN0HwDMAgAYAAQKtSO8WgCFAQAAAA==.Rosalian:BAAANQAECgYIEgAAAA==.Rotiko:BAAANQAECgYIEQAAAA==.Roweene:BAABNQAECn8fAAIkAAYKmQN9EgDbAAAkAAYKmQN9EgDbAAAAAA==.',
['Rá']='Rágnar:BAABNQAECn8cAAIQAAcKDxCduwCfAQAQAAcKDxCduwCfAQAAAA==.',
Sa='Sabiel:BAAANQAECgQIDwAAAA==.Sakuta:BAAANQADCgYIBgABNQAECgkJIQASAOcdAA==.',
Se='Serenatee:BAABNQAECn8eAAIgAAcKUQvgMgCIAQAgAAcKUQvgMgCIAQAAAA==.',
Sh='Shaedai:BAAANQAECgcIDgAAAA==.Shagohod:BAAANQADCgQIBAAAAA==.Shakked:BAAANQAECgEIAwAAAA==.Shinanigans:BAAANQADCggICAAAAA==.',
Sk='Skotojar:BAAANQADCgUIBQAAAA==.',
Sn='Snortedgfuel:BAAANQAECgcIEgAAAA==.',
So='Sokroar:BAAANQAECgIIAQABNQAFFAUIAQAWAAAAAA==.Solphera:BAAANQADCgQIDAAAAA==.Sonknight:BAAANQAECgQIBAAAAA==.',
Sp='Speedshot:BAAANQADCgUIBgAAAA==.Spitefulcrow:BAABNQAECn8ZAAIlAAgKaAlwCADJAQAlAAgKaAlwCADJAQAAAA==.',
St='Stardstr:BAAANQADCgMIAwAAAA==.Stealinsoulz:BAAANQADCgQIBAABNQADCgQIBAAWAAAAAA==.Stealsoul:BAAANQADCgIIAgABNQADCgQIBAAWAAAAAA==.Sto:BAAANQAECgEIAgAAAA==.Stratof:BAAANQADCgcIBwAAAA==.',
Su='Sufferding:BAABNQAECn8VAAIbAAcKzAzkSQB4AQAbAAcKzAzkSQB4AQAAAA==.Suria:BAABNQAECn8eAAIXAAgKwB5YFACjAgAXAAgKwB5YFACjAgAAAA==.',
Sw='Swytchblade:BAAANQADCggIAQAAAA==.',
Sy='Syker:BAAANQADCgIIAgAAAA==.',
Ta='Tahrovin:BAAANQAECgYICgAAAA==.Taytorchips:BAABNQAECn8bAAMQAAgKfAVQ5gBIAQAQAAgKfAVQ5gBIAQANAAMKNwHNDQFVAAAAAA==.',
Th='Thaendrin:BAAANQADCgYICQAAAA==.Thearcane:BAAANQADCgQIBwAAAA==.Thedoc:BAAANQAECgUICQAAAA==.Theefjeef:BAAANQAECgQIBQABNQAECggIDQAWAAAAAA==.Thorloim:BAABNQAECn8eAAISAAYKnSAOWgD+AQASAAYKnSAOWgD+AQAAAA==.Thornx:BAAANQADCgEIAQAAAA==.Throwaway:BAAANQAECgcICAAAAA==.Thundercups:BAABNQAECn8YAAIPAAgKNRLCFAAYAgAPAAgKNRLCFAAYAgAAAA==.',
Ti='Tigerstarr:BAABNQAECn8ZAAMfAAkKRRGpNgD4AQAfAAkKRRGpNgD4AQAeAAQKngkZogCzAAAAAA==.Tinyshieva:BAAANQADCgQIBAAAAA==.Tizuki:BAAANQAECgQIBAAAAA==.',
To='Tonystandard:BAAANQAECgUICQABNQAECgkJNgARAA4iAA==.',
Tr='Treborlock:BAABNQAECn8ZAAMFAAcKSg2MGACmAQAFAAcKSg2MGACmAQADAAEKmQKPUgEhAAAAAA==.Triplock:BAAANQAECgEJAQAAAA==.Trolcain:BAABNQAECn8fAAIeAAkKgRtOHQDaAgAeAAkKgRtOHQDaAgAAAA==.',
Tw='Twistedspork:BAAANQADCggIGgAAAA==.',
Un='Unbuffed:BAAANQADCgIIAgABNQAECgcIHAANACITAA==.',
Va='Vaedar:BAAANQAECgEIAQAAAA==.Vagglord:BAAANQAECgQIDwAAAA==.Valha:BAABNQAECn8eAAIbAAgKgA5dPQDJAQAbAAgKgA5dPQDJAQAAAA==.Vardisk:BAAANQADCgQIBAAAAA==.Varlashard:BAAANQADCggIDwAAAA==.Varteras:BAABNQAECn8iAAMEAAgKAhIeBwAuAgAEAAgKAhIeBwAuAgADAAUKXAa07gDnAAAAAA==.',
Ve='Vellron:BAAANQAECgYIEgAAAA==.Veroque:BAAANQADCgUIBQAAAA==.',
['Và']='Vàsh:BAAANQAECgUIBQAAAA==.',
['Vø']='Vødøu:BAAANQAECgYIEAAAAA==.',
Wa='Wafflelegend:BAABNQAECn8mAAIbAAgKFiV/CgBaAwAbAAgKFiV/CgBaAwAAAA==.Wardkbriggle:BAABNQAECn8XAAMfAAkKbBrDNAADAgAfAAkKExfDNAADAgAeAAgKsRhgVQC5AQAAAA==.Warint:BAAANQAECgUICwAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Welish:BAAANQABCgEIAQAAAA==.',
Wi='Wifi:BAABNQAECn8ZAAIQAAcK0h0vWgCFAgAQAAcK0h0vWgCFAgAAAA==.',
Wo='Wolfdude:BAAANQAECggICQAAAA==.',
Wy='Wydge:BAABNQAECn8eAAICAAYKWhDVCQF5AQACAAYKWhDVCQF5AQAAAA==.Wyven:BAABNQAECn8kAAIeAAkK6yKrDwA4AwAeAAkK6yKrDwA4AwABNQADCgcICgAWAAAAAA==.',
Xa='Xanddoria:BAABNQAECn8ZAAMHAAcKtCJ8HQCPAgAHAAcKtCJ8HQCPAgAIAAMKCBjzNwDyAAAAAA==.Xaoc:BAAANQAECgYIDwAAAA==.',
Xh='Xhared:BAABNQAECn8iAAIYAAYK9h95OgAZAgAYAAYK9h95OgAZAgAAAA==.',
Xo='Xochital:BAAANQADCgEIAQAAAA==.',
Yu='Yunah:BAAANQADCgYIBgAAAA==.',
Ze='Zephy:BAAANQAECgQIDwAAAA==.',
['Åe']='Åeon:BAAANQAECgQICQAAAA==.',
['Ðr']='Ðráco:BAAANQAECgQIBAAAAA==.',
['ßu']='ßullzeye:BAAANQADCgcIBwAAAA==.',
['Ÿu']='Ÿunalessca:BAAANQAECgYICwAAAA==.',
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
