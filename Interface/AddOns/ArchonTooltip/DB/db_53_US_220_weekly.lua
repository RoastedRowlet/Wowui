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

local lookup = {'Rogue-Assassination','Rogue-Outlaw','Rogue-Subtlety','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Balance','Mage-Frost','Mage-Arcane','Warrior-Protection','Priest-Holy','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Fury','Evoker-Preservation','Hunter-BeastMastery','Hunter-Survival','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','DeathKnight-Blood','Warrior-Arms','DemonHunter-Devourer','Druid-Feral','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Holy','Priest-Discipline','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Druid-Guardian','Druid-Restoration',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaragon:BAABNQAECn8WAAQBAAkKJxIyFAAkAQABAAkKJxIyFAAkAQACAAQK9A8iEgDnAAADAAEKhxGbSQBEAAABNQAFFAoKJAAEANIgAA==.',
Ab='Abysmal:BAABNQAECn8aAAMFAAYKHBK8kABeAQAFAAYKHBK8kABeAQAGAAEKAAAYSAEqAAAAAA==.',
Ad='Adame:BAAANQAECgEIAQAAAA==.Adjudicator:BAAANQAECgQIBAABNQAECgQIBQAHAAAAAA==.',
Ae='Aeriona:BAABNQAECn8vAAIIAAkKTBwaGQC+AQAIAAkKTBwaGQC+AQAAAA==.Aerobear:BAAANQADCgYIBgABNQAFFAQIBgAJAEUFAA==.Aerolock:BAAANQAECgUICwABNQAFFAQIBgAJAEUFAA==.Aerosong:BAACNQAFFH8GAAMJAAQKRQVcFACvAAAJAAMKRQVcFACvAAAKAAEKAACcBAAAAAA1AAQKfyAAAgkACgooEhExACACAAkACgooEhExACACAAAA.',
Af='Affalon:BAAANQAECgQICAAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Aine:BAAANQAECggIEwAAAA==.Ainkor:BAAANQAECgYICwABNQAFFAEIAQAHAAAAAA==.',
Ak='Akyospirit:BAABNQAECn81AAIFAAoK0w0OFgClAQAFAAoK0w0OFgClAQAAAA==.',
Al='Alchemised:BAAANQAECggIEAABNQAECgoKHQALAJscAA==.Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAABNQAECn8jAAIMAAYKZgp+LACwAAAMAAYKZgp+LACwAAAAAA==.Allumin:BAAANQADCggIFAAAAA==.Alpha:BAABNQAECn8wAAMNAAkKWhaaCABVAgANAAgKQBiaCABVAgAOAAkK2RMAHQCcAQAAAA==.',
Am='Amamonk:BAABNQAECn8WAAIEAAgK/RU0IgAYAgAEAAgK/RU0IgAYAgAAAA==.Amathore:BAAANQADCgcIBwAAAA==.Ammert:BAAANQAECgQIBAAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAcIGAAPADMWAA==.Angliko:BAAANQADCgMJAwABNQAECgoKLwAKAHYZAA==.Annei:BAABNQAECn8wAAMQAAkKCyF6EgA2AwAQAAgKIiN6EgA2AwARAAYKoBJyOwBOAQABNQAFFAIIAwAHAAAAAA==.Anomandaris:BAABNQAECn8aAAMGAAcKUA4ujACGAQAGAAcKUA4ujACGAQAFAAQKTAgkbAB5AAAAAA==.Anquan:BAABNQAECn8WAAMSAAYKbxFfIQAeAQASAAYKngtfIQAeAQATAAQKgxO8jgDrAAAAAA==.Anya:BAABNQAECn8iAAIDAAoKXhM0BAAKAgADAAoKXhM0BAAKAgAAAA==.',
Ap='Apedemak:BAAANQAECgQIBgAAAA==.Apothica:BAABNQAECn8lAAIOAAkKKAvVJQB/AQAOAAkKKAvVJQB/AQAAAA==.Apothicc:BAAANQAECgUICgABNQAECgkJJQAOACgLAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUJDAAAAA==.',
Aq='Aquae:BAAANQAECgYICAABNQAECggIGQAUAIQaAA==.',
Ar='Arcohunt:BAAANQADCgcJBwABNQAECgUJDAAHAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAABNQAECn8VAAIIAAkKbhdlhgAaAgAIAAkKbhdlhgAaAgAAAA==.Argonaut:BAAANQADCggIEAAAAA==.Artarius:BAAANQABCgQIBQAAAA==.',
As='Asheritâ:BAAANQAECgUIDgAAAA==.Ashvalis:BAABNQAECn8eAAIVAAcKJCFaBQCIAQAVAAcKJCFaBQCIAQAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECggIDwAAAA==.Askr:BAAANQAECgUIDwAAAA==.Asphar:BAABNQAECn8bAAIWAAgKJCIPKAD4AgAWAAgKJCIPKAD4AgAAAA==.Astria:BAAANQADCgYICwAAAA==.Asynic:BAAANQADCgYIEAABNQAECgYIFQAXAEoXAA==.',
Au='Aung:BAABNQAECn89AAIJAAkKjiWRCQBmAwAJAAkKjiWRCQBmAwAAAA==.Auri:BAAANQAECgIIAgAAAA==.',
Av='Avitarkorra:BAAANQAECgUICAAAAA==.',
Ax='Axex:BAABNQAECn8VAAIIAAgK5QvAxwCMAQAIAAgK5QvAxwCMAQAAAA==.',
Az='Azamii:BAABNQAECn8nAAMFAAkK0xxkVwALAgAFAAgKnBtkVwALAgAGAAUKIh7qKQAVAQABNQAECgoKNQAQAFYfAA==.Azarion:BAABNQAECn8rAAMYAAoK3BOpDQDaAQAYAAkK5BKpDQDaAQAZAAUK5hLTJgBAAQAAAA==.Azill:BAACNQAFFH8RAAIEAAYKqhElAgA7AQAEAAYKqhElAgA7AQA1AAQKfyUAAgQACgrqG0oRANYCAAQACgrqG0oRANYCAAAA.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAwAAAA==.Azurefury:BAABNQAECn8iAAIaAAcKBwjWHQCEAQAaAAcKBwjWHQCEAQAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Bandi:BAABNQAECn8kAAIYAAkKNRTGGgCGAQAYAAkKNRTGGgCGAQAAAA==.Bartrak:BAAANQADCgIJAgABNQAECgQIBQAHAAAAAA==.Battôsai:BAAANQAECgQIDAAAAA==.',
Be='Bearfucius:BAABNQAECn8mAAMEAAgK0RZWJgDwAQAEAAcKhxdWJgDwAQALAAgKuwx/FgCTAAAAAA==.Bearrific:BAABNQAECn8cAAMDAAgK4w+fHwDrAAADAAgK4w+fHwDrAAABAAEKXwUDpwAuAAAAAA==.Beefypriest:BAAANQABCgEIAQAAAA==.Behomadra:BAAANQAECgYIBgAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAABNQAECn8fAAMbAAkKIyHfDwAuAwAbAAkKIyHfDwAuAwATAAEKzgHc/QAaAAAAAA==.Beyond:BAAANQAECgQIBQAAAA==.',
Bi='Billthekid:BAAANQADCgcIBwAAAA==.Binksy:BAACNQAFFH8IAAIcAAIKzxWoEgCIAAAcAAIKzxWoEgCIAAA1AAQKfzYAAhwACgpeHqo4AOICABwACgpeHqo4AOICAAAA.Biscuit:BAACNQAFFH8YAAMPAAcKMxZMAQDeAQAPAAYKhBtMAQDeAQAcAAEK7gA1PABJAAA1AAQKfzgAAw8ACgoZJRIBAMkDAA8ACgrdJBIBAMkDABwABQrFG7K6AIoBAAAA.',
Bl='Blaam:BAAANQAECgIIAwAAAA==.Blazin:BAACNQAFFH8UAAMOAAUK5xn3CgADAQAOAAUK5xn3CgADAQANAAEKnBCOEwBHAAA1AAQKfywAAw4ACgqrIEtGAPYCAA4ACgo/IEtGAPYCAA0ABQpqG6wTAG4BAAAA.Blinkzy:BAAANQADCgUICQABNQAFFAIICAAcAM8VAA==.Blitzoria:BAAANQADCgYIBgABNQAECgcIDgAHAAAAAA==.Bloui:BAAANQADCgYIFwAAAA==.Blueknight:BAABNQAECn8jAAMbAAcKlQY4NwCbAAAbAAcKlQY4NwCbAAATAAIKUAaJzQBSAAAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgUICQAAAA==.Bonythumper:BAAANQADCgQIBAAAAA==.Borlok:BAAANQAECgcIKAAAAQ==.',
Br='Brannigan:BAABNQAECn81AAIcAAoKsB7qDwDZAQAcAAoKsB7qDwDZAQAAAA==.Brannigandh:BAABNQAECn8hAAQKAAgKoRgHCwAjAgAKAAgKfBgHCwAjAgAdAAYKvQ1+QABIAQAJAAEKAAAojgA/AAABNQAECgoKNQAcALAeAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIDAAAAA==.Briantu:BAAANQADCggJCAAAAA==.Brickfelt:BAAANQABCgYIDAAAAA==.Brickitphil:BAABNQAECn8jAAISAAoK1RwdCgC6AQASAAoK1RwdCgC6AQAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Bruaimiamh:BAAANQADCgMIAwABNQAECgIIAgAHAAAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIIAgAHAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAABNQAECn8ZAAMUAAgKhBqYCgAfAgAUAAcKxxuYCgAfAgAcAAMK4QuVJgGLAAAAAA==.Bulldan:BAAANQAECgQIBwAAAA==.Bullvi:BAAANQAECgQIBgAAAA==.',
['Bä']='Bärkler:BAAANQAECgUJBgAAAA==.',
['Bé']='Béckléy:BAABNQAECn8XAAIeAAkKiCHJBAA7AwAeAAkKiCHJBAA7AwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cannïbal:BAAANQAECgYICQAAAA==.Caprichos:BAAANQADCgYIBgAAAA==.Cara:BAAANQADCgMIBAAAAA==.Carra:BAABNQAECn8nAAIWAAgKYBh8XABgAgAWAAgKYBh8XABgAgAAAA==.Cassiopeía:BAEANQAECgYIBQABNQAECggICAAHAAAAAA==.Catriona:BAABNQAECn8hAAIWAAYK2gmCygBsAQAWAAYK2gmCygBsAQAAAA==.',
Ch='Charcuterie:BAACNQAFFH8YAAIfAAcKMQ+yAQD4AQAfAAcKMQ+yAQD4AQA1AAQKfyAAAh8ACgpAH8YGANkCAB8ACgpAH8YGANkCAAAA.Chartou:BAAANQADCggICAAAAA==.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheeze:BAAANQABCgUIBQABNQAECgcIIQAWANcQAA==.Cheezeburg:BAABNQAECn8hAAMWAAcK1xCfLwBiAQAWAAcK1xCfLwBiAQAgAAYKpQlnRgAnAQAAAA==.Chicken:BAAANQAECgcICQABNQAFFAcIGAAPADMWAA==.Chikindalf:BAAANQADCgEJAQAAAA==.Chillainkor:BAAANQAECgUIBQABNQAFFAEIAQAHAAAAAA==.Chillidán:BAABNQAECn8mAAIdAAgKxwMgQABLAQAdAAgKxwMgQABLAQAAAA==.Choggie:BAABNQAECn8wAAMhAAoKbxfAAwC7AgAhAAoKbxfAAwC7AgAIAAYKawNQOAHGAAAAAA==.Chulainn:BAABNQAECn8VAAIMAAgKnQuVEgBFAQAMAAgKnQuVEgBFAQAAAA==.',
Co='Cons:BAABNQAECn82AAMQAAoKTh4dCwAzAgAQAAoKTh4dCwAzAgAiAAEKBAvsKgAuAAAAAA==.Corellon:BAABNQAECn8rAAIWAAkK2RyLDwD0AQAWAAkK2RyLDwD0AQAAAA==.',
Cr='Cranee:BAABNQAECn9MAAMYAAoKAhQ7SgB0AgAYAAoKgBM7SgB0AgAZAAMKTA2RCQCFAAAAAA==.Cranium:BAABNQAECn8ZAAISAAgKayHHGQC9AgASAAgKayHHGQC9AgAAAA==.Crazytasty:BAABNQAECn82AAIWAAoKFh3rAwCgAgAWAAoKFh3rAwCgAgAAAA==.Critcomander:BAAANQADCgYIDAAAAA==.',
Cy='Cyndel:BAAANQABCgIIAgAAAA==.',
Da='Dabora:BAABNQAECn8/AAMBAAoKKyErAQC5AgABAAoKKyErAQC5AgACAAIKEg4yGABhAAAAAA==.Damassan:BAAANQABCgYIBgAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECggIIgAWAC0IAA==.Darige:BAAANQAECgUIDwAAAA==.Darim:BAABNQAECn8zAAIIAAoKYyToAwDKAgAIAAoKYyToAwDKAgABNQADCgYIBgAHAAAAAA==.Darthshob:BAAANQAECgcIBwAAAA==.Darthspawn:BAABNQAECn8eAAISAAcK2gdhLgDiAAASAAcK2gdhLgDiAAAAAA==.Daryn:BAAANQAECgEIAQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIIAgAHAAAAAA==.',
De='Deadchops:BAAANQAECgQIBQABNQAECgYICAAHAAAAAA==.Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQAFFAEIAQAAAA==.Demonicfury:BAAANQAECgIIAgAAAA==.Dencity:BAABNQAECn85AAMQAAoKhhzEFwCzAQAQAAoKhhzEFwCzAQAiAAEK3wOLMAAjAAAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQAECgMIAwABNQAECggIGQAcAA4ZAA==.Devitodevour:BAABNQAECn82AAMYAAoKaxovEADBAQAYAAgKDhgvEADBAQAZAAIKgiGVBgC7AAAAAA==.Devwarr:BAABNQAECn8ZAAIcAAgKDhnGPwAkAQAcAAgKDhnGPwAkAQAAAA==.Dezard:BAAANQABCgIIAgAAAA==.',
Dh='Dhbert:BAAANQAECgIIAgAAAA==.Dhomeli:BAAANQAECgIIAwAAAA==.Dhometri:BAAANQADCgIIAgAAAA==.',
Di='Dicbswellin:BAAANQAECgEIAQAAAA==.Dirtchez:BAAANQAECgUIBQAAAA==.Disastrophy:BAAANQAECgYICAAAAA==.Disturbed:BAABNQAECn82AAQYAAoK0BgISQB4AgAYAAkKoRcISQB4AgAZAAMKIxYpOQDcAAAjAAEKkwScNAAoAAAAAA==.',
Dk='Dkson:BAACNQAFFH8NAAIbAAUK/xpRCwCgAQAbAAUK/xpRCwCgAQA1AAQKfzEAAhsACgoPIB0IAHsDABsACgoPIB0IAHsDAAAA.',
Do='Docen:BAAANQAECgUIBwAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.Download:BAAANQADCggICAAAAA==.',
Dr='Dragonfist:BAAANQAECgUICwAAAA==.Dragthyr:BAAANQADCgYIEgAAAA==.Druiaier:BAAANQAECgUIBwAAAA==.Druknatsu:BAAANQAECgYIDgAAAA==.',
Du='Dustyknight:BAAANQAECggIEgAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgcIEAAAAA==.',
Ec='Ecthan:BAAANQADCgQIBAAAAA==.',
Ed='Edge:BAABNQAECn8hAAIFAAcKXyH8DgDkAQAFAAcKXyH8DgDkAQAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elicio:BAAANQADCgMIAwAAAA==.Elidoria:BAEBNQAECn82AAIOAAoK8RuQCQAxAgAOAAoK8RuQCQAxAgAAAA==.Elphinia:BAAANQADCgYJBgABNQAECgoKMQAGAEgbAA==.',
En='Enoki:BAABNQAECn8ZAAMGAAoKHh1IIwD6AgAGAAoKHh1IIwD6AgAFAAIKhwt9+gB2AAABNQAFFAcIFgAhAOoSAA==.',
Ep='Ephodess:BAAANQAECgUICAAAAA==.',
Er='Eraduckated:BAABNQAECn8aAAMBAAgKRx94IQB4AgABAAcKRx94IQB4AgACAAUKNhFQEAAbAQAAAA==.Erde:BAAANQAECgIIAwAAAA==.',
Es='Esco:BAAANQAECgEIAQAAAA==.Esile:BAABNQAECn8sAAIkAAgKTQqqBQAuAQAkAAgKTQqqBQAuAQAAAA==.Esoryn:BAABNQAECn8sAAIIAAkKACRyIQA+AwAIAAkKACRyIQA+AwAAAA==.',
Ev='Everlife:BAAANQAECgEIBQAAAA==.Evilainkor:BAABNQAECn8cAAIbAAoKbhiLJgCJAgAbAAoKbhiLJgCJAgABNQAFFAEIAQAHAAAAAA==.',
Ex='Exia:BAACNQAFFH8WAAIcAAYK+RL2DADjAQAcAAYK+RL2DADjAQA1AAQKfxsAAhwACgqlEPR4ACwCABwACgqlEPR4ACwCAAAA.',
Fa='Fallnphoenix:BAAANQAECgQIAgAAAA==.Fauzzie:BAAANQAECgUIDgAAAA==.Fayrel:BAABNQAECn8cAAIGAAcKJAo/lgBtAQAGAAcKJAo/lgBtAQAAAA==.',
Fe='Fedders:BAABNQAECn8wAAIIAAoK6iSVBADVAwAIAAoK6iSVBADVAwAAAA==.Felaids:BAABNQAECn8sAAQYAAgKIx/NWABMAgAYAAcKeh/NWABMAgAZAAIKTRhvTwCRAAAjAAIKWhDQIgBmAAAAAA==.Felnyx:BAAANQADCgYJCgAAAA==.Felstone:BAAANQABCgIIAgABNQADCgYIBgAHAAAAAA==.Feor:BAAANQAECgYIEQAAAA==.Feralyn:BAAANQAECgIIAQAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAACNQAFFH8NAAIIAAQKhyCVDwBTAQAIAAQKhyCVDwBTAQA1AAQKfyIAAggACQriIRk4AO8CAAgACQriIRk4AO8CAAAA.Fionas:BAAANQAECgUIDQAAAA==.Firexcracker:BAAANQAECgEIAQAAAA==.Fishfood:BAABNQAECn8xAAITAAoK+BaWAwAXAgATAAoK+BaWAwAXAgAAAA==.Fixer:BAAANQAECgEIAQAAAA==.',
Fl='Flappysnail:BAAANQADCgYICwAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fo='Foondin:BAAANQAECgQICAAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frazzle:BAAANQADCgMIAwABNQAECgQICAAHAAAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAABNQAECn8lAAIOAAoKRBIUjABnAgAOAAoKRBIUjABnAgAAAA==.',
Fu='Fujitora:BAAANQAECgQIDQAAAA==.Funbunz:BAAANQAECgEIAQAAAA==.',
['Fø']='Førd:BAACNQAFFH8IAAIkAAIKEBxJAgCUAAAkAAIKEBxJAgCUAAA1AAQKfzMABCQACgrsG/ELAKcCACQACQoOGvELAKcCACUACQoUF4kIAAkCABUABQoqBc86AMIAAAAA.',
Ga='Gahza:BAAANQADCggIDQAAAA==.Galyte:BAAANQADCgQIBwAAAA==.Gangrene:BAABNQAECn8sAAITAAkKVRG2DQByAQATAAkKVRG2DQByAQAAAA==.Gaspasser:BAAANQAECgYIDgAAAA==.Gaviin:BAABNQAECn8nAAIBAAoKhRuKAQCQAgABAAoKhRuKAQCQAgAAAA==.',
Ge='Gearador:BAAANQADCgMIBAAAAA==.Genovia:BAAANQADCgQIBAABNQAECggIBAAHAAAAAA==.Gerhart:BAABNQAECn8zAAMJAAoKkxuyEwABAwAJAAkKXx2yEwABAwAKAAkK4hj+CQA+AgAAAA==.',
Gi='Gigarius:BAABNQAECn8oAAMmAAcKSxzfFwA6AgAmAAYKaiHfFwA6AgAIAAEKzgcl/gAyAAAAAA==.Gizelia:BAAANQADCgMIBAAAAA==.',
Gl='Gleya:BAAANQADCgYIBwAAAA==.Gloomy:BAAANQADCgYIBgAAAA==.',
Gn='Gnomestomper:BAAANQABCgIIAQAAAA==.',
Go='Goblinsrhot:BAAANQADCggIIAAAAA==.Goncor:BAAANQAFFAIIAwAAAA==.Gorrelord:BAAANQADCgIIAgABNQAFFAUIFAAOAOcZAA==.',
Gr='Gracze:BAAANQAECgYIBwAAAA==.Gramadingg:BAAANQADCgEIAQAAAA==.Granolah:BAAANQAECgQIDwABNQAECgoKPwABACshAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgYIDAAAAA==.Greyback:BAAANQADCgMIAwAAAA==.Griffmonk:BAABNQAECn8qAAILAAkKnyAUAwALAgALAAkKnyAUAwALAgAAAA==.Grimoire:BAAANQAECgQIBAABNQAECgYICAAHAAAAAA==.Grumpymage:BAABNQAECn8pAAINAAgK9SBfBADoAgANAAgK9SBfBADoAgAAAA==.',
Gu='Gunjamomma:BAAANQAECgMIAwAAAA==.',
Ha='Hafsac:BAABNQAECn8WAAIJAAkKLRQXHgAJAQAJAAkKLRQXHgAJAQAAAA==.Hamasakura:BAAANQADCggIDwAAAA==.Hardord:BAAANQAECgYIEAAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAABNQAECn8sAAIPAAkKRRglBQB6AQAPAAkKRRglBQB6AQAAAA==.',
He='Healchucky:BAAANQAECgIIAgAAAA==.Healzjoogewd:BAAANQAECgQICAAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.Hexflex:BAAANQAECgEIAQAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAABNQAECn8mAAIQAAkKpBXSNgAmAQAQAAkKpBXSNgAmAQAAAA==.Holikow:BAABNQAECn8aAAIIAAcKYxAfWQASAQAIAAcKYxAfWQASAQAAAA==.Holyherpies:BAAANQAECgIIAgAAAA==.Holyness:BAABNQAECn8YAAImAAcK/BzoGwANAgAmAAcK/BzoGwANAgAAAA==.Honeybunz:BAAANQADCgMIBAAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAABNQAECn8aAAMmAAgK4xInJwClAQAmAAgKoBInJwClAQAIAAcKQAyY6gBHAQABNQAFFAUIEAAVAKgcAA==.',
Hu='Hurano:BAABNQAECn8XAAIhAAoKFiCDCgAaAgAhAAoKFiCDCgAaAgAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Ic='Icekel:BAAANQADCgUIBQAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
Ih='Ihsan:BAAANQAECggIDQAAAA==.',
Il='Ilharess:BAAANQADCggICAAAAA==.Illusiõn:BAAANQAECgQIBAAAAA==.',
In='Inducktive:BAAANQAECgUIBQABNQAECggIGgABAEcfAA==.Inkdot:BAABNQAECn81AAMhAAoKqh99FQAqAwAhAAoKqh99FQAqAwAIAAgKVxUboQDfAQAAAA==.Inkshield:BAAANQADCgYICAABNQAECgoKHQALAJscAA==.Inkwell:BAAANQAECgIIAgABNQAECgoKNQAhAKofAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Io='Io:BAAANQAECgUIBQABNQAECgoKIQAbAA8hAA==.Iomedáe:BAAANQADCgMIAwAAAA==.',
Ir='Irishnight:BAAANQADCgQICgABNQAECgoKLgAnAKEQAA==.Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQAECgEIAQAAAA==.',
Ja='Jakobo:BAABNQAECn8UAAMIAAkKkiLyzQB/AQAIAAUKDSDyzQB/AQAhAAUKXREKowA+AQAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarkus:BAAANQADCgYIBwAAAA==.Jarthas:BAAANQADCgYIDQAAAA==.Jazlynel:BAAANQADCgYIBgAAAA==.',
Je='Jelly:BAACNQAFFH8WAAIhAAcK6hJdBABAAgAhAAcK6hJdBABAAgA1AAQKfykAAyEACgohH4QOAFYDACEACgohH4QOAFYDAAgAAwrMGmoxAdAAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.Jenni:BAAANQADCgcIBwAAAA==.',
Ji='Jimbostein:BAAANQADCgMIAwAAAA==.',
Jo='Johnnyblaze:BAAANQADCgIIAgAAAA==.Jozalin:BAAANQADCgQIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgQICAAAAA==.Junknthtrunk:BAAANQAECgIIAwAAAA==.',
Ka='Kaelana:BAAANQABCgQIBQAAAA==.Kamahl:BAABNQAECn8iAAIcAAkKdRTRJgBqAQAcAAkKdRTRJgBqAQAAAA==.',
Ke='Keanew:BAABNQAECn8mAAMJAAgK/hI/GgAiAQAJAAgK/hI/GgAiAQAKAAEKAAC6MwAtAAAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIIgAAAA==.Keonna:BAAANQADCgYIEwAAAA==.Keppra:BAAANQAECgQIBwAAAA==.Kerlin:BAABNQAECn8nAAIoAAoKWxxhBgDoAQAoAAoKWxxhBgDoAQAAAA==.',
Kh='Kheilah:BAAANQADCgEIAQAAAA==.Khurst:BAAANQAECgQIBAAAAA==.',
Ki='Kialis:BAEANQAECgMIAwABNQAECgcIDQAHAAAAAA==.Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgMIBAAAAA==.Kinoxo:BAACNQAFFH8WAAIcAAcKSxx5BACPAgAcAAcKSxx5BACPAgA1AAQKfzQAAxwACQoRJUQSAHMDABwACQoRJUQSAHMDABQAAQpIIWgrAFgAAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kitina:BAAANQABCgIIAQAAAA==.Kitsunë:BAAANQADCgYIBgAAAA==.Kittyclysm:BAAANQAECgIIAgAAAA==.',
Ko='Kossuth:BAAANQABCgEIAQAAAA==.Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQAECgUIBAAAAA==.Krampusnacht:BAAANQADCgYIBgAAAA==.Krissycat:BAAANQAECggIDAAAAA==.',
La='Langris:BAAANQAECgEIAQABNQAECgYICAAHAAAAAA==.Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgYIDgABNQAFFAIICAAcAM8VAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAABNQAECn81AAIQAAoKVh9dAgBEAwAQAAoKVh9dAgBEAwAAAA==.Leiche:BAAANQAECgQICwAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Lichma:BAAANQABCgEIAQAAAA==.Liferia:BAAANQAECgYICAABNQAECgcIDAAHAAAAAA==.Ligerzero:BAAANQAECgEIAQAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgMIBAAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECgYIGgAFABwSAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Littlefry:BAAANQABCgEIAQAAAA==.Livesey:BAABNQAECn8bAAMVAAgKrBMBHwDjAQAVAAgKrBMBHwDjAQAlAAEKAAAGJgAsAAAAAA==.',
Lo='Lockpie:BAAANQADCgQIBAAAAA==.Longshañk:BAABNQAECn8fAAIXAAoK6RVGBACmAgAXAAoK6RVGBACmAgAAAA==.',
Lu='Lucibrew:BAABNQAECn8cAAMEAAkKkR42FAC1AgAEAAkKQxw2FAC1AgAfAAcK1h4uDABCAgAAAA==.Lunaar:BAAANQADCgUIBQAAAA==.Luto:BAAANQAECggIDAAAAA==.Luuko:BAAANQADCgMIAwAAAA==.',
Ma='Mackaveli:BAAANQADCgYIBgAAAA==.Macpreizy:BAAANQADCgQIFQAAAA==.Macshorty:BAAANQADCgEIAQAAAA==.Mattydruid:BAAANQAECgMICwAAAA==.Mavelor:BAAANQADCgcIBwAAAA==.Mavramune:BAABNQAECn8nAAIWAAkK1Bh2UwB2AgAWAAkK1Bh2UwB2AgAAAA==.',
Mc='Mcfizzertz:BAAANQAECggIBAAAAA==.Mcfürry:BAAANQAECgQIBAAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECgoKNAAaAJYeAA==.Mendinna:BAAANQADCggIHQABNQAECggIGwAMAAQMAA==.Mendool:BAAANQADCgcIBwABNQAECggIGwAMAAQMAA==.Mendoon:BAABNQAECn8bAAIMAAgKBAzhFQAuAQAMAAgKBAzhFQAuAQAAAA==.Methir:BAAANQAECgUIBQABNQAECgcIKAAHAAAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAACNQAFFH8aAAIWAAYKERkCBQAHAgAWAAYKERkCBQAHAgA1AAQKfzgAAhYACgpKJnQDAM8DABYACgpKJnQDAM8DAAAA.Mistborn:BAAANQAECggICQABNQAECgoKHQALAJscAA==.',
Mo='Moistmaker:BAAANQAECgQIBQAAAA==.Moneygame:BAABNQAECn8aAAIOAAkKExabmwBJAgAOAAkKExabmwBJAgABNQAECgkJPQAJAI4lAA==.Montebrew:BAAANQADCgYIBgABNQADCgcIDAAHAAAAAA==.Montecane:BAAANQADCgcIDAAAAA==.Mooferrigno:BAAANQAFFAIIAgABNQAFFAMIAwAHAAAAAA==.Mooky:BAABNQAECn8iAAIMAAgKvAn9UACYAQAMAAgKvAn9UACYAQAAAA==.Moonfire:BAAANQAECggJCAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.Moshicat:BAAANQAECgYIDQAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAABNQAECn8WAAMjAAYKIRM5EABKAQAjAAUKIRM5EABKAQAYAAQKwQqJ9wDcAAAAAA==.Mythallas:BAAANQADCgIIAgAAAA==.',
Na='Nadezda:BAAANQAECgYIBgAAAA==.Nakir:BAAANQAECgUIDgAAAA==.Naraku:BAABNQAECn85AAMYAAoKTiDMKABOAQAZAAQKUSK9IgBcAQAYAAgK9R3MKABOAQAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAABNQAECn8nAAIYAAgKyxN6GQCLAQAYAAgKyxN6GQCLAQAAAA==.Nehemez:BAAANQADCggICAABNQAECgEIAQAHAAAAAA==.Neshock:BAAANQAECgIIAgABNQAECgkJFwAMAOoWAA==.Nettie:BAAANQAECgUIDgAAAA==.Netty:BAAANQAECgQIBgABNQAECgUIDgAHAAAAAA==.',
No='Nobodygnomes:BAAANQAECggICgAAAA==.Noctyra:BAAANQADCgUIDQAAAA==.Novakayne:BAAANQADCgMIBAAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.Nusy:BAAANQADCgQIBAAAAA==.',
Ny='Nymphetamine:BAABNQAECn8hAAIQAAgKuRQjGQCrAQAQAAgKuRQjGQCrAQAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAABNQAECn80AAIgAAoKzw6rBgB+AQAgAAoKzw6rBgB+AQAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgcIIQAWANcQAA==.',
Ow='Owenwilson:BAAANQAECgEIAQAAAA==.',
Pa='Pandaloco:BAAANQAECgMIAwAAAA==.Pandalôc:BAAANQAECgUIDgAAAA==.Pandoe:BAACNQAFFH8cAAInAAcK0SBoAABjAgAnAAcK0SBoAABjAgA1AAQKfzgAAicACgqyJYUAAPkDACcACgqyJYUAAPkDAAAA.',
Pe='Penelopea:BAABNQAECn8XAAMNAAgK6w8iHQAFAQAOAAcKnwrKCQF8AQANAAUKRBQiHQAFAQAAAA==.Perun:BAABNQAECn8VAAMGAAcK0ht0cgDJAQAGAAYKhRp0cgDJAQAFAAIKuQSfDgFLAAAAAA==.',
Ph='Phaithfulnes:BAAANQADCgUIBQABNQAECgcIGAAmAPwcAA==.Phenomenal:BAABNQAECn8XAAIgAAgK1hhFJgAaAgAgAAgK1hhFJgAaAgAAAA==.Pheonyx:BAAANQAECgUIBQAAAA==.',
Pi='Picarus:BAAANQAECgMIAwAAAA==.Picklerìck:BAAANQAECgYIEAAAAA==.',
Pl='Planb:BAAANQAECgUJCwABNQAECgoKTAAYAAIUAA==.',
Pn='Pneumonya:BAAANQAECgMIAwAAAA==.',
Po='Porteagarder:BAAANQAECgYICgABNQAECggIEgAHAAAAAA==.',
Pr='Preparedpie:BAACNQAFFH8ZAAMJAAYKPxFyBwDFAQAJAAYKPxFyBwDFAQAdAAQKRAwjCwAXAQA1AAQKf0AAAwkACgoJIV4NAD0DAAkACQoZIV4NAD0DAB0ACQqfIC0LACoDAAAA.Priarace:BAAANQAECggIDAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAcIGAAPADMWAA==.Producktive:BAAANQAECgIIAgABNQAECggIGgABAEcfAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQAECgQIBAABNQAECggILAAkAE0KAA==.Príestly:BAAANQAECgcIDQAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgUIBAAAAA==.',
Py='Pyatt:BAABNQAECn8uAAIjAAoKQBleAABWAgAjAAoKQBleAABWAgAAAA==.Pyromaniacal:BAAANQAECgQIBQAAAA==.',
['Pä']='Pändaloc:BAAANQAECgEIAQAAAA==.',
Qe='Qe:BAAANQADCgQIBAAAAA==.',
Qu='Quack:BAAANQAECggIDAAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECggIDAAHAAAAAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCggILQABNQAECggIEgAHAAAAAA==.',
Qy='Qyburn:BAABNQAECn8ZAAMBAAkKbx0UGAC7AgABAAkKbx0UGAC7AgADAAMKixqJPQDMAAAAAA==.',
Ra='Radacast:BAAANQABCgIIAgAAAA==.Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQADCgcIBwABNQAECgUIEwAHAAAAAA==.Ragecage:BAAANQAECgIIAgABNQAECgkJIAAYAIQXAA==.Ragga:BAAANQADCgUIBQAAAA==.Randivh:BAAANQADCgYIDAAAAA==.Rassputin:BAABNQAECn8UAAIOAAcKYxR85wC7AQAOAAcKYxR85wC7AQAAAA==.Raye:BAAANQADCgYIBgAAAA==.',
Re='Recipes:BAABNQAECn8dAAMLAAoKmxxyDQCtAgALAAoKmxxyDQCtAgAfAAEKAACsGQAAAAAAAA==.Redbeardd:BAAANQADCggIHAAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgABNQAECgkJFgAJAC0UAA==.Rendezvous:BAAANQAECgIIAQAAAA==.Renkà:BAABNQAECn8xAAIGAAoKSBu2KwDQAgAGAAoKSBu2KwDQAgAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECn81AAITAAoKEx6NBwC2AQATAAoKEx6NBwC2AQAAAA==.Reyanne:BAAANQAECgMIAwABNQAECgQIBwAHAAAAAA==.',
Rh='Rheas:BAAANQADCgYIDAABNQAECggIBAAHAAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAcIGAAPADMWAA==.',
Rn='Rn:BAAANQADCgQIBAAAAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEJAQABNQAECggIBAAHAAAAAA==.Roflthump:BAAANQADCgcJBwAAAA==.Roketraccoon:BAAANQAECgMIAwAAAA==.Rootbreaker:BAAANQAECgEIAQABNQAECgYICAAHAAAAAA==.Rosamyna:BAEANQADCgQIBwABNQAECgUIEwAHAAAAAA==.Roshamandes:BAABNQAECn8vAAIKAAoKdhnGAACBAgAKAAoKdhnGAACBAgAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgcIIwAbAJUGAA==.Runep:BAAANQAECgEIAQAAAA==.Runstupid:BAAANQADCgUIBQAAAA==.',
['Rè']='Rèi:BAAANQAECgMICAABNQAECgoKNgAWABYdAA==.',
Sa='Sabermage:BAAANQAECgYICQAAAA==.Sacredchikín:BAABNQAECn8hAAMYAAkKlhyvKwDWAgAYAAkKlhyvKwDWAgAZAAEKuBQwdgA4AAAAAA==.Samuel:BAAANQAECgMIBgAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgUICQAAAA==.Saxa:BAABNQAECn8vAAIdAAkKyCJPAwABAgAdAAkKyCJPAwABAgAAAA==.',
Sc='Screamsoda:BAAANQAECgYICgABNQAECgoKHQALAJscAA==.Scrubzz:BAAANQAECgYIDAAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekobrew:BAAANQADCgYICQAAAA==.Seyekolock:BAABNQAECn8WAAIYAAgKKhGzQQAJAQAYAAgKKhGzQQAJAQAAAA==.Seyekosis:BAABNQAECn8hAAIdAAgKdhoMBADkAQAdAAgKdhoMBADkAQAAAA==.',
Sg='Sgathaich:BAEANQAECgUIBwABNQAECgYIBwAHAAAAAA==.',
Sh='Shadowzform:BAAANQABCgYIBAABNQAECgQICAAHAAAAAA==.Shallistiah:BAABNQAECn8iAAMMAAgKnwy0TQCqAQAMAAgKnwy0TQCqAQAoAAYKwQxAQwASAQAAAA==.Shamadin:BAAANQAECgMIAwAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdh:BAAANQAECgYIDAAAAA==.Shamdwarf:BAAANQAECggIDAAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQADCggIDgAAAA==.Shobadon:BAAANQAECggICwAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgQICAAAAA==.',
Si='Siatral:BAACNQAFFH8QAAIVAAUKqBxuAwCFAQAVAAUKqBxuAwCFAQA1AAQKfy8AAxUACgqHIeoEAF8DABUACgqHIeoEAF8DACUAAQruEkEjADoAAAAA.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQAECgMIBAABNQAECggIBAAHAAAAAA==.Sigvolden:BAAANQAECgEJAQABNQAECggIBAAHAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAABNQAECn8pAAMNAAkKJBi5AgCsAQANAAkKJBi5AgCsAQAOAAYKwQL6VgEAAQAAAA==.Silver:BAAANQAECgIIAgABNQAECgkJKQANACQYAA==.Siona:BAABNQAECn8sAAIWAAkKjQcfTAAbAQAWAAkKjQcfTAAbAQAAAA==.Sixpaths:BAAANQAECgYIEwABNQAECgoKHQALAJscAA==.Siyunkai:BAEANQAECgIIAwABNQAECgUICQAHAAAAAA==.Siyunprai:BAEANQAECgUICQAAAA==.Siyunzu:BAEANQAECgIIAgABNQAECgUICQAHAAAAAA==.',
Sk='Skadie:BAABNQAECn8rAAIWAAkKXBOIZABMAgAWAAkKXBOIZABMAgAAAA==.Skittellz:BAAANQABCgMIAwAAAA==.Skiye:BAAANQADCgcIBwAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgAHAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgAHAAAAAA==.Skwup:BAABNQAECn8tAAMhAAoKvBeBLgCsAgAhAAoKvBeBLgCsAgAIAAQKpxaMGgHzAAAAAA==.',
Sl='Slackness:BAAANQAECgEIAQAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slappygilmor:BAAANQADCgcIBwABNQAECgQICAAHAAAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggJCQABNQAFFAUIFAAOAOcZAA==.Sleepybeard:BAAANQAECgQICAAAAA==.Slubadub:BAABNQAECn8aAAQKAAkKmx0XDQDxAQAdAAgKThtpHwBUAgAKAAUKySIXDQDxAQAJAAUKHhNVVgAzAQABNQAFFAMIAwAHAAAAAA==.',
Sm='Smiteslay:BAAANQAECgUJCgABNQAFFAUIFAAOAOcZAA==.',
Sn='Snivels:BAABNQAECn8VAAMMAAcKKQwwWAB0AQAMAAcKKQwwWAB0AQAeAAMKjgyULwCVAAAAAA==.Snïpe:BAAANQABCgQIBAAAAA==.',
So='So:BAABNQAECn8YAAIQAAkK3SAZSwBEAgAQAAkK3SAZSwBEAgAAAA==.Soggycat:BAEANQADCgEIAQAAAA==.Soil:BAABNQAECn8rAAIjAAoKwSH/AABqAwAjAAoKwSH/AABqAwAAAA==.Somna:BAAANQAECgUJCwAAAA==.',
Sp='Sparrkle:BAABNQAECn8vAAIZAAoKjAYqBADxAAAZAAoKjAYqBADxAAAAAA==.Spawnkis:BAAANQADCggICAAAAA==.Spayme:BAAANQAECgEIAQAAAA==.Spida:BAAANQADCgIIAgAAAA==.Spinecrawler:BAABNQAECn8gAAIYAAkKhBeuSwBwAgAYAAkKhBeuSwBwAgAAAA==.Spyro:BAAANQAECgIIAwAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIIAgAHAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgMIBAAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stickshamm:BAAANQAECgEIAQAAAA==.Stiick:BAABNQAECn8sAAImAAkKkRh/CABzAQAmAAkKkRh/CABzAQAAAA==.Stonecracker:BAAANQADCgMIBAAAAA==.Stöut:BAAANQAECgIIAgABNQAECgYICAAHAAAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.Sudsy:BAAANQADCgUICAABNQAECggIGQAUAIQaAA==.Supadupaman:BAAANQAECggIDwAAAA==.Supaman:BAAANQABCgUIBwAAAA==.',
Sw='Sweetbippy:BAAANQAECgUIDgAAAA==.Swifthealss:BAABNQAECn8bAAMnAAgKURGLJgBhAQAnAAgKURGLJgBhAQAeAAEKDQUdJQAaAAAAAA==.Swirls:BAAANQAECgMIBAAAAA==.',
Sy='Sylunae:BAAANQAECgEIAQABNQAECggIEgAHAAAAAA==.Syluné:BAAANQAECggIEgAAAA==.',
Ta='Tabasco:BAAANQAECgcICwABNQAFFAcIGAAPADMWAA==.Tacoshaman:BAAANQADCgIJAgABNQAECgMIAwAHAAAAAA==.Tacozpriest:BAAANQAECgIIAgABNQAECgMIAwAHAAAAAA==.Taelyx:BAAANQAECgYIEwAAAA==.Taishyoo:BAAANQADCgUIBgAAAA==.Tamago:BAAANQAECgYIBgABNQAFFAcIFgAhAOoSAA==.Tambot:BAAANQAECgcICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgYIEQAAAA==.Tazmina:BAABNQAECn8hAAIJAAYKwB6eQgCtAQAJAAYKwB6eQgCtAQAAAA==.',
Te='Teddykgb:BAAANQAECgIIAwAAAA==.Teenieweenie:BAAANQADCgUIBQAAAA==.Tequilàrose:BAAANQADCgYIBwABNQAECgQICAAHAAAAAA==.Tessa:BAABNQAECn8sAAIGAAkKTxMjGABgAQAGAAkKTxMjGABgAQAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAABNQAECn8pAAQQAAoKihtUMQCjAgAQAAgKnR5UMQCjAgARAAkK7hKpIQApAgAiAAEKvQkRLQAqAAAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIIAgAHAAAAAA==.Thejudge:BAAANQAFFAMIAwAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinkey:BAAANQAECgMIAwAAAA==.Tinyjapeto:BAAANQAECgUICwAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAABNQAECn8sAAIWAAkK3B8YEwDYAQAWAAkK3B8YEwDYAQAAAA==.Tortapounder:BAAANQAECgQIDAAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgUICwAAAA==.',
Tu='Turin:BAABNQAECn8vAAIPAAoKvgnuBwA3AQAPAAoKvgnuBwA3AQAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twiggysmalls:BAAANQADCgUIBAAAAA==.Twilghtdawn:BAAANQADCgUIBQAAAA==.Twotone:BAAANQAECggICAAAAA==.',
Ty='Tybo:BAABNQAECn8VAAIaAAcKJxx4FAAhAgAaAAcKJxx4FAAhAgAAAA==.Tycho:BAAANQADCgYIDQAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.Tydros:BAAANQADCggICAAAAA==.Tyriondale:BAAANQADCgEIAQAAAA==.',
Un='Uncás:BAABNQAECn8hAAIWAAcK7ArmbQDQAAAWAAcK7ArmbQDQAAAAAA==.Undyinggnome:BAAANQAECgQIBwAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Ur='Urza:BAAANQADCgQIBAAAAA==.',
Va='Vaelock:BAABNQAECn8gAAQjAAgKEQ6xBgDLAAAYAAcKjQ7ppgCGAQAjAAUKSguxBgDLAAAZAAIKTANidgA3AAAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQAECgQIBAAAAA==.Valoryan:BAABNQAECn8sAAIoAAkK5hzwBQD1AQAoAAkK5hzwBQD1AQAAAA==.Valy:BAAANQADCgcIBwAAAA==.Valyteilssra:BAAANQAECgQIBAAAAA==.Vasoline:BAAANQAECggICwABNQAECgkJHwAbACMhAA==.Vaxtur:BAAANQAECggICAAAAA==.',
Ve='Vegà:BAABNQAECn8jAAMfAAYKzQ89GgBBAQAfAAYKzQ89GgBBAQAEAAQKOgs/VgCSAAAAAA==.Vendettis:BAAANQAECgEIAQAAAA==.Veracious:BAAANQADCgQIBAAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYJBgABNQAECgUIBwAHAAAAAA==.Veylyn:BAABNQAECn8cAAIIAAYKFgjMAQEcAQAIAAYKFgjMAQEcAQAAAA==.Veztaroth:BAABNQAECn8fAAITAAgK+g5gXwCSAQATAAgK+g5gXwCSAQAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQAECgIIAgAAAA==.Voidyo:BAABNQAECn83AAMdAAoK/yAFAwCpAwAdAAoK/yAFAwCpAwAJAAgKYR6mHwCdAgAAAA==.',
['Vë']='Vëngeåncelöt:BAAANQADCgQIBAAAAA==.',
Wa='War:BAAANQADCggICAABNQAECggIIQAeAKQPAA==.',
We='Weißenacht:BAAANQAECgMIAwAAAA==.Wenno:BAAANQAECgYIBgAAAA==.',
Wh='Whiskeyjak:BAABNQAECn8qAAMPAAoKfBhOCwCIAgAPAAgKcx1OCwCIAgAcAAoK4gyeRQAWAQAAAA==.Whycatihealu:BAAANQADCgYICgAAAA==.',
Wi='Willowbark:BAAANQADCgYIEwAAAA==.Willowest:BAABNQAECn8/AAIWAAoKoyHVCQArAgAWAAoKoyHVCQArAgAAAA==.Wizbizzler:BAAANQAECgcIDwAAAA==.',
Wr='Wrathstorm:BAABNQAECn80AAIaAAoKlh7nAQA+AgAaAAoKlh7nAQA+AgAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanier:BAAANQADCgYIGAABNQAECgcIHwAjAMQQAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAABNQAECn8UAAIfAAcKsQMFHgAGAQAfAAcKsQMFHgAGAQAAAA==.Xithia:BAEANQAECgcIDQAAAA==.',
Xo='Xorm:BAAANQAECggICAAAAA==.',
Xx='Xxcor:BAAANQAECgUIBQAAAA==.',
Xy='Xyndylyne:BAAANQADCgcIBwAAAA==.',
Ya='Yahtze:BAAANQADCgYIBgAAAA==.Yanella:BAABNQAECn8qAAIQAAoKSBkLCwA0AgAQAAoKSBkLCwA0AgAAAA==.',
Yi='Yisdk:BAAANQAECgUICQAAAA==.Yispally:BAAANQAECgMIBQAAAA==.Yisshaman:BAAANQAECgcIEQAAAA==.',
Yo='Yogibearz:BAAANQAECgEIAQABNQAECgQICQAHAAAAAA==.',
Yu='Yunbao:BAAANQAECgEIAgAAAA==.',
Za='Zaijr:BAAANQAECgMIAwAAAA==.Zanax:BAAANQAECgYIEgAAAA==.Zandarbribbs:BAAANQAECgIIAwAAAA==.Zarrah:BAAANQABCgYICgAAAA==.',
Ze='Zennya:BAABNQAECn8jAAIoAAkKACBgBQAJAgAoAAkKACBgBQAJAgAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.Zeon:BAAANQABCgcICQAAAA==.',
Zo='Zoldyck:BAAANQADCggIIgAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zynnitar:BAAANQADCgEIAQAAAA==.Zyrx:BAAANQADCggIDwAAAA==.',
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
