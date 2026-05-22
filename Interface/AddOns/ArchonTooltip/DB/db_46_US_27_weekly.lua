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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Priest-Holy','Hunter-Marksmanship','Paladin-Protection','Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Druid-Balance','Warlock-Destruction','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Priest-Discipline','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Fury','Druid-Feral','Druid-Restoration','Druid-Guardian','Warrior-Arms','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaravos:BAAALgAECgcJEgAAAA==.',
Ab='Abysseon:BAAALgAECgQJCgAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIBAAcJWAWSZQA3AQABAAcJWAWSZQA3AQAAAA==.Adura:BAAALgADCgcJDwAAAA==.',
Ae='Aeirith:BAABLgAECn8jAAMCAAkJjB3lAACYAgACAAkJjB3lAACYAgADAAEJRQofGAE1AAAAAA==.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgYJDgAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Aldyah:BAAALgAECgUJBQAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJEAAAAA==.Alvist:BAAALgAECgQJDAAAAA==.',
Am='Amarasu:BAABLgAECn8YAAIEAAgJbQ99GgB/AQAEAAgJbQ99GgB/AQAAAA==.Amarlly:BAABLgAECn8eAAIFAAcJMRWLCgBRAQAFAAcJMRWLCgBRAQAAAA==.Amenedil:BAAALgAECgMJBwAAAA==.',
An='Anbrew:BAAALgAECgQJBwABLgAFFAUJDQAGAAQfAA==.Ancelina:BAABLgAECn8WAAIHAAYJ8CKLEwDjAQAHAAYJ8CKLEwDjAQAAAA==.Anderton:BAABLgAECn8hAAIIAAcJwhkmQQC6AQAIAAcJwhkmQQC6AQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAAALgAECgMJBgAAAA==.Annovera:BAAALgAECgMJAwAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.Anyi:BAAALgAECgEJAQAAAA==.',
Ap='Apexxd:BAAALgADCgEJAQAAAA==.Applefritter:BAAALgAECgQJBAABLgAECggJIwAJAE8UAA==.',
Ar='Archérhiro:BAACLgAFFH8XAAMBAAYJ9ReMEABnAQABAAUJsRyMEABnAQAKAAMJRwTfIQCHAAAuAAQKfygAAwEACQnrHigMAK4CAAEACQndHigMAK4CAAoACAkrGdobAEoCAAAA.Arilias:BAAALgAECgEJAQABLgAECggJIwABAAgTAA==.Arillann:BAABLgAECn81AAILAAkJpR74AgCmAgALAAkJpR74AgCmAgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arte:BAABLgAECn81AAIBAAkJbBO2KwDdAQABAAkJbBO2KwDdAQAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQAMAAAAAA==.Arvena:BAABLgAECn8nAAINAAkJVgpRVQA1AQANAAkJVgpRVQA1AQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQAMAAAAAA==.Asheron:BAAALgAECgYJBwAAAA==.Ashymage:BAACLgAFFH8JAAIDAAQJYBatMgBSAQADAAQJYBatMgBSAQAuAAQKfzIAAgMACQlYHEYgAGECAAMACQlYHEYgAGECAAAA.Askevar:BAABLgAECn8WAAMOAAYJtAtHJwAEAQAOAAYJ5wlHJwAEAQAGAAYJEgiXnQDkAAAAAA==.Aspect:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAABLgAECn8WAAIIAAgJMQXgowDkAAAIAAgJMQXgowDkAAAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Av='Avinthoro:BAAALgADCgIJAgAAAA==.',
Ay='Ayyayyron:BAAALgAECgIJAgAAAA==.',
Az='Azaleah:BAABLgAECn8rAAIIAAkJuhOjNADmAQAIAAkJuhOjNADmAQAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8hAAINAAgJORItPgCCAQANAAgJORItPgCCAQAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgADCgEJAQABLgAECgQJCAAMAAAAAA==.Banjoman:BAABLgAECn8jAAIJAAcJXCQzBgDRAgAJAAcJXCQzBgDRAgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIPAAYJ5A34NgD/AAAPAAYJ5A34NgD/AAAAAA==.',
Be='Beary:BAAALgAECgEJAwAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgEJAQAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigjuicy:BAAALgAECgcJCAAAAA==.Billie:BAAALgADCgcJBwAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Blackadder:BAAALgAECgMJBgAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn80AAIQAAkJaxvACQBfAgAQAAkJaxvACQBfAgAAAA==.Bluestreak:BAAALgAECgEJAwABLgAECgcJCAAMAAAAAA==.',
Bo='Bode:BAAALgAECgYJEgAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boogy:BAAALgAECgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJDAAMAAAAAA==.Borledish:BAAALgAECgMJBAABLgAECgQJDAAMAAAAAA==.Bottosai:BAAALgAECgEJAQAAAA==.',
Br='Branwynn:BAAALgAECgEJBAAAAA==.Breezyfight:BAAALgADCgMJAwAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAAALgAFFAMJAwAAAA==.Brewdaddy:BAAALgAECgUJCAABLgAECggJJQARADoNAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgADCgkJCQAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgADCggJCQAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBAAAAA==.Butterknifeo:BAABLgAFFH8FAAISAAMJxxREHQDgAAASAAMJxxREHQDgAAAAAA==.',
By='Byryja:BAAALgAECgMJBgAAAA==.',
Ca='Cahrazie:BAAALgAECgcJCAAAAA==.Caidinn:BAAALgAECgkJEQAAAA==.Caitrîn:BAAALgADCgkJCQAAAA==.Calissancia:BAABLgAECn8mAAIPAAgJhxQYGgDNAQAPAAgJhxQYGgDNAQAAAA==.Calkey:BAABLgAECn8WAAITAAYJUQjIFADFAAATAAYJUQjIFADFAAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Channingtotm:BAACLgAFFH8TAAIUAAQJyx/hDwB0AQAUAAQJyx/hDwB0AQAuAAQKfywAAhQACAn4IC4HAPQCABQACAn4IC4HAPQCAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwAMAAAAAA==.Cheekymonkey:BAABLgAECn8ZAAICAAYJtArnBgAAAQACAAYJtArnBgAAAQAAAA==.Chueyé:BAAALgADCgYJBwABLgAFFAMJCQAVAO8dAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8jAAMJAAgJTxRkGwCjAQAJAAcJTRVkGwCjAQAHAAcJpxnRGgCbAQAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQAMAAAAAA==.',
Cl='Closetcookie:BAAALgAECgQJBAAAAA==.',
Co='Cordialkylie:BAAALgADCgMJBAAAAA==.',
Cr='Crazyugly:BAAALgAECgEJAQAAAA==.Crogrer:BAAALgADCgUJBQAAAA==.Crosslock:BAAALgAECgEJAQAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgMJBAAAAA==.',
Da='Dalaris:BAABLgAECn8WAAIWAAYJsRRLHQAoAQAWAAYJsRRLHQAoAQAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgMJBAAAAA==.Darkeon:BAAALgAECgQJBAAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAQABLgAECgEJAQAMAAAAAA==.Darrosh:BAABLgAECn8bAAQXAAgJuxOjDADmAAAXAAYJDhCjDADmAAAVAAcJjQ1WLADZAAAYAAMJ9hB8FAC1AAAAAA==.Dartian:BAAALgADCgYJBgABLgAECggJIwABAAgTAA==.Dazdot:BAAALgADCgQJBAAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgADCgMJAwAAAA==.Deathmommy:BAAALgAECgEJAQAAAA==.Deathty:BAAALgAECgMJCgABLgAECgYJDQAMAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8jAAIZAAcJ6RgdPgCkAQAZAAcJ6RgdPgCkAQAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgADCgkJIAAAAA==.',
Di='Diltlish:BAAALgAECgMJBQAAAA==.Disconcern:BAAALgADCgcJBwAAAA==.Discontent:BAAALgAFFAIJAgAAAA==.Discordiä:BAABLgAECn8XAAIaAAgJHRedEgD3AQAaAAgJHRedEgD3AQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgIJBAAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJDAAMAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAIUAAQJkhbeHgARAQAUAAQJkhbeHgARAQAAAA==.',
Dr='Dracones:BAAALgAECgYJCQAAAA==.Dragondz:BAAALgAECgUJBQAAAA==.Dragonflai:BAABLgAECn8kAAIDAAgJPheNUACoAQADAAgJPheNUACoAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgADCgcJBwAAAA==.Drakkei:BAABLgAECn8lAAMBAAcJ7RFLTQBgAQABAAcJ7RFLTQBgAQAEAAIJwgJYQQBTAAAAAA==.Drerane:BAAALgADCgYJBgAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgADCgcJFAAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn81AAIbAAkJ+SJNAwDvAgAbAAkJ+SJNAwDvAgAAAA==.Drylo:BAEBLgAECn8tAAMcAAkJJSBHBgDAAgAcAAkJih5HBgDAAgAdAAgJxB+8AgBIAgAAAA==.',
Du='Dunstir:BAABLgAECn8ZAAIIAAgJ6AVqhQAZAQAIAAgJ6AVqhQAZAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8ZAAQcAAgJUhX5OwDlAAAdAAUJUBJRIgAYAQAcAAYJqhD5OwDlAAAeAAQJNwdIQwBTAAAAAA==.',
Ed='Edelweíss:BAAALgAECgEJAQAAAA==.',
El='Elarol:BAAALgAECgEJAgAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIfAAYJGxPrPQD8AAAfAAYJGxPrPQD8AAAAAA==.Emeralde:BAAALgAECgUJBgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyhands:BAAALgAECgQJBAAAAA==.Emptyheals:BAABLgAECn8pAAIaAAkJ1h3EBQDhAgAaAAkJ1h3EBQDhAgAAAA==.',
Er='Ereada:BAAALgADCgUJCgAAAA==.Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8eAAISAAgJPRCQOgDOAAASAAgJPRCQOgDOAAAAAA==.',
Et='Ethellin:BAABLgAECn8cAAIIAAYJzgSRtQDIAAAIAAYJzgSRtQDIAAAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgYJCQAAAA==.',
Fe='Feildmedic:BAAALgADCgUJBQAAAA==.Fellslasher:BAAALgAECgIJAgAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgAMAAAAAA==.Felwinter:BAABLgAECn8uAAIZAAkJ5BlXGwBEAgAZAAkJ5BlXGwBEAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgMJAwAAAA==.Fistsalot:BAAALgAECgQJBAAAAA==.',
Fl='Fluxarata:BAABLgAECn8ZAAINAAgJKAxwVwAvAQANAAgJKAxwVwAvAQAAAA==.',
Fr='Fred:BAABLgAECn8bAAIfAAYJHQiKRADfAAAfAAYJHQiKRADfAAAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgcJDQAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAABLgAECn8WAAIDAAYJTwsWmQANAQADAAYJTwsWmQANAQAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8kAAIgAAgJ6Rr/BgAPAgAgAAgJ6Rr/BgAPAgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAAALgAECgUJDAAAAA==.Galand:BAABLgAECn8fAAMGAAYJ+h6ETgCQAQAGAAYJdB6ETgCQAQAOAAIJoiHKOQBZAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAFFAEJAQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAFFAEJAQAMAAAAAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgIJAgAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8YAAIKAAcJxg6+DwAWAQAKAAcJxg6+DwAWAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halleyscomet:BAABLgAECn8WAAIIAAcJPBptRAAXAgAIAAcJPBptRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECgcJCQAAAA==.Hawkwave:BAAALgAECgcJDwABLgAECgkJEQAMAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Hefty:BAAALgAECgIJAgAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAACLgAFFH8MAAIbAAQJ7hNeFwAhAQAbAAQJ7hNeFwAhAQAuAAQKfxUAAxsACAleGEkdAH4BABAABgmOG30jALoBABsACAkXEkkdAH4BAAAA.Hellbine:BAAALgADCgMJAgAAAA==.Hellsspawn:BAAALgADCgEJAQAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAAMAAAAAA==.',
Ho='Hoardwither:BAAALgADCgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8JAAIVAAMJ7x1iFAAjAQAVAAMJ7x1iFAAjAQAuAAQKfzQABBUACQkpIgMHAHMCABUACQkpIgMHAHMCABgAAgkCGnMUAJQAABcAAQkZAs4cAAkAAAAA.Homealone:BAAALgAECgUJEAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAECgEJAwAAAA==.Huntinfuzzy:BAAALgAECggJDgAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAABLgAECn8eAAMhAAkJfx4CEAC4AgAhAAkJfx4CEAC4AgAgAAEJbQkWNAAwAAAAAA==.',
Il='Illariana:BAAALgAECgYJEgAAAA==.Illirotica:BAAALgAECgcJCAAAAA==.',
In='Insanitty:BAAALgAECgcJDwAAAA==.Invincible:BAAALgAECgEJAQABLgAECgMJBQAMAAAAAA==.',
Ir='Ironlobo:BAAALgAECgQJBQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAAALgAECgUJEAAAAA==.',
It='Itherious:BAAALgAECgEJAQAAAA==.',
Ja='Jacham:BAAALgAECgcJEQAAAA==.Jackyll:BAAALgAECgQJCAAAAA==.Jagerboy:BAAALgAECgYJBgAAAA==.Jango:BAAALgAECgIJAgABLgAFFAEJAQAMAAAAAA==.Jatix:BAABLgAECn8oAAIIAAgJ9CKnEQCfAgAIAAgJ9CKnEQCfAgAAAA==.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgMJBQAMAAAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgMJBQAAAA==.Jellyspinoff:BAAALgAECgMJBQAAAA==.Jellytown:BAABLgAECn81AAIDAAkJ6hOYNwD5AQADAAkJ6hOYNwD5AQAAAA==.Jelorinea:BAAALgAECgMJAwAAAA==.Jessiana:BAAALgAECgMJAwAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgMJBAAAAA==.',
Ju='Jumano:BAAALgAECgMJAwAAAA==.Jundra:BAAALgAECgEJAgAAAA==.',
Ka='Kaineh:BAABLgAECn8bAAIKAAYJ/BjzDABFAQAKAAYJ/BjzDABFAQAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn82AAIBAAkJ2x96CgDBAgABAAkJ2x96CgDBAgAAAA==.Kaladil:BAAALgAECgcJBwAAAA==.Kamis:BAAALgADCgQJBAAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMNAAgJzxv/LwA8AgANAAgJzxv/LwA8AgAWAAEJAQdWeQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgAECgMJAwAAAA==.Kasmus:BAAALgAECgQJBAAAAA==.Kawdor:BAABLgAECn8lAAQRAAgJOg3AMQA+AQARAAcJgQ3AMQA+AQALAAYJ3A9mGwDlAAAIAAMJHgoW9QBmAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMWAAQJNxZQDAD4AAAWAAMJkRlQDAD4AAANAAEJKgwSawBJAAAuAAQKfxYAAxYACAmlHD0NAO8BAA0ACAk1F1w+APsBABYABwlPHT0NAO8BAAAA.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgADCgQJBQAAAA==.Kirtthehurt:BAABLgAECn8hAAIDAAgJ2RQdTQCxAQADAAgJ2RQdTQCxAQAAAA==.',
Ko='Koldfront:BAAALgADCgMJBQAAAA==.Kollinator:BAAALgADCgYJBwAAAA==.Korso:BAAALgADCgUJCwABLgADCgkJCQAMAAAAAA==.Kotal:BAAALgAECgEJAQAAAA==.',
Ky='Kylair:BAABLgAECn8sAAIHAAkJaB5YBgCtAgAHAAkJaB5YBgCtAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgMJAwAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAECgYJDQAAAA==.Laftydh:BAAALgAECgUJDgABLgAECgYJDQAMAAAAAA==.Lailah:BAAALgADCgIJAgABLgAECgkJKwAIALoTAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgYJCwAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8aAAIVAAYJ+glkJgAEAQAVAAYJ+glkJgAEAQAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJBQABLgAECggJIwAJAE8UAA==.Lieree:BAAALgAECgcJDgAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJCAAAAA==.Lilyfaye:BAAALgADCgcJBwAAAA==.Limosfire:BAAALgAECgQJCwAAAA==.Linsatha:BAAALgAECgMJAwAAAA==.',
Lo='Lockty:BAAALgAECgIJAwABLgAECgYJDQAMAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgUJBgAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lunà:BAAALgAECgUJDAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8kAAIIAAgJfxB/ZQBZAQAIAAgJfxB/ZQBZAQAAAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJCQAVAO8dAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgAECgQJCgABLgAFFAEJAQAMAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Malachi:BAAALgADCgkJCQAAAA==.Manavoid:BAABLgAECn8cAAINAAYJkAoafQDRAAANAAYJkAoafQDRAAAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8bAAIPAAYJTxdIKABbAQAPAAYJTxdIKABbAQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meri:BAABLgAECn8bAAIhAAcJoB4rJgAfAgAhAAcJoB4rJgAfAgAAAA==.',
Mi='Miande:BAAALgAECgUJBQAAAA==.Microburst:BAAALgADCgUJBQAAAA==.Minilock:BAABLgAECn8bAAMTAAYJEg4qFQDCAAAZAAYJ8Qp1iQDpAAATAAUJTg4qFQDCAAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missleading:BAAALgAECgEJAQAAAA==.Missused:BAAALgAECgQJBgAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgAECgEJAQAAAA==.',
Mo='Mongermook:BAABLgAECn8bAAMiAAgJCgq3JACnAAAiAAgJCgq3JACnAAASAAEJxgFpkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQAMAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgMJAwAAAA==.Moonbloom:BAABLgAECn8bAAIhAAgJQxvbGAA3AgAhAAgJQxvbGAA3AgAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn8fAAIjAAgJrgaSIAD8AAAjAAgJrgaSIAD8AAAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQAAAA==.Mull:BAAALgAECgUJDAAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgAECgUJBQAAAA==.',
Na='Naatixa:BAAALgADCgYJCwAAAA==.Nacronor:BAAALgAECgEJAQAAAA==.Naiika:BAAALgAECgIJAgAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgUJCAABLgAECgYJEwAMAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgEJAQAAAA==.Neeve:BAAALgADCgYJBgAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgMJAwAMAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgAECgYJCwAAAA==.Nickatnite:BAAALgAECgEJAgAAAA==.Nickelodeon:BAAALgAECgQJBwAAAA==.Nicksaban:BAABLgAECn8fAAIIAAgJnBpHLQADAgAIAAgJnBpHLQADAgAAAA==.Nightgear:BAACLgAFFH8rAAMBAAYJoRcgBABeAQABAAUJyxogBABeAQAKAAIJ/ArQHgBTAAAuAAQKf1kAAwEACQm0IlIGAPcCAAEACQm0IlIGAPcCAAoABAnfEpUZAKUAAAAA.Nilux:BAAALgAECgYJDgAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgADCggJEwAAAA==.Nixeava:BAAALgAECgEJAgAAAA==.',
No='Nogooddruid:BAAALgAECgEJAQAAAA==.Nopetsneeded:BAABLgAECn8sAAIKAAgJKhL4CQCEAQAKAAgJKhL4CQCEAQAAAA==.Nostariel:BAAALgADCgEJAQAAAA==.Notadoctor:BAAALgAECgQJBAAAAA==.Noteworthy:BAAALgAECgYJEAABLgAFFAUJDQAGAAQfAA==.',
Ny='Nysong:BAABLgAECn8jAAMTAAgJ0QYuEADxAAATAAgJ0QYuEADxAAAZAAMJYwIC1wBYAAAAAA==.',
Od='Oddangel:BAAALgAECgYJEwAAAA==.Odex:BAABLgAECn8XAAIdAAcJBwk8CwAfAQAdAAcJBwk8CwAfAQAAAA==.',
Oh='Ohblergen:BAAALgAECgEJAQAAAA==.',
Ok='Okragren:BAABLgAECn8sAAIkAAkJswgZKgBIAQAkAAkJswgZKgBIAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.',
On='Onos:BAABLgAECn8bAAIBAAcJIyQ4IABEAgABAAcJIyQ4IABEAgAAAA==.Ontoquas:BAAALgADCgEJAQAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgEJAQAAAA==.Pathogen:BAABLgAECn8hAAIGAAkJDR9sJQAnAgAGAAkJDR9sJQAnAgAAAA==.',
Pe='Penryn:BAAALgAECgEJAQAAAA==.Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgADCgQJBAAAAA==.',
Pl='Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgUJDAAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgABLgAECgEJAQAMAAAAAA==.',
Qu='Queedle:BAAALgAECgYJEwAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Rahanumn:BAAALgAECgYJDQAAAA==.Rainsvoker:BAACLgAFFH8jAAIeAAYJXQ39CQCbAQAeAAYJXQ39CQCbAQAuAAQKf1IAAx4ACQkQHHEEAKECAB4ACQkQHHEEAKECABwABgk7CCpDAMgAAAAA.Ramike:BAAALgAECggJCQAAAA==.Raqtar:BAAALgADCgMJAwABLgAECgkJEQAMAAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8lAAIIAAgJlgzhZgBWAQAIAAgJlgzhZgBWAQAAAA==.Renata:BAAALgAECgYJBgAAAA==.Replicant:BAAALgAECgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reverìe:BAAALgAECgcJBwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reï:BAAALgAECgYJEgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Ritzon:BAABLgAECn81AAMfAAkJ0iPVAgARAwAfAAkJ0iPVAgARAwAjAAEJmBcvSQA/AAAAAA==.',
Ro='Roxydan:BAABLgAECn8dAAMTAAgJhg03KQAdAQAZAAgJhg1KZwCWAQATAAYJ8Ag3KQAdAQAAAA==.',
Ry='Ryko:BAABLgAECn8ZAAIlAAcJIRLFDwC8AQAlAAcJIRLFDwC8AQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJDQAAAA==.Sankai:BAAALgAECgEJAQABLgAECgYJDgAMAAAAAA==.Sarumanpally:BAAALgAECgYJBwAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgIJAwAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAFFAEJAQAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgIJBAAAAA==.Shmooves:BAEALgAECgMJAwAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgAECgEJAQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgQJBAAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAABLgAECn8YAAITAAYJLw/0DwD0AAATAAYJLw/0DwD0AAAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwAMAAAAAA==.Snoopingas:BAAALgADCgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgAECgEJAQAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIkAAYJCAxiTAAWAQAkAAYJCAxiTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIkAAgJERDXMwCJAQAkAAgJERDXMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAAALgAECgcJEwAAAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJEQAMAAAAAA==.',
Su='Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgYJDQAAAA==.Sune:BAABLgAECn8XAAIHAAYJ8AoSNQDuAAAHAAYJ8AoSNQDuAAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Sydneyweenie:BAAALgADCgcJBwAAAA==.Syldi:BAAALgAECgEJAQAAAA==.Sythis:BAAALgAECgEJAQAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAAALgAECgMJBgAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgADCgcJCwAAAA==.Tanlon:BAAALgAECgEJAQAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8nAAIhAAkJkQ8AMACZAQAhAAkJkQ8AMACZAQAAAA==.Telphin:BAAALgAECgYJCAAAAA==.Tempestira:BAAALgADCgIJCAAAAA==.Tensuken:BAABLgAECn8ZAAIIAAYJpBgFdQA4AQAIAAYJpBgFdQA4AQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJCAAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAAALgAECgYJDQAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwAMAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgMJAwAAAA==.Thrazzoro:BAAALgAECgYJEwAAAA==.',
Ti='Tiarl:BAABLgAECn8lAAIJAAgJXRasFADlAQAJAAgJXRasFADlAQAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8XAAMdAAYJRCD5DgDrAQAdAAYJRCD5DgDrAQAcAAEJUhc0aABBAAAAAA==.Tinysitril:BAAALgADCgYJBQABLgAECgYJFgAWALEUAA==.Titañick:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgYJEAAAAA==.Toosxyfohair:BAAALgAECgMJBAAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trolltoll:BAAALgADCgEJAgAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Ty='Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgADCgYJCgAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIgAAUJzh31EACdAQAgAAUJzh31EACdAQAAAA==.',
Un='Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgAIAJoSAA==.',
Va='Valakk:BAAALgAECgIJBAAAAA==.Vallak:BAAALgADCgIJAwAAAA==.Valsitril:BAAALgAECgYJCQABLgAECgYJFgAWALEUAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgAECgEJAQAAAA==.Varadun:BAAALgAECgEJAQAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCAAAAA==.Velsetin:BAABLgAECn8dAAIDAAcJTBsyTABSAgADAAcJTBsyTABSAgABLgAFFAMJBQASAMcUAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAAMAAAAAA==.Veryspooky:BAABLgAECn8XAAIZAAgJMBenMwDKAQAZAAgJMBenMwDKAQAAAA==.Vexian:BAAALgADCgcJFgAAAA==.',
Vi='Vicas:BAAALgAECgUJCQAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJEAAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgAECgEJAQAAAA==.',
Wh='Whisperlia:BAAALgADCgEJAQAAAA==.Whitetoothe:BAABLgAECn8VAAIBAAYJRxK7YwAhAQABAAYJRxK7YwAhAQAAAA==.',
Wi='Wistmeaver:BAAALgAECgMJBQAAAA==.Witherbear:BAAALgADCgcJBwAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgYJBgAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJBwAAAA==.',
Xo='Xotiko:BAAALgAECgYJBgAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
Ya='Yaerin:BAACLgAFFH8JAAIaAAMJRiCMFwAmAQAaAAMJRiCMFwAmAQAuAAQKfyIAAhoACQnsIK8CAE4DABoACQnsIK8CAE4DAAAA.',
Yu='Yunarä:BAAALgAECgYJBwAAAA==.Yuukon:BAAALgAECgYJEQAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8cAAINAAcJdxh6RwDWAQANAAcJdxh6RwDWAQAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgAECgEJAQAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.',
Zi='Zilphia:BAAALgAECgcJEAAAAA==.',
Zu='Zuriel:BAAALgAECgEJAQAAAA==.',
Zy='Zyku:BAAALgADCgIJAgAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAECgQJBQABLgAECgYJLAALANciAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgADCgMJBwAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAIBAAYJ1BIybgAIAQABAAYJ1BIybgAIAQAAAA==.',
['Ös']='Östara:BAAALgAECgYJEAAAAA==.',
['ßj']='ßjörn:BAAALgADCgQJBAAAAA==.',
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
