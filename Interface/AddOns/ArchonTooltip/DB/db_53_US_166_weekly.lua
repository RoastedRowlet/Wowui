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

local lookup = {'Priest-Shadow','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Unholy','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Shaman-Enhancement','Rogue-Assassination','Druid-Restoration','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Frost','Shaman-Elemental','Druid-Balance','Druid-Guardian','Priest-Holy','Priest-Discipline','Paladin-Holy','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','Paladin-Retribution','Druid-Feral','Warrior-Arms','Mage-Fire','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','Monk-Windwalker','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Warlock-Demonology','Evoker-Devastation','Warlock-Affliction','Rogue-Subtlety','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abyssdk:BAAANQAECgEIAQABNQAFFAUICwABALwkAA==.Abyssfurry:BAAANQADCggICAABNQAFFAUICwABALwkAA==.',
Ac='Acadêmica:BAABNQAECn80AAICAAkKWhKfhQByAgACAAkKWhKfhQByAgAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adcosmos:BAAANQAECgUIBQABNQAECggIGwADAK8YAA==.Adebaio:BAACNQAFFH8IAAIEAAMKPBWpEgDeAAAEAAMKPBWpEgDeAAA1AAQKfzcAAgQACQp9JK8HAIUDAAQACQp9JK8HAIUDAAAA.',
Ae='Aegenwullf:BAAANQADCgIIAgAAAA==.Aegislashh:BAABNQAECn8fAAIFAAcKyAtbMQBRAQAFAAcKyAtbMQBRAQAAAA==.Aerlath:BAACNQAFFH8WAAIGAAYKyCEfBAACAgAGAAYKyCEfBAACAgA1AAQKfy0AAgYACQoYJq0DAJwDAAYACQoYJq0DAJwDAAAA.Aetulia:BAABNQAECn8cAAMHAAgKnw34PgC/AQAHAAgKnw34PgC/AQAGAAEK0AFVdQAeAAAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQAECgMIAwAIAAAAAA==.',
Ag='Aggroster:BAAANQAECgIIAgAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahrathor:BAAANQAECgYIDAAAAA==.Ahyeon:BAAANQAECgMIAwAAAA==.',
Ak='Akasta:BAABNQAECn80AAIJAAcKpCC8DwBrAgAJAAcKpCC8DwBrAgAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.Akâme:BAABNQAECn8YAAIKAAkK9h6cCwApAwAKAAkK9h6cCwApAwABNQAFFAQICAALAFIVAA==.',
Al='Alascayoung:BAAANQAECgEIAwAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Alatrëon:BAAANQAECgUIBwABNQAECggIHQAMAPgXAA==.Aldrathion:BAAANQAECgEIAQABNQAECgkJPQANABQkAA==.Aledk:BAAANQAECgYICAAAAA==.Alessan:BAAANQADCggIDwAAAA==.Alessary:BAAANQADCgYIBwAAAA==.Alfurieb:BAAANQAECgQIEAAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAABNQAECn8kAAMEAAkKmh9YGQDzAgAEAAkKmh9YGQDzAgAOAAEKfhFBqgA0AAAAAA==.Altreir:BAAANQADCgcIFAABNQAECgMIAwAIAAAAAA==.Aluny:BAAANQAECgYICAABNQAFFAUICAAPACIJAA==.Aluxxious:BAAANQAECgQICQAAAA==.Alëcream:BAAANQAECgcIDwAAAA==.Alíne:BAAANQAECgYIEAAAAA==.',
Am='Amrb:BAAANQADCgIIAgAAAA==.Amyzu:BAAANQADCgYICQAAAA==.Amøm:BAAANQAECgcIEAAAAA==.',
An='Anadirtei:BAAANQAFFAUIAQAAAA==.Anduinwill:BAAANQAECgEIAQAAAA==.Andärilho:BAAANQAECgQIBAABNQAECgcIDwAIAAAAAA==.Ankados:BAABNQAECn8aAAQQAAkKKRIrUACZAQAQAAYKZRgrUACZAQALAAUKSw9bQAAeAQARAAEKAADzXQA0AAABNQAFFAQICwAPALcPAA==.Ankapos:BAABNQAECn8VAAQSAAgKqgYoiAB5AQASAAgKqgYoiAB5AQABAAEKNwflfAAtAAATAAEKFgEdMwAWAAAAAA==.Annish:BAAANQADCgYJCwAAAA==.Anrond:BAAANQAECgUIBQAAAA==.Anthorforged:BAABNQAECn8aAAIUAAcK8BMHcgC+AQAUAAcK8BMHcgC+AQAAAA==.Anwvar:BAAANQADCgIIAgAAAA==.',
Ap='Apocalipse:BAABNQAECn8yAAIVAAkKDxkwBgCgAgAVAAkKDxkwBgCgAgAAAA==.',
Aq='Aquillez:BAAANQAECgQJBAAAAA==.',
Ar='Araurz:BAAANQAECgUICAABNQAECggIIQACAJYTAA==.Arinn:BAABNQAECn8YAAIWAAcKYgwkGwCSAQAWAAcKYgwkGwCSAQAAAA==.Arkcirce:BAAANQAECgUICwABNQAECggIFQAXAMQTAA==.Arkdemias:BAAANQAECgUIBgAAAA==.Arkw:BAAANQADCgMIAwAAAA==.Arnaldinho:BAAANQADCgQICAABNQAECgcIEAAIAAAAAA==.Arthalan:BAAANQAECgIIAgAAAA==.Arthega:BAAANQAECgMIBAABNQAFFAYIFgAGAMghAA==.Artoriös:BAAANQAECgIIAgABNQAECggIFgAUAHENAA==.Artradian:BAAANQAECgQIBgAAAA==.Arucàrd:BAAANQADCgYICgAAAA==.Aryethi:BAABNQAECn8sAAIYAAkKdg+4jgADAgAYAAkKdg+4jgADAgAAAA==.',
As='Asafe:BAAANQAECgIIAgABNQAECgUICgAIAAAAAA==.Ashabellanar:BAAANQAECgQICAAAAA==.Ashenna:BAABNQAECn8XAAIZAAkK+B9gBABFAwAZAAkK+B9gBABFAwAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECggIHAAHAJ8NAA==.',
Au='Aurdraen:BAAANQAECgEIAQAAAA==.Autonomo:BAAANQAECgEIAQAAAA==.',
Av='Avanthara:BAAANQAECgQIDgAAAA==.',
Aw='Awk:BAABNQAECn8gAAQSAAkKYhxmNgCLAgASAAcKuh5mNgCLAgABAAYKBR8OJQAEAgATAAEKiAdkKgAuAAAAAA==.',
Az='Azuros:BAAANQABCgIIAgAAAA==.',
['Aø']='Aøc:BAACNQAFFH8FAAIYAAIKoAe1KAB+AAAYAAIKoAe1KAB+AAA1AAQKfy0AAhgACQqEFZFwAEoCABgACQqEFZFwAEoCAAAA.',
Ba='Babara:BAAANQABCgYIBwAAAA==.Babyfart:BAABNQAECn8pAAMFAAcK5hXVKgCCAQAFAAcK5hXVKgCCAQAYAAMKKQbpYQF6AAAAAA==.Bakushiterra:BAAANQAECgYIEQAAAA==.Barao:BAABNQAECn8cAAIHAAgKMhXBNwDvAQAHAAgKMhXBNwDvAQAAAA==.Barriguinha:BAAANQAECgMIBQAAAA==.Baskervile:BAAANQAECgMIAwABNQAECgcIDwAIAAAAAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCggIGAAAAA==.',
Be='Belezona:BAAANQADCgUIBQAAAA==.Benningtn:BAAANQAECgUIBQAAAA==.Beornin:BAAANQADCgMIAwAAAA==.Betawizard:BAAANQAECgYIDwAAAA==.',
Bh='Bhast:BAAANQADCggICAABNQAECggIEgAIAAAAAA==.Bherg:BAAANQAECgUIDQAAAA==.',
Bi='Bilpaxton:BAAANQAECggIBwAAAA==.Biscilla:BAAANQADCgQIBAAAAA==.Biskademon:BAABNQAECn8lAAIGAAkKdBujGQCKAgAGAAkKdBujGQCKAgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.Bizumgãoo:BAAANQAECgQIBgAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQAECgIIBAAAAA==.Blackwatch:BAAANQAECgUICgAAAA==.Blecktk:BAABNQAECn8YAAIaAAgKIhdqeAAqAgAaAAgKIhdqeAAqAgAAAA==.Blitzkrig:BAACNQAFFH8TAAMbAAUK8xNWAAD6AAACAAUKtBKqHQCOAQAbAAMKAQ9WAAD6AAA1AAQKfysAAxsACQoDIeoAAAoDABsACQoDIeoAAAoDAAIAAgpDFVaZAYsAAAAA.Bloodlioness:BAAANQAECgEIAQAAAA==.Bloodswar:BAAANQAECgUICgAAAA==.Bloodyclaw:BAAANQADCggIHgAAAA==.',
Bo='Bolkien:BAAANQAECgIIAwAAAA==.Boomgoesyou:BAABNQAECn8WAAIQAAgKSw2+UQCRAQAQAAgKSw2+UQCRAQAAAA==.Bourdriel:BAABNQAECn8ZAAIQAAcKLArsWwBeAQAQAAcKLArsWwBeAQAAAA==.',
Br='Bradoki:BAAANQAECgMIBgAAAA==.Bradví:BAAANQAECgEIAQAAAA==.Brancalleone:BAAANQAECgIJAgAAAA==.Brazukmaiden:BAAANQAECgIIAgABNQAECgQIBAAIAAAAAA==.Brisawave:BAABNQAECn8qAAIMAAkKoyLGEQA3AwAMAAkKoyLGEQA3AwAAAA==.Brizagato:BAABNQAECn8hAAIQAAkKaRRrMwBHAgAQAAkKaRRrMwBHAgAAAA==.Brizzarda:BAAANQADCggICAAAAA==.Broke:BAAANQAECgQIBQAAAA==.Brujaria:BAAANQAECgYIEgAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAABNQAECn8mAAIYAAkKCxuDPgDXAgAYAAkKCxuDPgDXAgAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAABNQAECn8cAAIVAAYK+RbaEQCFAQAVAAYK+RbaEQCFAQAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQAECgQIBgAAAA==.',
Ca='Caiquebmq:BAAANQAECgIIAgAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgkJJAAcAKUeAA==.Calanguinhe:BAAANQAECgQIBQAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAABNQAECn8dAAIWAAgK1weVIABqAQAWAAgK1weVIABqAQAAAA==.Canard:BAAANQAECgUIAwABNQAECgkJIgAaAJEXAA==.Canards:BAAANQAECgUIBQABNQAECgkJIgAaAJEXAA==.Cannibal:BAAANQAECgEIAwAAAA==.Carinha:BAAANQADCggJAgAAAA==.Carloxamã:BAABNQAECn8vAAIJAAkKJCOaAwBiAwAJAAkKJCOaAwBiAwAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYICQABNQAECgcIEAAIAAAAAA==.Cathiseev:BAABNQAECn8lAAMdAAkKdR+XBgA9AwAdAAkKdR+XBgA9AwAeAAUK0Q4XEgAOAQAAAA==.Cathury:BAAANQAECgMJCAAAAA==.Catÿ:BAABNQAECn8ZAAIMAAcKrB+wOQB2AgAMAAcKrB+wOQB2AgABNQAFFAQIDgASAA4lAA==.Cavernozo:BAAANQAECgcIDAABNQAECgkJFgAFABIbAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Ceifhador:BAAANQAECgUIBQAAAA==.Celfier:BAAANQAECgQIBAAAAA==.Cenarioss:BAAANQAECgQIBgAAAA==.Cerino:BAAANQADCgQIBAAAAA==.Cevadão:BAABNQAECn8gAAIfAAkKExhJFQCmAgAfAAkKExhJFQCmAgABNQAECggIEgAIAAAAAA==.',
Ch='Chaleira:BAAANQAECgUIBQAAAA==.Changjin:BAAANQAECgUICQAAAA==.Chewbaka:BAAANQAECgIIAgAAAA==.Cheweir:BAAANQAECgQICgAAAA==.Chiclete:BAABNQAECn8zAAUZAAkKjhkhDgAyAgAZAAgKxBchDgAyAgALAAkKaxFOJAD+AQAQAAQKMA7TdQDvAAARAAEKAAAZVQBLAAAAAA==.Chopz:BAAANQAECgMIAwABNQAFFAMICAAEADwVAA==.Chovor:BAAANQAECgYICQAAAA==.Chrizantm:BAAANQAECgQICwABNQAECggIIQACAJYTAA==.Chucknòórris:BAAANQAECgYIDgAAAA==.Chøcøballs:BAAANQABCgQIBAAAAA==.',
Cl='Clairë:BAAANQAECggIDwAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clbalena:BAAANQADCgEIAgAAAA==.Clio:BAABNQAECn8UAAIQAAQK/QRgjACfAAAQAAQK/QRgjACfAAAAAA==.',
Co='Cockcroft:BAAANQADCgYIDAABNQAECgkJJAAfAHsNAA==.Coionir:BAABNQAECn8XAAIZAAgKyR+JBwDjAgAZAAgKyR+JBwDjAgAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECggIFwAZAMkfAA==.Coldblooded:BAAANQADCgcIBwABNQAECgQIBQAIAAAAAA==.Coldnez:BAAANQAECgIIAgAAAA==.Comunistaa:BAACNQAFFH8GAAIPAAIKwh42HwCzAAAPAAIKwh42HwCzAAA1AAQKfywAAg8ACQokJEUFAMADAA8ACQokJEUFAMADAAAA.Coquette:BAAANQAECgUIBQAAAA==.Corruptionz:BAAANQAECgQIDAAAAA==.Corstine:BAAANQAECgYICgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Couldovisk:BAAANQADCgIJAgAAAA==.',
Cr='Crawsing:BAAANQADCgEIAQAAAA==.Cronosxdm:BAAANQAFFAEIAQAAAA==.Crucyatus:BAABNQAECn8iAAMYAAkKUR6aLwAJAwAYAAkKUR6aLwAJAwAFAAEKoR/UXwBYAAAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
Cy='Cyrande:BAAANQAECgIIAgABNQAECgIIAwAIAAAAAA==.',
['Cá']='Cássia:BAAANQADCggICQAAAA==.',
['Cå']='Cåssio:BAAANQAECgYIDwAAAA==.',
['Cÿ']='Cÿgnus:BAABNQAECn8aAAIBAAkKEB57CQBFAwABAAkKEB57CQBFAwABNQAECgkJMQAHAHQlAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Dago:BAAANQAECgEIAQAAAA==.Danadinn:BAAANQADCgcIBwABNQAECgYICAAIAAAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAABNQAECn8pAAMaAAkK+hJqcgA5AgAaAAkK+hJqcgA5AgAgAAcK7Q48EwBpAQAAAA==.Darklendio:BAAANQADCgUICgAAAA==.Daroncosp:BAAANQADCgIJAgAAAA==.Darü:BAAANQAECgQIBQAAAA==.Dashuman:BAABNQAECn8iAAIUAAkKpRxFIQDnAgAUAAkKpRxFIQDnAgAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dayshine:BAAANQADCgUIBQAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadguth:BAAANQAECggJBwAAAA==.Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgcIGwAGAFANAA==.Deceive:BAAANQAECgcIDwAAAA==.Defroque:BAAANQAECgUIBQAAAA==.Deimons:BAAANQAECggICQAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQAECgQIBAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQAECgMIBAAAAA==.Denevy:BAABNQAECn8xAAIhAAgKDBSCFgC+AQAhAAgKDBSCFgC+AQAAAA==.Deraelda:BAAANQADCgMIBAAAAA==.Derbster:BAAANQAECgcICwAAAA==.Destructiom:BAABNQAECn8iAAINAAgKfR8fOAC/AgANAAgKfR8fOAC/AgAAAA==.',
Dh='Dhamburguer:BAABNQAECn8fAAIGAAkK3BtXEgDWAgAGAAkK3BtXEgDWAgAAAA==.Dhanadrai:BAABNQAECn8YAAMXAAYKLQlMfAAEAQAXAAYKLQlMfAAEAQAEAAEKTQKK8gAiAAAAAA==.',
Di='Diabolick:BAAANQADCggICAAAAA==.Diamalboy:BAAANQADCggICAAAAA==.Diamath:BAAANQADCgUJBQAAAA==.Diggop:BAAANQAECgIIAwAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQAIAAAAAA==.Dima:BAABNQAECn8lAAIMAAkKRiGjBwCDAwAMAAkKRiGjBwCDAwAAAA==.',
Dk='Dktt:BAAANQAECgQICAAAAA==.',
Do='Dornaa:BAAANQAECgUICwAAAA==.Dosmagos:BAAANQAECgQIBAAAAA==.Doulce:BAABNQAECn8aAAMPAAcK0Q+bgQCdAQAPAAcK0Q+bgQCdAQAJAAEKAACtOQAlAAAAAA==.',
Dr='Dracarysz:BAAANQAECgIIAwAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAABNQAECn8iAAIaAAkKkRezQADFAgAaAAkKkRezQADFAgAAAA==.Dreampollys:BAAANQAECgEIAQABNQAFFAIIAgAIAAAAAA==.Dreamremix:BAAANQAFFAIIAgAAAA==.Dresaron:BAAANQADCgYIBgABNQAECgkJJAAcAKUeAA==.Dreyol:BAAANQAECgMIBAAAAA==.Drts:BAABNQAECn8vAAICAAkKpR+rRQD4AgACAAkKpR+rRQD4AgAAAA==.Drunkiechan:BAAANQAECgEIAQAAAA==.',
Du='Dudupokas:BAAANQAECgQIBAAAAA==.Dumar:BAAANQAECgcICgAAAA==.Duromargh:BAAANQADCgMIAwAAAA==.',
['Dü']='Düst:BAAANQADCggIEwAAAA==.',
Ed='Eduarthas:BAABNQAECn8VAAIEAAYKWghhhAAKAQAEAAYKWghhhAAKAQAAAA==.Edyra:BAAANQADCggICAAAAA==.',
Eg='Egoist:BAAANQADCggJDwAAAA==.',
El='Elementys:BAAANQAECgQICQABNQAECgUIBQAIAAAAAA==.Elemëntum:BAAANQAECgEIAQAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgkJPQANABQkAA==.Elinaara:BAABNQAECn8fAAMFAAcKqw3zLwBbAQAFAAcKqw3zLwBbAQAYAAEKvgqemAE4AAAAAA==.Elizabeth:BAAANQAECgMIAwAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgQIBgAAAA==.Elmagoprior:BAAANQAECgQIDQAAAA==.Elricky:BAAANQAECgEIAQAAAA==.Eluna:BAAANQAECgcICwAAAA==.Eluric:BAAANQAECgcICwABNQAECgkJPQANABQkAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.Entropye:BAAANQAECgQIBAAAAA==.',
Ep='Epsan:BAAANQAECgEIAQAAAA==.',
Er='Ercshadow:BAAANQAECgUICAAAAA==.Ermooke:BAAANQAECgQIBgAAAA==.',
Es='Escanorzão:BAAANQADCgcJDAABNQAECgMIAwAIAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Executepowa:BAAANQADCggIDgAAAA==.Exo:BAABNQAECn8kAAINAAkKIh/4JgD6AgANAAkKIh/4JgD6AgAAAA==.Exorciseur:BAACNQAFFH8MAAIHAAUKHxw+CACuAQAHAAUKHxw+CACuAQA1AAQKfzQAAgcACQqnI7cIAG8DAAcACQqnI7cIAG8DAAAA.',
Fa='Fabercästell:BAAANQAECgcICgAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Fargunn:BAABNQAECn8bAAINAAcK5BJCkADlAQANAAcK5BJCkADlAQAAAA==.',
Fe='Feanori:BAABNQAECn8hAAIHAAkKzBQ9LQA2AgAHAAkKzBQ9LQA2AgAAAA==.Feanør:BAAANQAECgYIEgAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgkJGQAGABkjAA==.Fennris:BAAANQAECgEIAwAAAA==.Feyrin:BAAANQADCggIHQAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQAIAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
Fr='Francine:BAAANQADCggICAAAAA==.',
['Fí']='Fíli:BAAANQAECgEIAQAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQAECgIIAwAAAA==.Gabrael:BAAANQABCgQJBAAAAA==.Gaiataur:BAAANQADCgUIBgAAAA==.Galandiel:BAAANQADCggIDgAAAA==.Galinni:BAAANQADCggIEAAAAA==.Gallon:BAABNQAECn8bAAIiAAgKGBmyEwA9AgAiAAgKGBmyEwA9AgAAAA==.Gandàllf:BAAANQAECgcIBwABNQAECggIFgAUAHENAA==.Garcs:BAAANQADCgQIBAAAAA==.Garfall:BAAANQAECgcIEgAAAA==.',
Gl='Glacyale:BAAANQAECgcIEgAAAA==.Glisa:BAABNQAECn8cAAQYAAkK9hX9hQAXAgAYAAkKohL9hQAXAgAFAAcKERZEJwCgAQAUAAEKagSTJwErAAAAAA==.Glorfindel:BAAANQAECgIIAwAAAA==.',
Gn='Gnomepink:BAAANQADCggIIwAAAA==.',
Go='Godadrian:BAABNQAECn8fAAMYAAgKlgy4tgCqAQAYAAgKlgy4tgCqAQAFAAEKAACFfgAdAAAAAA==.Gogozinho:BAAANQAECgUIBQAAAA==.Gordãobtm:BAAANQAECgcIEwAAAA==.Gosu:BAABNQAECn8lAAIfAAgKdiFUDgD4AgAfAAgKdiFUDgD4AgAAAA==.',
Gr='Gralfor:BAAANQAECgUIBQAAAA==.Grekorio:BAAANQAECgMIBgAAAA==.Greylord:BAAANQAECgIIAgABNQAECgkJHgAdAJUWAA==.Greylorddrak:BAABNQAECn8eAAIdAAkKlRYLEgCKAgAdAAkKlRYLEgCKAgAAAA==.Greylordp:BAAANQAECgEIAQABNQAECgkJHgAdAJUWAA==.Gromitak:BAAANQADCgUIBgAAAA==.Gronak:BAAANQAECgQJBAAAAA==.',
Gu='Guhtz:BAAANQADCgMIAwAAAA==.Guillyn:BAAANQAECgcIEAAAAA==.Gultai:BAAANQAECgYIDwAAAA==.Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgUIBwAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgIIBAAAAA==.',
Gw='Gwts:BAAANQAECgIIAgABNQAECggIKAAJAPQfAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYJBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hadoky:BAAANQADCgIIAgABNQAECgMIBAAIAAAAAA==.Hafo:BAAANQADCgYJDQAAAA==.Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBgAAAA==.Hamiister:BAAANQADCgQIBAAAAA==.Hancalimon:BAABNQAECn8dAAIQAAYKUhcjUACZAQAQAAYKUhcjUACZAQAAAA==.Haokö:BAAANQAECgIIAQAAAA==.Hasanzi:BAAANQADCgUIBQAAAA==.Hastterix:BAAANQAECgUIEwAAAA==.Hatezon:BAAANQAECgYIDAAAAA==.',
He='Heavyking:BAAANQAECgYIEQAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Helitox:BAAANQAECgQICAAAAA==.Hellhoundish:BAAANQADCgYIBgABNQAFFAQICwAgAPkTAA==.Hellreaper:BAABNQAECn8pAAIjAAkKCwzBfQDnAQAjAAkKCwzBfQDnAQAAAA==.Heloisaa:BAABNQAECn8dAAIhAAgKlhDjFwCsAQAhAAgKlhDjFwCsAQAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Hemm:BAAANQAECgMIAwAAAA==.Heracranosd:BAAANQAECgYICwAAAA==.Heracranosx:BAAANQAECgcIEAAAAA==.Heracranosz:BAAANQAECgIIAgAAAA==.Herdy:BAAANQADCgMJBAAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgUIDgAAAA==.',
Hi='Hireque:BAABNQAECn8fAAINAAgKnBk0VgBtAgANAAgKnBk0VgBtAgAAAA==.Hitkilled:BAABNQAECn8WAAINAAcKLwn9swCXAQANAAcKLwn9swCXAQAAAA==.Hitkins:BAAANQAECgUIBgAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgUIEAAAAA==.Holycel:BAAANQAECgQIBwABNQAECgkJJAAEAJofAA==.Holyscrim:BAAANQAECgEIAQAAAA==.Hoolylight:BAAANQAECgYIBwAAAA==.Hordhunter:BAAANQAECgMIAwABNQAECgkJFgAFABIbAA==.',
Hu='Huelandita:BAAANQAECgcICQAAAA==.Hunterpica:BAABNQAECn8jAAINAAkKKx6WKAD0AgANAAkKKx6WKAD0AgAAAA==.Huntmon:BAABNQAECn8VAAINAAYKWSH+mADRAQANAAYKWSH+mADRAQAAAA==.Huriah:BAAANQAECgIIAwAAAA==.Huskat:BAAANQAECgYIDAAAAA==.',
Hy='Hysillens:BAAANQAECgYIEQAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
['Hä']='Härü:BAAANQADCgUIAwAAAA==.',
['Hö']='Hölyfans:BAAANQAECgYIDgAAAA==.',
Ic='Icebïg:BAAANQAECgEIAQAAAA==.',
Ig='Ignicel:BAAANQAECgUICQABNQAECgkJJAAEAJofAA==.Igno:BAAANQAECgUIEgABNQAECgkJLQAPADklAA==.Igubigu:BAAANQADCgQIBAAAAA==.',
Il='Ilane:BAAANQABCggIDAAAAA==.Ilidarilariê:BAAANQADCgYIBgAAAA==.Illidatrix:BAABNQAECn8bAAIGAAcKUA2ENgCLAQAGAAcKUA2ENgCLAQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggJFAAAAA==.',
In='Inladris:BAAANQAECgEIAQAAAA==.Inot:BAABNQAECn8aAAISAAgKzBP4aQDcAQASAAgKzBP4aQDcAQAAAA==.',
Ir='Irmãsafada:BAAANQADCgMIAwAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgUICgAAAA==.',
It='Italodpz:BAAANQAECgUIBQABNQAECggIGwAXAAITAA==.Itsälasca:BAAANQAECgQIBQAAAA==.',
Iu='Iuri:BAAANQAECgcIEAAAAA==.',
Ix='Ixlzvaxtylxl:BAAANQADCgYIBgAAAA==.',
Iz='Izanna:BAAANQAECgUIBQAAAA==.',
Ja='Jabäl:BAAANQAECgUIBQAAAA==.Jalinrabeidh:BAAANQAECgEIAQAAAA==.Jampack:BAABNQAECn8gAAMMAAkKZiLmFwASAwAMAAkKZiLmFwASAwAPAAEKugnXOQEvAAAAAA==.',
Je='Jeevas:BAABNQAECn8dAAIUAAgKgB7LLQCtAgAUAAgKgB7LLQCtAgAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCggIDgAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQAECgEIAQAAAA==.',
Jo='Jocabiroca:BAABNQAECn8kAAMCAAkKsRg5fgCCAgACAAkKsRg5fgCCAgAbAAEKlwK7DgAqAAAAAA==.Johnez:BAAANQADCgcIBwAAAA==.Joral:BAAANQABCggICwAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAABNQAECn8lAAIcAAkKaA4qJQAgAgAcAAkKaA4qJQAgAgAAAA==.',
Jr='Jrxamã:BAABNQAECn8YAAIPAAUKmxwQfQCoAQAPAAUKmxwQfQCoAQAAAA==.',
Ju='Juliia:BAAANQAECgUIDgAAAA==.Jusgu:BAAANQAECgcICwABNQAECgkJGQACADoZAA==.',
['Jö']='Jönah:BAAANQADCgMIAwAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgYICgAAAA==.Kaju:BAABNQAECn8aAAIVAAkKkCDdBADSAgAVAAkKkCDdBADSAgAAAA==.Kalinis:BAAANQAECgEJAQAAAA==.Kalliiope:BAABNQAECn8gAAMVAAkK2wqTDQDUAQAVAAkK2AqTDQDUAQACAAUK+QJ7cAHXAAAAAA==.Kamesenin:BAAANQADCgUIBQAAAA==.Kamïlla:BAABNQAECn8YAAMgAAcKOw1EFQBFAQAgAAYKAg1EFQBFAQAaAAEKIQ4lRgE9AAAAAA==.Karak:BAAANQADCgIJAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCggIDAAAAA==.Katona:BAABNQAECn8bAAIVAAgKqBavCgAYAgAVAAgKqBavCgAYAgAAAA==.Kauss:BAAANQAECgUIBQAAAA==.',
Kd='Kdakaisa:BAAANQAECgMIAwAAAA==.Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQAECgEIAQAAAA==.Kenai:BAABNQAECn8WAAIRAAgK/gvoJgBZAQARAAgK/gvoJgBZAQAAAA==.Kewenz:BAABNQAECn8xAAINAAkK0yaQAAAHBAANAAkK0yaQAAAHBAABNQAFFAQICQANAOkjAA==.Keylaa:BAAANQAECgcIEQAAAA==.',
Kh='Khasin:BAABNQAECn8eAAIjAAcKjwXvzQApAQAjAAcKjwXvzQApAQAAAA==.',
Ki='Kierke:BAAANQAECgUIDQABNQAECggIGwABAKYfAA==.Kimyx:BAAANQAECgcIDAABNQAFFAQICQANAOkjAA==.Kindz:BAAANQAECgQIBAABNQAFFAQICQANAOkjAA==.Kiregeth:BAAANQAECgYIDQAAAA==.Kitrel:BAAANQAECgMIAwAAAA==.',
Kl='Kleiio:BAAANQAECgEIAQAAAA==.Kllauzz:BAABNQAECn8cAAIBAAcKjw0ZLgCxAQABAAcKjw0ZLgCxAQABNQAECggIJQAYAOAMAA==.Kllauzzmage:BAAANQAECgIIAgABNQAECggIJQAYAOAMAA==.Kllauzzpalla:BAABNQAECn8lAAIYAAgK4AxMtACwAQAYAAgK4AxMtACwAQAAAA==.',
Kn='Knufolgado:BAAANQADCgYIBgAAAA==.',
Ko='Kolyn:BAABNQAECn89AAINAAkKFCS5DQBxAwANAAkKFCS5DQBxAwAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgYIEgAAAA==.Kreegh:BAAANQAECgEIAQAAAA==.Krikixus:BAAANQADCgYIBgAAAA==.Krupper:BAAANQAECgMIAwABNQAECgYIDAAIAAAAAA==.Krynesa:BAAANQADCggICwAAAA==.',
Ku='Kuhaku:BAAANQADCgQIBAAAAA==.Kukuatzo:BAAANQAECgUIDgAAAA==.',
Ky='Kyary:BAAANQAECgYIDAABNQAECgkJMQAgAMogAA==.Kyndin:BAAANQADCgEIAQABNQAFFAQICQANAOkjAA==.Kyrara:BAAANQAECgUIBQAAAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQAECgQIBAAIAAAAAA==.Käyros:BAAANQADCgUJCgAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAABNQAECn8bAAIPAAcKACMrLgDBAgAPAAcKACMrLgDBAgAAAA==.Köri:BAABNQAECn8eAAMCAAkKpx1BVwDRAgACAAkKPh1BVwDRAgAVAAEKMx2KPQBIAAAAAA==.',
La='Lakaioo:BAABNQAECn8eAAMaAAcKjwsJyABiAQAaAAcKjwsJyABiAQAhAAIKkAMtPwBAAAAAAA==.Lamiel:BAAANQAECgEIAQAAAA==.Lamont:BAABNQAECn8jAAIUAAcKkA+WfQCdAQAUAAcKkA+WfQCdAQAAAA==.Lampiião:BAABNQAECn8rAAINAAgKMxuFQACnAgANAAgKMxuFQACnAgAAAA==.Lanllaniel:BAAANQAECgcIDwAAAA==.Largartixa:BAAANQADCgQJBAABNQAECgQJBAAIAAAAAA==.Larslion:BAAANQABCgYJBgAAAA==.',
Le='Lebelisco:BAABNQAECn8XAAINAAgKfxxIUwB0AgANAAgKfxxIUwB0AgAAAA==.Leehyori:BAAANQAECgQICgAAAA==.Legëndaria:BAAANQAECgEIAQAAAA==.Lennorien:BAABNQAECn8nAAIWAAgKgBj+BwCAAgAWAAgKgBj+BwCAAgAAAA==.Lestard:BAAANQAECgUIBQAAAA==.Leturey:BAAANQADCgMIAwAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAABNQAECn8aAAMRAAgK5BJuIwB1AQARAAgKEw9uIwB1AQAZAAYKAQ6MGwBGAQAAAA==.Liftshertail:BAABNQAECn8pAAQdAAkKvBs0CwDvAgAdAAkKvBs0CwDvAgAkAAUKnwyDJQALAQAeAAIKawyzHwBbAAAAAA==.Ligiaf:BAAANQAECgUIEQAAAA==.Liilum:BAAANQAECgMIAwAAAA==.Limeware:BAAANQADCgYICAAAAA==.Linë:BAAANQADCggJHwABNQAECgQIBAAIAAAAAA==.Linëa:BAAANQADCgIIBQAAAA==.Linüss:BAAANQAECgEIAQAAAA==.Lionarot:BAAANQAECgUIEQAAAA==.Littleshelby:BAAANQADCgYJDwAAAA==.',
Lo='Lobinox:BAAANQADCggICgAAAA==.Lolzhe:BAAANQAECgYIBwABNQAECggIKAAiAFcaAA==.Longaim:BAABNQAECn8WAAINAAcKohKtlQDZAQANAAcKohKtlQDZAQAAAA==.Lorthaeron:BAABNQAECn8VAAIOAAgKARCvQAC+AQAOAAgKARCvQAC+AQAAAA==.Losdor:BAAANQAECgUIBgAAAA==.Lostminder:BAAANQAECgMIBAAAAA==.Lothbrok:BAABNQAECn8jAAINAAgKexhTZQBHAgANAAgKexhTZQBHAgAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAACNQAFFH8XAAIaAAcKtRhpBgBXAgAaAAcKthhpBgBXAgA1AAQKfycAAxoACQpPI/AnABgDABoACQqHIvAnABgDACAAAQrQIfUrAFIAAAAA.Lukanelas:BAAANQADCgcIDgAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luna:BAABNQAECn8bAAMSAAkK9huMIgDiAgASAAkKkxqMIgDiAgATAAQK/RNUEwDxAAAAAA==.Lunes:BAABNQAECn8wAAIMAAkKCx5ZGgAFAwAMAAkKCx5ZGgAFAwAAAA==.Lunna:BAAANQADCgcICAAAAA==.Luster:BAAANQADCggIEQAAAA==.Lusther:BAABNQAECn8WAAMUAAgKcQ1YbwDHAQAUAAgKcQ1YbwDHAQAFAAQKKReQQgDmAAAAAA==.Luzdacelesc:BAACNQAFFH8LAAIBAAUKvCQyBQDkAQABAAUKvCQyBQDkAQA1AAQKf0QAAwEACQqhJl8AAP4DAAEACQqhJl8AAP4DABIAAgp4DRPfAIMAAAAA.',
Ly='Lyaah:BAAANQADCggIGQAAAA==.Lyeer:BAAANQADCgIIAgAAAA==.',
['Lë']='Lënori:BAAANQAECgEIAQAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYICwABNQAECggIKAAiAFcaAA==.',
['Lø']='Lølzhê:BAABNQAECn8oAAIiAAgKVxokFQAlAgAiAAgKVxokFQAlAgAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQAECgQIBwAAAA==.',
Ma='Maagnuss:BAAANQADCgIIAgAAAA==.Madbuddha:BAAANQADCggIDAAAAA==.Mageli:BAABNQAECn8UAAICAAcKfhIt2ADUAQACAAcKfhIt2ADUAQAAAA==.Magodanilo:BAAANQAECgIIAgAAAA==.Magodavida:BAABNQAECn8WAAISAAYKIQ4ElgBOAQASAAYKIQ4ElgBOAQAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maguinax:BAAANQAECgEIAwABNQAFFAMICAAEADwVAA==.Maheena:BAAANQAECgcIEgAAAA==.Mai:BAABNQAECn8eAAMbAAgK2w9UAwDGAQAbAAcKpBFUAwDGAQACAAUK7ARLaQHiAAAAAA==.Mairon:BAAANQADCgcICQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAABNQAECn8eAAIXAAgKiRAkVQCcAQAXAAgKiRAkVQCcAQAAAA==.Malborion:BAAANQAECgUIEAAAAA==.Malevolent:BAAANQAECgcIDwAAAA==.Malignõ:BAABNQAECn8tAAIPAAkKOSWACACiAwAPAAkKOSWACACiAwAAAA==.Mallphite:BAAANQAECgEIAQAAAA==.Malluria:BAAANQADCgYIBgAAAA==.Maltozo:BAABNQAECn8ZAAIOAAgK7wsrTwBwAQAOAAgK7wsrTwBwAQAAAA==.Mandrakson:BAABNQAECn8eAAIOAAkKxQplQADAAQAOAAkKxQplQADAAQAAAA==.Mandubim:BAAANQADCgUIBgAAAA==.Mariiamil:BAAANQAECgUIEAAAAA==.Marvelos:BAAANQABCggJCgAAAA==.Marvvila:BAABNQAECn8gAAMNAAgKmRnbUwBzAgANAAgKmRnbUwBzAgAcAAEK5QaSjAAxAAAAAA==.Marycristiny:BAABNQAECn8cAAMWAAkKGBeUBgChAgAWAAgKxRmUBgChAgAjAAEKDgeXRwEsAAAAAA==.Mauwolf:BAAANQAECgQIBQAAAA==.Mazaky:BAABNQAECn8dAAISAAcKuAsQkABhAQASAAcKuAsQkABhAQAAAA==.',
Me='Medivi:BAAANQADCgMIAwAAAA==.Megumi:BAAANQAECgMIAwAAAA==.Meisterz:BAAANQADCgQIBAABNQAECggIKAAJAPQfAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAABNQAECn8lAAIiAAkKLxq1DwCAAgAiAAkKLxq1DwCAAgAAAA==.Mestredoido:BAAANQAECgQICQAAAA==.Mestreløck:BAAANQADCgMICQAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.Meuhomen:BAAANQAECgMIAwABNQAECgkJKQANAM8dAA==.',
Mh='Mhenb:BAAANQAECggIEgAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Micherouc:BAAANQADCggIDgAAAA==.Midnights:BAAANQADCgUIBQAAAA==.Mierket:BAAANQADCgUIBQAAAA==.Mikal:BAABNQAECn8YAAINAAcKExLdiQDzAQANAAcKExLdiQDzAQAAAA==.Miniime:BAAANQADCgQIBAAAAA==.Minort:BAAANQAECgUIEQAAAA==.Minör:BAAANQAECgQIBwAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mistogunn:BAAANQAECgIIBgAAAA==.Mithrael:BAAANQADCgUIBQAAAA==.Mizukagesou:BAAANQAECgQIDwAAAA==.',
Mo='Monkbest:BAAANQADCggIEwAAAA==.Montedruids:BAAANQADCgEIAQAAAA==.Montej:BAAANQAECgMIBAAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAABNQAECn8bAAIQAAgKIxMdPgAEAgAQAAgKIxMdPgAEAgAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgQIBAABNQAECgYIFgAFAN0OAA==.Moranguinhö:BAAANQADCgEJAQAAAA==.Mordiidinha:BAAANQAECgQIBwABNQAECgkJLQAPADklAA==.Morganviolet:BAABNQAECn8dAAIOAAcKnA3CSwCDAQAOAAcKnA3CSwCDAQAAAA==.',
Mu='Mugidinhaa:BAAANQABCgcIBQAAAA==.Murdoky:BAAANQADCgEIAQABNQAECgMIBAAIAAAAAA==.Musleira:BAAANQAECgYIEgAAAA==.',
My='Myranor:BAAANQAECgUIBwAAAA==.Myrzin:BAAANQADCggIDAAAAA==.Mythariel:BAAANQAECgQIBgAAAA==.Mythcut:BAAANQAECgQIDAAAAA==.Mythjegue:BAAANQAECgEIAQAAAA==.Myø:BAAANQAECgYIBgABNQAFFAQIBwAcAGIUAA==.',
['Mä']='Mällü:BAAANQAECgYIEwAAAA==.Mälthazar:BAABNQAECn8oAAMFAAkK+x6oCAASAwAFAAkK+x6oCAASAwAYAAMK+BjHHAHoAAAAAA==.Määt:BAAANQADCggICAABNQAFFAYIEwAjAKMYAA==.',
['Må']='Mågus:BAABNQAECn8eAAIVAAgKVxqCCABUAgAVAAgKVxqCCABUAgAAAA==.',
['Mò']='Mòrgan:BAAANQAECgEIAQAAAA==.',
['Mø']='Mørgåna:BAAANQAECgYIEQAAAA==.',
Na='Naamt:BAAANQADCgYIBgAAAA==.Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQADCgYICgABNQAECgQICAAIAAAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgYIDwAAAA==.Namisan:BAAANQAECgIIAwAAAA==.Namuhß:BAAANQAECgQIEAABNQAECggIFwALAEAPAA==.Namøøh:BAABNQAECn8XAAMLAAgKQA/TLQCoAQALAAgKQA/TLQCoAQAQAAQK2A1RfwDMAAAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQIDQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Nardalan:BAAANQADCgQJBAABNQAECgUICgAIAAAAAA==.Narjes:BAAANQAECgYICQAAAA==.Nathrezim:BAAANQADCgcIEAAAAA==.Nathÿ:BAAANQADCgIIAgAAAA==.',
Ne='Necrogélido:BAAANQADCgYIEwAAAA==.Nefariio:BAAANQADCgQIBAAAAA==.Neninhaa:BAAANQADCgcJBQAAAA==.Neopaladino:BAAANQAECgQICQAAAA==.Nerlock:BAAANQAECgUIEQAAAA==.',
Ni='Nicom:BAAANQADCgYIBgAAAA==.Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAABNQAECn8kAAIHAAkK+RqbHACxAgAHAAkK+RqbHACxAgAAAA==.',
No='Noahwallker:BAAANQADCgYIBgAAAA==.Noazard:BAAANQAECgQIDAAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Normalin:BAAANQADCgEIAQAAAA==.Nortênho:BAABNQAECn8hAAIQAAkKLx85FAAkAwAQAAkKLx85FAAkAwAAAA==.Nosferüs:BAAANQAECgQIBwAAAA==.Nossilat:BAABNQAECn8xAAIHAAkKdCW+AgDHAwAHAAkKdCW+AgDHAwAAAA==.',
Nu='Nuit:BAAANQAECgMICAAAAA==.',
Ny='Nysthiael:BAABNQAECn8tAAMjAAgKQhy6TwBiAgAjAAgKQhy6TwBiAgAlAAEKAAC3MwAqAAAAAA==.Nyxicel:BAAANQAECgUICwABNQAECgkJJAAEAJofAA==.',
['Nã']='Nãoseicurar:BAAANQAECgUIBwAAAA==.',
['Nä']='Närem:BAAANQAECggIAQAAAA==.Nästÿ:BAAANQAECgUIBgAAAA==.',
['Ní']='Níih:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgUIEAAAAA==.',
Oc='Ocon:BAAANQABCgIIBAAAAA==.',
Od='Odigo:BAAANQADCgIIAgAAAA==.Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCggILQAAAA==.',
Ol='Oldcook:BAAANQABCgYIBQAAAA==.Oliele:BAAANQAECgUIDAAAAA==.',
On='Onixpala:BAAANQAECgQIBwABNQAECgUIEwAIAAAAAA==.Onlydruix:BAAANQADCgIIAgAAAA==.',
Oo='Oorun:BAAANQADCgcIBwAAAA==.',
Op='Opsdesculpa:BAABNQAECn8cAAMKAAgKvRRIMQAVAgAKAAgKvRRIMQAVAgAmAAEKEBF8TwA9AAAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAABNQAECn8kAAICAAkKYiLQRAD6AgACAAkKYiLQRAD6AgAAAA==.',
Os='Osiria:BAAANQABCgYICAAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgYICwABNQAECgkJMgAWAM0XAA==.Otávio:BAAANQAECgUICAAAAA==.',
Ow='Owlcapøne:BAAANQAECgUIBQAAAA==.',
Ox='Oxentedragon:BAAANQADCgUIBAAAAA==.',
Oz='Ozyi:BAABNQAECn8aAAIUAAgKKBcgTwAsAgAUAAgKKBcgTwAsAgAAAA==.',
Pa='Pachiinko:BAAANQAECgYJAgAAAA==.Pain:BAAANQADCgQIBAAAAA==.Painkke:BAAANQAECggIEAAAAA==.Pajeh:BAAANQADCgYIBwAAAA==.Pallacetamal:BAAANQAECgUIBQAAAA==.Palluz:BAAANQAECgUICAABNQAFFAMIBgANAMUSAA==.Palyz:BAAANQADCggIDwAAAA==.Pandaphorte:BAAANQADCgQIBAABNQAECgQIBgAIAAAAAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Panteão:BAAANQADCgcIBwAAAA==.Parafinaisis:BAABNQAECn8XAAILAAcKIAlAPAA7AQALAAcKIAlAPAA7AQAAAA==.Parafinared:BAAANQAECgQICAAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.Paupacino:BAAANQADCgUIBQAAAA==.',
Pe='Pedrosolock:BAAANQADCgYICQAAAA==.Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQAECgQIBAAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgYIDQAIAAAAAA==.Pesaa:BAABNQAECn8pAAIaAAkKZSDSJAAjAwAaAAkKZSDSJAAjAwAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Pirizin:BAABNQAECn8wAAIYAAkKcRp6WACKAgAYAAkKcRp6WACKAgAAAA==.Pirus:BAAANQADCgUICgAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAABNQAECn8dAAIBAAgKRRJnKQDZAQABAAgKRRJnKQDZAQAAAA==.Portal:BAAANQAECgUICgAAAA==.Portelamage:BAABNQAECn8qAAICAAkKKx/7RQD3AgACAAkKKx/7RQD3AgAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAABNQAECn8vAAMPAAgKzBcIUQAxAgAPAAgKzBcIUQAxAgAMAAIK/ACuHAEvAAAAAA==.Pravuls:BAAANQAECgEIAQAAAA==.Priapista:BAAANQAECgQIBQAAAA==.Priyla:BAAANQABCgcICgAAAA==.Prosaic:BAAANQADCggICAABNQADCggJDwAIAAAAAA==.Pråhå:BAAANQAECgQICQABNQAECggIFwALAEAPAA==.',
Ps='Psicopanda:BAAANQAECgcIEAAAAA==.Psychiclink:BAABNQAECn8WAAIBAAkKrSDjCABMAwABAAkKrSDjCABMAwABNQAFFAUICwABALwkAA==.',
Pu='Puffys:BAAANQAECgEIAQABNQAECgYICwAIAAAAAA==.',
Pw='Pwcca:BAAANQAECgEJAQAAAA==.',
['Pó']='Pórthosrox:BAAANQAECgEIAgAAAA==.',
['Pú']='Púh:BAAANQADCgQIBAABNQAECggIKAAJAPQfAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAABNQAECn8sAAIgAAgKsiBcBQDMAgAgAAgKsiBcBQDMAgAAAA==.Raewyn:BAABNQAECn8eAAIOAAkKZBopGgC2AgAOAAkKZBopGgC2AgAAAA==.Rafaelgame:BAAANQAECgQICAAAAA==.Ragdead:BAACNQAFFH8FAAIXAAIKoA3vIwBrAAAXAAIKoA3vIwBrAAA1AAQKfyIAAhcACQqeG2wzAD0CABcACQqeG2wzAD0CAAE1AAUUBAgEAAgAAAAA.Ragdöll:BAAANQAECgQIBQAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAFFAQIBAAIAAAAAA==.Ragosan:BAAANQAFFAQIBAAAAA==.Rairone:BAABNQAECn8YAAInAAgK3A0uBwAKAgAnAAgK3A0uBwAKAgAAAA==.Raparigaloka:BAAANQAECgUIDwAAAA==.Rapunxel:BAABNQAECn8yAAMWAAkKzReiBADcAgAWAAkKzReiBADcAgAjAAUKjwhV5wD1AAAAAA==.Rarkion:BAABNQAECn8kAAMkAAkKABy4BgAaAwAkAAkKABy4BgAaAwAdAAMKpRZUNgDeAAAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Rawrii:BAAANQADCgUIBQAAAA==.Raynmake:BAAANQAECgEIAQABNQAECgcIBwAIAAAAAA==.',
Rb='Rbchama:BAABNQAECn8YAAMPAAUKYwZS0gDrAAAPAAUKYwZS0gDrAAAMAAEKTwBmNQEVAAAAAA==.',
Re='Rebelk:BAAANQAECgEIAQAAAA==.Redvil:BAAANQADCgUJBwAAAA==.Revoltedhunt:BAAANQAECggICwABNQAFFAcIGgAcAHsSAA==.Revolthed:BAACNQAFFH8aAAMcAAcKexLxBgDcAQAcAAYK3BXxBgDcAQANAAQKeA2qFAAVAQA1AAQKfyoAAxwACQo9IysNAAkDABwACQoYIysNAAkDAA0ABQrnGMW1AJQBAAAA.Reygon:BAAANQADCggICwAAAA==.',
Rh='Rhaadora:BAAANQAECgQIBAAAAA==.Rhoghar:BAABNQAECn8kAAMHAAkK8BwWGADXAgAHAAkK8BwWGADXAgADAAgKZRjBCQBCAgAAAA==.Rhoghardruid:BAAANQAECgYICgABNQAECgkJJAAHAPAcAA==.',
Ri='Riachu:BAAANQADCgcIBwAAAA==.Riluyu:BAAANQAECgUIBQAAAA==.Rimetail:BAAANQABCgQIBAAAAA==.',
Ro='Rokalf:BAABNQAECn8gAAIhAAgKhBNIFgDBAQAhAAgKhBNIFgDBAQAAAA==.Rossiten:BAABNQAECn8YAAICAAcKexkiwwD8AQACAAcKexkiwwD8AQAAAA==.Roverandom:BAAANQADCgEIAQAAAA==.Roöf:BAAANQAECgUIEQAAAA==.',
Ru='Rubya:BAAANQAECgEJAQABNQAECgcIEwAIAAAAAA==.Runavento:BAAANQADCgIIAgAAAA==.Ruélatórta:BAAANQAECgQICAAAAA==.',
['Rä']='Räidela:BAABNQAECn85AAMjAAgKciADMADEAgAjAAgKciADMADEAgAWAAEK2hJmdAA5AAAAAA==.',
Sa='Sagman:BAAANQAECgEIAQAAAA==.Sagädegemeos:BAABNQAECn8eAAIYAAcKFhpVgQAhAgAYAAcKFhpVgQAhAgABNQAECgkJIwANAOAcAA==.Salasär:BAABNQAECn8hAAIaAAgKVx4wVwCCAgAaAAgKVx4wVwCCAgABNQAECggIIgANAH0fAA==.Saleyi:BAAANQAECgYIDwAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQAECgYICwAAAA==.Sarashi:BAAANQADCgUIDAAAAA==.Sarte:BAAANQAECgQIBgAAAA==.Sarzlok:BAAANQAECgUIBgAAAA==.',
Sc='Schaeppi:BAAANQAECgEIAQAAAA==.Schiabelle:BAAANQADCggIFAAAAA==.Schiabellee:BAAANQADCggIEQAAAA==.Scoobydruida:BAABNQAECn8fAAIQAAkKShLEMwBFAgAQAAkKShLEMwBFAgAAAA==.Screan:BAABNQAECn8pAAIBAAkKhBQVHQBXAgABAAkKhBQVHQBXAgAAAA==.Scrøøge:BAAANQAECgQICgAAAA==.',
Se='Sealgaire:BAAANQADCgYICAAAAA==.Seelyvorey:BAABNQAECn81AAQOAAgKkiQ6GwCuAgAOAAgKBSM6GwCuAgAEAAcKJyT3JgCdAgAXAAUKdhZucQAsAQAAAA==.Selph:BAABNQAECn8WAAIFAAkKEhtoEACVAgAFAAkKEhtoEACVAgAAAA==.Sengos:BAAANQAECgQIBQAAAA==.Sens:BAAANQADCgIIAgAAAA==.Sephhiroth:BAAANQADCgcICgAAAA==.Serrase:BAABNQAECn8jAAICAAkKCxqpagCpAgACAAkKCxqpagCpAgAAAA==.',
Sh='Shaado:BAAANQAECgQIBgAAAA==.Shadowwlock:BAAANQAFFAIIAgAAAA==.Shagy:BAAANQAECgMIAwAAAA==.Shaldorei:BAAANQADCgUIBQAAAA==.Shalivane:BAAANQAECggIDwAAAA==.Shalquoir:BAAANQAECgcICAABNQAECgkJKQAdALwbAA==.Sharckaron:BAAANQAECgUIEAAAAA==.Shedleass:BAABNQAECn8bAAIDAAgKrxh8CgAuAgADAAgKrxh8CgAuAgAAAA==.Shendalar:BAABNQAECn84AAMCAAgKxRmAjQBkAgACAAgKxRmAjQBkAgAbAAMKvgQvCQB1AAAAAA==.Shigami:BAAANQADCgcIBwAAAA==.Shigare:BAAANQAECgEIAQAAAA==.Shuräto:BAAANQAECgMIAwAAAA==.Shywa:BAAANQADCgQIBgAAAA==.Shërëkhan:BAAANQAECgEIAQAAAA==.Shîvas:BAAANQAECgYICQAAAA==.Shöstakövich:BAAANQABCgEIAQAAAA==.Shøtinha:BAABNQAECn8rAAMcAAkK8R5rEwDEAgAcAAgK8R5rEwDEAgANAAMK+xmZDAHmAAAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECgcIIgAQAKsbAA==.',
Si='Sianus:BAAANQAECgIJBAAAAA==.Sicarious:BAAANQADCgYICwABNQAECgkJIgAYAAYUAA==.Sicariuz:BAABNQAECn8iAAIYAAkKBhSxfAAsAgAYAAkKBhSxfAAsAgAAAA==.Silara:BAAANQADCgYICQAAAA==.Silves:BAAANQABCgYICgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQAECgYIBgABNQAECgkJLwAJACQjAA==.',
Sm='Smarcão:BAAANQAECgcIBwAAAA==.',
Sn='Snipinho:BAAANQAECgcIEwAAAA==.Snowtail:BAAANQAECgQIDQAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAABNQAECn8XAAICAAkKAAQj/QCQAQACAAkKAAQj/QCQAQAAAA==.Solidheals:BAAANQAECgIIBgAAAA==.Sougigante:BAAANQAECgQIDAAAAA==.Souillé:BAAANQAECgYIBgABNQAFFAUIDAAHAB8cAA==.Soulbinder:BAAANQADCgIJAgAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.Sovaco:BAAANQAECgUIBQAAAA==.',
Sp='Spelldruid:BAAANQADCggIDQAAAA==.Spellshadown:BAABNQAECn8rAAIjAAkK/RcJPQCZAgAjAAkK/RcJPQCZAgAAAA==.Spellshamy:BAAANQAECggIDgAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQAECgMIAwAAAA==.',
Ss='Sshar:BAAANQADCgYIBgAAAA==.',
St='Stalinbrs:BAAANQAECgEIAQABNQAECgcIHgAXANEcAA==.Stalindinho:BAAANQAECgcIDQAAAA==.Stanyzz:BAAANQAECgIIAgABNQAECgkJGgAQAPMXAA==.Stelluna:BAAANQAECgMIAwAAAA==.Stormimrage:BAAANQAECgQICQAAAA==.Strexx:BAAANQAECgYIDwAAAA==.Stronoffgard:BAABNQAECn8kAAIaAAgKqB4cUgCQAgAaAAgKqB4cUgCQAgAAAA==.Stronq:BAAANQADCggIFgAAAA==.',
Su='Sulfur:BAAANQAECgIIBAAAAA==.Surionn:BAAANQADCgcIBwAAAA==.',
['Sà']='Sàgadegemeos:BAABNQAECn8jAAMNAAkK4BzXSACQAgANAAcK/SDXSACQAgAcAAQKXBJdTAD9AAAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQAECggIGQAjAHkXAA==.',
Ta='Tacka:BAAANQAECgEIAQAAAA==.Tafoki:BAABNQAECn8oAAMJAAgK9B+kCgDFAgAJAAgK9B+kCgDFAgAPAAIKFhMo+ACcAAAAAA==.Taloco:BAAANQAECgUIBQAAAA==.Tanakin:BAAANQAECgUICgABNQAECgkJMQAgAMogAA==.Tangdebanana:BAAANQAECgUICQABNQAECgkJJAAcAKUeAA==.Tankairotty:BAAANQAECgQIBQAAAA==.Tanrity:BAAANQAECgcIEwAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAAANQAECgUIEgAAAA==.',
Te='Temeloorego:BAAANQAECgMIAwAAAA==.Temkutemmedo:BAAANQAECgIIBQABNQAECgMIAwAIAAAAAA==.Tennkkar:BAAANQAECgEIAQAAAA==.Texugojogatv:BAABNQAECn8dAAICAAkKmhWYdQCSAgACAAkKmhWYdQCSAgAAAA==.Texugosa:BAAANQAECgEJAQAAAA==.',
Th='Thaeeria:BAAANQAECggICAAAAA==.Thamihime:BAABNQAECn8kAAINAAcKAhIcjQDsAQANAAcKAhIcjQDsAQAAAA==.Tharizdum:BAAANQAECgQICgAAAA==.Theedarknes:BAAANQADCgQIBAAAAA==.Thlrall:BAAANQAECgEIAgABNQAECgEIBgAIAAAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAACNQAFFH8GAAIgAAQKohkUAQBqAQAgAAQKohkUAQBqAQA1AAQKfxwAAiAACAoXItIFALoCACAACAoXItIFALoCAAAA.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thunderburp:BAAANQAECgUIBQABNQAECggIJQAWAG8kAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.Thânatos:BAAANQADCgIIAgAAAA==.',
Ti='Tiadobil:BAAANQAECggIEAAAAA==.',
To='Toni:BAAANQAECgUIEAAAAA==.Toshyo:BAAANQAECggIEAAAAA==.Tostão:BAAANQADCgUICwAAAA==.Touchhme:BAAANQAECgIIAgAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQAIAAAAAA==.Toykiller:BAAANQADCgYIDQAAAA==.',
Tp='Tprdmage:BAABNQAECn8XAAICAAQKRRMcUwEBAQACAAQKRRMcUwEBAQAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgYICQAAAA==.Triixie:BAAANQAECgEIAQABNQAECgQIBwAIAAAAAA==.Trolhöl:BAAANQAECgcJEwAAAA==.Trollrogue:BAAANQAECgUIEQAAAA==.Trosobado:BAAANQAECgQICAAAAA==.Troyana:BAAANQADCggICAABNQAFFAYIFAAaAH8bAA==.',
Tu='Tukiel:BAAANQAECgcICQAAAA==.Tunkav:BAAANQABCgYJCQAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAABNQAECn8ZAAMLAAcKzRRcKgDHAQALAAcKzRRcKgDHAQAQAAIKYQlZnwBbAAABNQAECgkJIwAdAOIVAA==.Typol:BAABNQAECn8hAAIVAAYKcQ5cFwA+AQAVAAYKcQ5cFwA+AQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAABNQAECn8dAAIMAAgK+Bc2TAAwAgAMAAgK+Bc2TAAwAgAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQAIAAAAAA==.Umehara:BAACNQAFFH8PAAMcAAUKxRaBCwCCAQAcAAUKxRaBCwCCAQANAAEKAAAHNwBLAAA1AAQKfzUAAxwACQpXIqQHAFUDABwACQoGIqQHAFUDAA0AAQotHElAAVYAAAAA.Umokh:BAABNQAECn8xAAIgAAkKyiDWAQBzAwAgAAkKyiDWAQBzAwAAAA==.Umterço:BAAANQADCgcICwAAAA==.',
Un='Unbrøken:BAAANQAECgMIBgAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgcIEAAIAAAAAA==.',
Uo='Uolokoelfo:BAABNQAECn8rAAIaAAgKYiBJSwCkAgAaAAgKYiBJSwCkAgAAAA==.',
Ur='Urannia:BAABNQAECn8oAAINAAgKbRZmZgBFAgANAAgKbRZmZgBFAgAAAA==.Urgath:BAAANQAECgYIEQAAAA==.',
Ut='Uther:BAAANQAECgQICQABNQAECgkJMwAVAGMTAA==.',
Va='Valan:BAAANQAECgEIAgAAAA==.Valdeco:BAAANQADCggIDAAAAA==.Valdevino:BAABNQAECn8nAAISAAkK1BDcUgAnAgASAAkK1BDcUgAnAgAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vatoo:BAAANQADCgEIAQAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAABNQAECn8kAAQcAAkKpR5LFQCxAgAcAAkKoRtLFQCxAgANAAUKwCF0nwDDAQAnAAMKMx5jDAAPAQAAAA==.Venonpoison:BAAANQADCgMIAgAAAA==.Vermeryn:BAAANQAECgUIDQAAAA==.Vermithór:BAAANQAECgMIBwAAAA==.',
Vi='Viciadø:BAAANQAECgYICQABNQAFFAQIBwAcAGIUAA==.Villalobos:BAAANQAECgcIDQAAAA==.Vits:BAABNQAECn8eAAMNAAgKYRnwUAB6AgANAAcKsh3wUAB6AgAcAAQK1wciWgC4AAAAAA==.',
Vo='Voidsurge:BAAANQAECgUIDwAAAA==.Voidwar:BAAANQAECgIIAgABNQAECgUIDwAIAAAAAA==.Vollin:BAABNQAECn8ZAAQmAAgK4g6dHADrAQAmAAgK4g6dHADrAQAKAAIKEgMclQBSAAAoAAEKAADcHAArAAAAAA==.Volrun:BAAANQADCggIDAAAAA==.Voragem:BAAANQAECgcIDgAAAA==.Vougam:BAAANQAECgIIAgAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.Vultures:BAAANQADCgQICAAAAA==.',
Wa='Warlockdoido:BAAANQAECgQIBQAAAA==.Warlôka:BAAANQADCgUIBQAAAA==.Warriorbeso:BAAANQADCgIIAgAAAA==.',
Wi='Wiillord:BAAANQAECgQICAAAAA==.Willbm:BAABNQAECn80AAMYAAgKMw7lswCxAQAYAAgK6g3lswCxAQAFAAYKawxiPwD5AAAAAA==.Winnettou:BAABNQAECn8UAAIYAAgKJwUK6gBBAQAYAAgKJwUK6gBBAQAAAA==.Wipalogo:BAAANQAECgMIAwAAAA==.Wise:BAABNQAECn8rAAIYAAgKESN6KwAXAwAYAAgKESN6KwAXAwAAAA==.',
Wm='Wmana:BAABNQAECn8UAAICAAQKDxVdTwEHAQACAAQKDxVdTwEHAQAAAA==.',
Wr='Wrathi:BAAANQAECgMIAgAAAA==.',
Wu='Wuan:BAABNQAECn8hAAMfAAgKrRmlHgA5AgAfAAgKrRmlHgA5AgAiAAQKPQ9pMwDKAAAAAA==.',
Xa='Xamanico:BAAANQAECgQICQAAAA==.Xanasmanas:BAAANQAECgcIEgAAAA==.Xazon:BAAANQADCgUIBwAAAA==.',
Xh='Xharlios:BAAANQAECgUICgAAAA==.',
Xi='Xingorila:BAAANQADCgQIBAAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgUICAAAAA==.Xxnicoxx:BAAANQADCggIEQAAAA==.',
Xy='Xymor:BAACNQAFFH8SAAQkAAUK0A5nBQBnAQAkAAUK0A5nBQBnAQAeAAEKAABYDABGAAAdAAEKHwKRGQA5AAA1AAQKfycAAyQACQrQIboHAAEDACQACQrQIboHAAEDAB0AAQrlApdQACoAAAE1AAQKBggIAAgAAAAA.Xyuwan:BAAANQADCgUIBQAAAA==.',
['Xä']='Xäm:BAAANQAECgEIAQAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Ye='Yenniferxd:BAAANQABCgUIBQAAAA==.',
Yl='Ylanna:BAABNQAECn8ZAAQTAAkKyxEXCQDJAQATAAcKAxUXCQDJAQABAAIK0wUEZwBgAAASAAEKEAbB9QA6AAAAAA==.',
Yn='Ynit:BAAANQAECgQICwAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoodoo:BAAANQABCgUJBQAAAA==.Yoriko:BAAANQAECgYICAAAAA==.Yorú:BAABNQAECn8hAAIYAAgKvRoSaABfAgAYAAgKvRoSaABfAgAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQAECgEIAQAAAA==.',
Za='Zambrotta:BAAANQADCgYIBgAAAA==.Zamii:BAAANQAECgQIBgABNQAECgcIGAANAPEhAA==.Zarik:BAAANQADCgcIBwAAAA==.',
Ze='Zenolis:BAAANQADCgcJFAAAAA==.Zerathir:BAAANQAECgQICgAAAA==.',
Zh='Zhalazar:BAAANQAECgUIDAAAAA==.Zhenb:BAAANQAECgIIAgAAAA==.',
Zi='Zigosmar:BAAANQAECgEJAQAAAA==.',
Zo='Zoleiman:BAAANQADCggICAAAAA==.Zolet:BAAANQAECgMIBAAAAA==.Zones:BAAANQAECgQIBwABNQAECggIHQAMAPgXAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Ág']='Ágripa:BAAANQABCgYIBgAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQAECgUIDgAAAA==.Änä:BAAANQADCggIDgAAAA==.',
['Är']='Ärthås:BAAANQAECgUICQAAAA==.',
['Äz']='Äzra:BAAANQAECgEIAgAAAA==.',
['Ær']='Ærikão:BAABNQAECn8UAAIaAAcKehiLjwDxAQAaAAcKehiLjwDxAQAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQAECgEIAQAAAA==.',
['Ðr']='Ðrakko:BAAANQADCgQICAAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Ör']='Örigem:BAAANQAECgcIDwAAAA==.',
['ßa']='ßardeolitico:BAAANQAECgEIAQABNQAECgcIHwAYAK0WAA==.',
['ßl']='ßlåkehunter:BAAANQAECgEIAQAAAA==.',
['ßr']='ßradvi:BAAANQADCggIDgAAAA==.ßrutalßarbie:BAAANQADCgYIBgAAAA==.',
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
