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

local lookup = {'Priest-Shadow','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Unholy','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','Shaman-Restoration','Hunter-BeastMastery','Druid-Balance','DeathKnight-Frost','Shaman-Elemental','Druid-Guardian','Priest-Holy','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Mage-Frost','Warlock-Destruction','Druid-Feral','Warrior-Arms','Mage-Fire','Warlock-Affliction','Warlock-Demonology','Hunter-Marksmanship','Evoker-Preservation','Evoker-Augmentation','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warrior-Protection','DeathKnight-Blood','Evoker-Devastation','Hunter-Survival','Shaman-Any','Rogue-Outlaw',}
local provider = {region='US',realm='Nemesis',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abyssdk:BAAANQAECgEIAQABNQAFFAUIDAABALwkAA==.Abyssfurry:BAAANQADCggICAABNQAFFAUIDAABALwkAA==.',
Ac='Acadêmica:BAABNQAECn9HAAICAAoKfhYjBwBbAgACAAoKfhYjBwBbAgAAAA==.Acnaya:BAAANQADCgQIBAAAAA==.',
Ad='Adcosmos:BAAANQAECgYIBQABNQAECgkJHgADAJwXAA==.Adebaio:BAACNQAFFH8KAAIEAAUKWhbwEgDeAAAEAAUKWhbwEgDeAAA1AAQKfzsAAgQACgpZI70HAIYDAAQACgpZI70HAIYDAAAA.',
Ae='Aegenwullf:BAAANQADCgIIAgAAAA==.Aegislashh:BAABNQAECn8fAAIFAAcKyAv2MQBRAQAFAAcKyAv2MQBRAQAAAA==.Aerlath:BAACNQAFFH8YAAIGAAcKSR1DBAAAAgAGAAcKSR1DBAAAAgA1AAQKfzIAAgYACgoIJcUDAJsDAAYACgoIJcUDAJsDAAAA.Aetulia:BAABNQAECn8hAAMHAAgKnw20PwC/AQAHAAgKnw20PwC/AQAGAAUKDQUMHwC3AAAAAA==.',
Af='Afixo:BAAANQADCgQIBAABNQAECgQIBQAIAAAAAA==.',
Ag='Aggroster:BAAANQAECgUIBQAAAA==.Agnestesia:BAAANQAECgQIBwAAAA==.',
Ah='Ahkanos:BAAANQADCgcIBwAAAA==.Ahrathor:BAAANQAECgYIAwAAAA==.Ahyeon:BAAANQAECgMIAwAAAA==.',
Ak='Akasta:BAABNQAECn85AAIJAAcKziABEABpAgAJAAcKziABEABpAgAAAA==.Akkiralock:BAAANQADCgYIBgAAAA==.Akâme:BAABNQAECn8cAAMKAAoKJR7QCwApAwAKAAkK9h7QCwApAwALAAEKbRjrRQBNAAABNQAFFAQICAAMAFIVAA==.',
Al='Alascayoung:BAAANQAECgEIBAAAAA==.Alatroz:BAAANQADCgIIAgAAAA==.Alatrëon:BAAANQAECgYICwABNQAECggIHQANAPgXAA==.Aldrathion:BAAANQAECgEIAQABNQAECgoKRgAOAAskAA==.Aledk:BAAANQAECgYICAAAAA==.Alessan:BAAANQADCggIDwAAAA==.Alessary:BAAANQADCgYIBwAAAA==.Alfurieb:BAABNQAECn8WAAIPAAYKNAwxJgDNAAAPAAYKNAwxJgDNAAAAAA==.Alianar:BAAANQADCgMIAwAAAA==.Alicel:BAACNQAFFH8HAAIEAAMKMBJ4AwDbAAAEAAMKMBJ4AwDbAAA1AAQKfyUAAwQACgrvHpgZAPMCAAQACgrvHpgZAPMCABAAAQp+EcKtADQAAAAA.Altreir:BAAANQADCgcIFAABNQAECgQIBQAIAAAAAA==.Aluny:BAAANQAECgYICAABNQAFFAUICAARACIJAA==.Aluxxious:BAAANQAECgQICQAAAA==.Alëcream:BAAANQAECggIDwAAAA==.Alíne:BAAANQAECgYIEAAAAA==.',
Am='Amrb:BAAANQADCgIIAgAAAA==.Amyzu:BAAANQADCgYICQAAAA==.Amøm:BAABNQAECn8WAAMDAAYKShPeFABfAQADAAYKShPeFABfAQAHAAEKQwfpkgA1AAAAAA==.',
An='Anadirtei:BAAANQAFFAcIAQAAAA==.Anduinwill:BAAANQAECgEIAQAAAA==.Andärilho:BAAANQAECgQICQABNQAECggIGQABAKMOAA==.Ankados:BAACNQAFFH8JAAMPAAQKpgc8HAC4AAAPAAMKlQc8HAC4AAAMAAEK4gLPFwA8AAA1AAQKfx0ABAwACgpBEB9BAB4BAAwABQpLDx9BAB4BAA8ABwqZGTAhAOYAABIAAQoAAD5gADQAAAAA.Ankapos:BAABNQAECn8ZAAQTAAkKeAw2OwAYAQATAAkKeAw2OwAYAQABAAEKNweTfgAtAAAUAAEKFgG8MwAWAAAAAA==.Annish:BAAANQADCgYJCwAAAA==.Anrond:BAAANQAECgUIBQAAAA==.Anthorforged:BAABNQAECn8gAAMVAAgKhhXKHAB6AQAVAAgKhhXKHAB6AQAWAAEKAAMuAQEvAAAAAA==.Anwvar:BAAANQADCgIIAgAAAA==.Anãozé:BAAANQADCgIIAgAAAA==.',
Ap='Apocalipse:BAABNQAECn82AAIXAAoKiBdBBgCgAgAXAAoKiBdBBgCgAgAAAA==.',
Aq='Aquillez:BAAANQAECgQJBAAAAA==.',
Ar='Araurz:BAAANQAECgUICgABNQAECgoKJQACAJIPAA==.Arinn:BAABNQAECn8YAAIYAAcKYgxRGwCSAQAYAAcKYgxRGwCSAQAAAA==.Arkcirce:BAAANQAECgcIEgAAAA==.Arkdemias:BAAANQAECgUICAABNQAECgYIEwAIAAAAAA==.Arkw:BAAANQAECgYIBgAAAA==.Arnaldinho:BAAANQADCgQICAABNQAECgkJFgANAGcjAA==.Arthalan:BAAANQAECgIIAwAAAA==.Arthega:BAAANQAECgMIBgABNQAFFAcIGAAGAEkdAA==.Artoriös:BAAANQAECgMIBgABNQAECggIGAAVAHENAA==.Artradian:BAAANQAECgQIBgAAAA==.Arucàrd:BAAANQADCgYICgAAAA==.Aryethi:BAABNQAECn80AAIWAAkKGBDhkAADAgAWAAkKGBDhkAADAgAAAA==.',
As='Asafe:BAAANQAECgIIAgABNQAECgUICgAIAAAAAA==.Ashabellanar:BAAANQAECgQICAAAAA==.Ashenna:BAABNQAECn8ZAAIZAAkKISB2BABFAwAZAAkKISB2BABFAwAAAA==.Aslatiel:BAAANQADCgYIBgABNQAECggIIQAHAJ8NAA==.',
Au='Aurdraen:BAAANQAECgEIAQAAAA==.Autonomo:BAAANQAECgEIAQAAAA==.',
Av='Avanthara:BAAANQAECgUIDgAAAA==.',
Aw='Awk:BAABNQAECn8lAAQTAAoKfhxBNwCLAgATAAcKuh5BNwCLAgABAAgKAhprJQAEAgAUAAEKiAffKgAuAAAAAA==.',
Az='Azuros:BAAANQABCgIIAgAAAA==.',
['Aê']='Aêca:BAAANQADCgYIBgAAAA==.',
['Aø']='Aøc:BAACNQAFFH8GAAIWAAMKswWpKQB+AAAWAAMKswWpKQB+AAA1AAQKfzAAAhYACgr1E4RyAEoCABYACgr1E4RyAEoCAAAA.',
Ba='Babara:BAAANQABCgYIBwAAAA==.Babyfart:BAABNQAECn8tAAMFAAcK5hV2KwCBAQAFAAcK5hV2KwCBAQAWAAMKKQYcZwF6AAAAAA==.Bakushiterra:BAABNQAECn8WAAMRAAgKzAyVlgBsAQARAAcKKAiVlgBsAQANAAgKzgaQpgAlAQAAAA==.Barao:BAABNQAECn8fAAIHAAoK1RJrOADvAQAHAAoK1RJrOADvAQAAAA==.Barriguinha:BAAANQAECgUICgAAAA==.Baskervile:BAAANQAECgQIBwABNQAECggIGQABAKMOAA==.Batlemage:BAAANQABCgQIBgAAAA==.Batmano:BAAANQADCggIGAAAAA==.',
Be='Belezona:BAAANQADCgUIBQAAAA==.Benningtn:BAAANQAECgcICwAAAA==.Beornin:BAAANQADCgMIAwAAAA==.Betawizard:BAAANQAECgYIDwAAAA==.',
Bh='Bhast:BAAANQADCggICAABNQAECgoKGAACAFsUAA==.Bherg:BAAANQAECgUIDQAAAA==.',
Bi='Bilpaxton:BAAANQAECggIDwAAAA==.Biscilla:BAAANQAECgUIBQAAAA==.Biskademon:BAABNQAECn8nAAIGAAkKKB3kGQCKAgAGAAkKKB3kGQCKAgAAAA==.Bizum:BAAANQADCgcIDAAAAA==.Bizumgãoo:BAAANQAECgQIBgAAAA==.',
Bj='Bjørn:BAAANQADCgQIBAAAAA==.',
Bl='Blackee:BAAANQAECgIIBAAAAA==.Blackwatch:BAAANQAECgUICgAAAA==.Blecktk:BAABNQAECn8hAAIaAAkK9hjpDwDZAQAaAAkK9hjpDwDZAQAAAA==.Blitzkrig:BAACNQAFFH8UAAMbAAYKxhBbAAD6AAACAAYK1g9sHgCPAQAbAAMKAQ9bAAD6AAA1AAQKfy8AAxsACgrtHe0AAAkDABsACQoDIe0AAAkDAAIABQodE/ZLACMBAAAA.Bloodlioness:BAAANQAECgEIAQAAAA==.Bloodswar:BAAANQAECgUICgAAAA==.Bloodyclaw:BAAANQADCggIIAAAAA==.',
Bo='Bolkien:BAAANQAECgIIAwAAAA==.Boomgoesyou:BAABNQAECn8WAAIPAAgKSw2UUgCRAQAPAAgKSw2UUgCRAQAAAA==.Bourdriel:BAABNQAECn8fAAIPAAcKrwvHJADTAAAPAAcKrwvHJADTAAAAAA==.',
Br='Brad:BAAANQAECgMIAwABNQAECgoKKQAWANQZAA==.Bradoki:BAAANQAECgMIBgAAAA==.Bradví:BAAANQAECgEIAQAAAA==.Brancalleone:BAAANQAECgIJAgAAAA==.Brazukmaiden:BAAANQAECgIIAgABNQAECgQIBAAIAAAAAA==.Brisawave:BAABNQAECn8qAAINAAkKoyISEgA3AwANAAkKoyISEgA3AwAAAA==.Brizagato:BAABNQAECn8hAAIPAAkKaRTiMwBHAgAPAAkKaRTiMwBHAgAAAA==.Brizzarda:BAAANQADCggICAAAAA==.Broke:BAAANQAECgQIBQAAAA==.Brujaria:BAABNQAECn8bAAMcAAcKfROpCQDlAQAcAAcKfROpCQDlAQAdAAUKdwY88wDkAAAAAA==.Bruxxaum:BAAANQADCgEIAQAAAA==.Brád:BAABNQAECn8pAAIWAAoK1BklYwBxAgAWAAoK1BklYwBxAgAAAA==.',
Bu='Bushido:BAAANQADCgYIEgAAAA==.Bustgril:BAABNQAECn8jAAIXAAcKnhQSEgCFAQAXAAcKnhQSEgCFAQAAAA==.',
Bz='Bzbit:BAAANQADCgMIAgAAAA==.',
['Bé']='Béssi:BAAANQAECgQIBgAAAA==.',
Ca='Caiquebmq:BAAANQAECgQIBAAAAA==.Calanguejo:BAAANQADCgQIBAABNQAECgoKKwAeACUfAA==.Calanguinhe:BAAANQAECgQIBQAAAA==.Caldrin:BAAANQADCgEIAQAAAA==.Calliphora:BAABNQAECn8kAAIYAAgK8Aq7BADgAAAYAAgK8Aq7BADgAAAAAA==.Camilia:BAAANQADCggICAAAAA==.Canard:BAAANQAECgUIAwABNQAECgoKKAAaAKoXAA==.Canards:BAAANQAECgUIBQABNQAECgoKKAAaAKoXAA==.Cannibal:BAAANQAECgIIAwAAAA==.Carinha:BAAANQADCggJAgAAAA==.Carloxamã:BAABNQAECn80AAIJAAoKhSCyAwBgAwAJAAoKhSCyAwBgAwAAAA==.Cassisus:BAAANQADCggICAAAAA==.Catarnaldo:BAAANQADCgYICQABNQAECgkJFgANAGcjAA==.Cathiseev:BAABNQAECn8pAAMfAAoKySCyBgA8AwAfAAoKySCyBgA8AwAgAAUK0Q5JEgAOAQAAAA==.Cathury:BAAANQAECgMJCAAAAA==.Catÿ:BAABNQAECn8iAAINAAkKKiHEFQCnAQANAAkKKiHEFQCnAQABNQAFFAQIEAATAA4lAA==.Cavernozo:BAAANQAECgcIDAABNQAECgoKGwAFACgaAA==.Caxola:BAAANQADCgIIAgAAAA==.',
Ce='Ceifhador:BAAANQAECgUIBQAAAA==.Celfier:BAAANQAECgQIBAAAAA==.Cenarioss:BAAANQAECgQIBgAAAA==.Cerino:BAAANQADCgQIBAAAAA==.Cevadão:BAABNQAECn8mAAIhAAoKShffBQCzAQAhAAoKShffBQCzAQABNQAECgoKGAACAFsUAA==.',
Ch='Chaleira:BAAANQAECgYICQAAAA==.Changjin:BAAANQAECgUICQAAAA==.Chewbaka:BAAANQAECgIIAgAAAA==.Cheweir:BAAANQAECgQICgAAAA==.Chiclete:BAABNQAECn9JAAUSAAoKPxmtBwCEAQAZAAkK+xZdDgAwAgAMAAoK5BT0CgCJAQASAAgK0hOtBwCEAQAPAAQKMA4AdwDvAAAAAA==.Chopz:BAAANQAECgQIBgABNQAFFAUICgAEAFoWAA==.Chovor:BAAANQAECggIDwAAAA==.Chrizantm:BAAANQAECgUIEQABNQAECgoKJQACAJIPAA==.Chucknòórris:BAAANQAECgYIDgAAAA==.Chøcøballs:BAAANQABCgQIBAAAAA==.',
Cl='Clairë:BAAANQAECggIDwAAAA==.Claude:BAAANQADCgQIBQAAAA==.Clbalena:BAAANQADCgEIAgAAAA==.Clio:BAABNQAECn8UAAIPAAQK/QTZjQCfAAAPAAQK/QTZjQCfAAAAAA==.',
Co='Cockcroft:BAAANQADCgYIDAABNQAFFAMIBwAiAEsGAA==.Coionir:BAABNQAECn8XAAIZAAgKyR+vBwDjAgAZAAgKyR+vBwDjAgAAAA==.Coiovoker:BAAANQADCgEIAQABNQAECggIFwAZAMkfAA==.Coldblooded:BAAANQADCgcIBwABNQAECgQIBQAIAAAAAA==.Coldnez:BAAANQAECgMIBAAAAA==.Comunistaa:BAACNQAFFH8GAAIRAAIKwh7UHwCzAAARAAIKwh7UHwCzAAA1AAQKfywAAhEACQokJGIFAMADABEACQokJGIFAMADAAAA.Contadoruns:BAAANQAECgUIBQAAAA==.Coquette:BAAANQAECgUIBQAAAA==.Corruptionz:BAAANQAECgQIDAAAAA==.Corstine:BAAANQAECgYICgAAAA==.Corvynus:BAAANQADCgUIBgAAAA==.Couldovisk:BAAANQADCgIJAgAAAA==.',
Cr='Crawsing:BAAANQADCgEIAQAAAA==.Cronosxdm:BAAANQAFFAEIAQAAAA==.Crucyatus:BAABNQAECn8iAAMWAAkKUR6pMAAHAwAWAAkKUR6pMAAHAwAFAAEKoR8AYQBYAAAAAA==.Cruelmoon:BAAANQADCgEIAQAAAA==.',
Cy='Cyrande:BAAANQAECgIIAgABNQAECgIIAwAIAAAAAA==.',
['Cá']='Cássia:BAAANQADCggICQAAAA==.',
['Cå']='Cåssio:BAAANQAECgYIDwAAAA==.',
['Cÿ']='Cÿgnus:BAABNQAECn8gAAIBAAoKbB6kCQBFAwABAAoKbB6kCQBFAwABNQAECgoKNwAHAKwkAA==.',
Da='Dadashi:BAAANQADCggICAAAAA==.Dago:BAAANQAECgEIAQAAAA==.Danadinn:BAAANQADCgcIBwABNQAECgYICAAIAAAAAA==.Danteholy:BAAANQADCgMIAwAAAA==.Darkhold:BAABNQAECn8wAAMaAAkK+hKSJwBoAQAjAAcK7Q5rEwBpAQAaAAkK+hKSJwBoAQAAAA==.Darklendio:BAAANQADCgUICgAAAA==.Daroncosp:BAAANQADCgIJAgAAAA==.Darü:BAAANQAECgQIBQAAAA==.Dashuman:BAABNQAECn8lAAIVAAkKpRzQIQDmAgAVAAkKpRzQIQDmAgAAAA==.Davicohunter:BAAANQADCgIIAgAAAA==.Dayshine:BAAANQADCgUICAAAAA==.Dazhu:BAAANQADCggICAAAAA==.',
De='Deadguth:BAAANQAECggJBwAAAA==.Deadusopp:BAAANQADCgQIBAAAAA==.Deathatrix:BAAANQADCgUICAABNQAECgkJHwAGAEAMAA==.Deceive:BAABNQAECn8ZAAMHAAkKSg8rDQCGAQAHAAgKSg8rDQCGAQAGAAEKAAArdgAiAAAAAA==.Defroque:BAAANQAECgUIBQAAAA==.Deimons:BAAANQAECggIEAAAAA==.Deis:BAAANQADCgUIBAAAAA==.Delarÿn:BAAANQAECgQIBAAAAA==.Demoncrashe:BAAANQADCgEIAQAAAA==.Demzumilde:BAAANQAECgMIBAAAAA==.Denevy:BAABNQAECn85AAIkAAgKDBQwCAAzAQAkAAgKDBQwCAAzAQAAAA==.Deraelda:BAAANQADCgMIBAAAAA==.Derbster:BAAANQAECgcICwAAAA==.Destructiom:BAABNQAECn8mAAIOAAkKPB0TOQC/AgAOAAkKPB0TOQC/AgAAAA==.',
Dh='Dhamburguer:BAABNQAECn8iAAIGAAkK3BueEgDWAgAGAAkK3BueEgDWAgAAAA==.Dhanadrai:BAABNQAECn8aAAMlAAYKUAlffQAEAQAlAAYKUAlffQAEAQAEAAEKTQJT9QAiAAAAAA==.',
Di='Diabolick:BAAANQADCggICAAAAA==.Diamalboy:BAAANQADCggICAAAAA==.Diamath:BAAANQADCgUJBQAAAA==.Diestro:BAAANQAECgEIAQAAAA==.Diggop:BAAANQAECgIIAwAAAA==.Dijank:BAAANQADCgIIAgABNQADCgUICQAIAAAAAA==.Dima:BAABNQAECn8mAAINAAoKdSHLBwCDAwANAAoKdSHLBwCDAwAAAA==.',
Dk='Dktt:BAAANQAECgUIDgAAAA==.',
Do='Dornaa:BAAANQAECgUICwAAAA==.Dosmagos:BAAANQAECgQICgAAAA==.Doulce:BAABNQAECn8gAAMRAAcK0Q9bgwCcAQARAAcK0Q9bgwCcAQAJAAEKAABZOgAlAAAAAA==.',
Dr='Dracarysz:BAAANQAECgIIAwAAAA==.Draculavmp:BAAANQADCgEIAQAAAA==.Dragonbaby:BAAANQADCgUIBQAAAA==.Drainetty:BAAANQAECgEIAQAAAA==.Dranacs:BAABNQAECn8oAAIaAAoKqhdaIACCAQAaAAoKqhdaIACCAQAAAA==.Dreampollys:BAAANQAECgEIAQABNQAFFAIIAgAIAAAAAA==.Dreamremix:BAAANQAFFAIIAgAAAA==.Dresaron:BAAANQADCgYIBgABNQAECgoKKwAeACUfAA==.Dreyol:BAAANQAECgMIBAAAAA==.Drts:BAABNQAECn80AAICAAoKUh0ORwD1AgACAAoKUh0ORwD1AgAAAA==.Drunkiechan:BAAANQAECgEIAQAAAA==.',
Du='Dudupokas:BAAANQAECgQIBAAAAA==.Dumar:BAAANQAECgcIDQAAAA==.Duromargh:BAAANQADCgMIAwAAAA==.',
['Dü']='Düst:BAAANQADCggIEwAAAA==.',
Ed='Eduarthas:BAABNQAECn8VAAIEAAYKWgichQAKAQAEAAYKWgichQAKAQAAAA==.Edyra:BAAANQADCggICAAAAA==.',
Eg='Egoist:BAAANQADCggJDwAAAA==.',
El='Elementys:BAAANQAECgQICQABNQAECgYIBgAIAAAAAA==.Elemëntum:BAAANQAECgEIAQAAAA==.Elfuryon:BAAANQADCgIIAgABNQAECgoKRgAOAAskAA==.Elinaara:BAABNQAECn8hAAMFAAcKuw2ZMABaAQAFAAcKuw2ZMABaAQAWAAEKvgqwngE4AAAAAA==.Elizabeth:BAAANQAECgMIAwAAAA==.Elliith:BAAANQADCgIIAgAAAA==.Ellithyx:BAAANQAECgQIBgAAAA==.Elmagoprior:BAABNQAECn8VAAMCAAUKPgZNrwBzAAACAAUKPgZNrwBzAAAbAAEKEgLaDwAbAAAAAA==.Elricky:BAAANQAECgEIAQAAAA==.Eluna:BAAANQAECgcICwAAAA==.Eluric:BAAANQAECgcICwABNQAECgoKRgAOAAskAA==.Elwiñ:BAAANQADCgEIAQAAAA==.',
En='Encanis:BAAANQADCgYIAgAAAA==.Entropye:BAAANQAECgQIBAAAAA==.',
Ep='Epsan:BAAANQAECgEIAgAAAA==.',
Er='Ercshadow:BAAANQAECgUICgAAAA==.Ermooke:BAAANQAECggICgAAAA==.',
Es='Escanorzão:BAAANQADCgcIDAABNQAECgQIBQAIAAAAAA==.Escola:BAAANQAECgQICQAAAA==.',
Ex='Executepowa:BAAANQADCggIDgAAAA==.Exo:BAABNQAECn8sAAIOAAoKmR+iDAANAgAOAAoKmR+iDAANAgAAAA==.Exorciseur:BAACNQAFFH8RAAIHAAYKGhs8AgBeAQAHAAYKGhs8AgBeAQA1AAQKfzkAAgcACgqVIuwIAG4DAAcACgqVIuwIAG4DAAAA.Extintora:BAAANQAECgIIAQABNQAECgoKKwAeACUfAA==.',
Fa='Fabercästell:BAAANQAECgcICgAAAA==.Fabers:BAAANQAECgMIAwAAAA==.Farator:BAAANQAECgQIAgAAAA==.Fargunn:BAABNQAECn8cAAIOAAgKgRFqkgDkAQAOAAgKgRFqkgDkAQAAAA==.',
Fe='Feanori:BAABNQAECn8hAAIHAAkKzBTfLQA2AgAHAAkKzBTfLQA2AgAAAA==.Feanør:BAABNQAECn8UAAMFAAcKAArFOgAaAQAFAAcK9wnFOgAaAQAWAAQKxwRJUgGdAAAAAA==.Feinanduo:BAAANQADCgMIAwAAAA==.Felfury:BAAANQADCgUIBQABNQAECgoKHAAGAPwiAA==.Fennris:BAAANQAECgEIAwAAAA==.Feyrin:BAAANQADCggIHQAAAA==.',
Fi='Finngermy:BAAANQADCggICQAAAA==.',
Fl='Flodearthen:BAAANQADCgQIBwABNQAECgEIAQAIAAAAAA==.Flodfelblood:BAAANQAECgEIAQAAAA==.',
Fr='Francine:BAAANQAECgUIBQAAAA==.',
['Fí']='Fíli:BAAANQAECgEIAQAAAA==.',
['Fï']='Fïrestorm:BAAANQADCgYIBgAAAA==.',
Ga='Gabela:BAAANQAECgIIAwAAAA==.Gabrael:BAAANQABCgQJBAAAAA==.Gaiataur:BAAANQADCgUIBgAAAA==.Galandiel:BAAANQADCggIDgAAAA==.Galinni:BAAANQADCggIEAAAAA==.Gallon:BAABNQAECn8hAAMiAAgKLxr0BwBfAQAiAAgKLxr0BwBfAQAhAAEKAABZQgAAAAAAAA==.Gandàllf:BAAANQAECgcICQABNQAECggIGAAVAHENAA==.Garcs:BAAANQADCgQIBAAAAA==.Garfall:BAABNQAECn8bAAIPAAkK4BaSEgBFAQAPAAkK4BaSEgBFAQAAAA==.',
Gh='Ghøulthamy:BAAANQAECgEIAQAAAA==.',
Gl='Glacyale:BAABNQAECn8eAAIXAAkKpBVuAwCPAQAXAAkKpBVuAwCPAQAAAA==.Glisa:BAABNQAECn8fAAQWAAoKuRQviAAXAgAWAAoK0BEviAAXAgAFAAcKERbXJwCfAQAVAAIKjgTyKgErAAAAAA==.Glorfindel:BAAANQAECgIIAwAAAA==.',
Gn='Gnomepink:BAAANQADCggIJQAAAA==.',
Go='Godadrian:BAABNQAECn8nAAMWAAoKLw0XOwBSAQAWAAoKLw0XOwBSAQAFAAEKAADpfwAdAAAAAA==.Gogozinho:BAAANQAECgUIBQAAAA==.Gordãobtm:BAABNQAECn8VAAIaAAcK7RO5qAC3AQAaAAcK7RO5qAC3AQAAAA==.Gordãum:BAAANQAECgEIAQAAAA==.Gosu:BAABNQAECn8uAAIhAAkKCCGGAAAkAwAhAAkKCCGGAAAkAwAAAA==.',
Gr='Gralfor:BAAANQAECgUIBQAAAA==.Grekorio:BAAANQAECgUICgAAAA==.Greylord:BAAANQAECgIIAwABNQAECgoKIwAfAFcXAA==.Greylorddrak:BAABNQAECn8jAAIfAAoKVxc7EgCIAgAfAAoKVxc7EgCIAgAAAA==.Greylordp:BAAANQAECgEIAQABNQAECgoKIwAfAFcXAA==.Gromitak:BAAANQAECgQIBQAAAA==.Gronak:BAAANQAECgQJBAAAAA==.',
Gu='Guhtz:BAAANQADCgMIAwAAAA==.Guillyn:BAAANQAECgcIEwAAAA==.Gultai:BAAANQAECgYIDwAAAA==.Gults:BAAANQADCgQIBAAAAA==.Gultsz:BAAANQADCgUIBwAAAA==.Gunpowter:BAAANQABCgIIAwAAAA==.Guxrock:BAAANQAECgIIBAAAAA==.',
Gw='Gwts:BAAANQAECgIIAgABNQAECgoKMAAJAOwaAA==.',
Gy='Gyllenhaal:BAAANQADCgUIBQAAAA==.',
['Gä']='Gäspär:BAAANQADCgYJBgAAAA==.',
['Gø']='Gødmar:BAAANQAECgIIAgAAAA==.',
Ha='Hadoky:BAAANQADCgIIAgABNQAECgUIBwAIAAAAAA==.Hafo:BAAANQADCgYJDQAAAA==.Hagnaredk:BAAANQADCgMIAwAAAA==.Haiume:BAAANQAECgQIBgAAAA==.Hamiister:BAAANQADCgQIAwAAAA==.Hancalimon:BAABNQAECn8gAAIPAAYKUhf7UACYAQAPAAYKUhf7UACYAQAAAA==.Haokö:BAAANQAECgEIAQAAAA==.Happyhour:BAAANQADCgQIBAAAAA==.Hasanzi:BAAANQADCgUIBQAAAA==.Hastterix:BAABNQAECn8YAAIWAAYKXRHI0wB0AQAWAAYKXRHI0wB0AQAAAA==.Hatezon:BAAANQAECgYIEAAAAA==.',
He='Heavyking:BAABNQAECn8bAAIFAAgKfhCRLwBhAQAFAAgKfhCRLwBhAQAAAA==.Heishoo:BAAANQADCgIIAgAAAA==.Helitox:BAAANQAECgQICAAAAA==.Hellhoundish:BAAANQADCgYIBgABNQAFFAQIDwAjAPkTAA==.Hellreaper:BAABNQAECn8vAAMdAAoKyg2NfwDnAQAdAAoKEA2NfwDnAQAcAAIKuAxOCgB7AAAAAA==.Heloisaa:BAABNQAECn8dAAIkAAgKlhBAGACrAQAkAAgKlhBAGACrAQAAAA==.Helwen:BAAANQAECgEIAQAAAA==.Hemm:BAAANQAECgMIAwAAAA==.Heracranosd:BAAANQAECgcIDAAAAA==.Heracranosx:BAAANQAECggIEwAAAA==.Heracranosz:BAAANQAECgQIBAAAAA==.Herdy:BAAANQADCgMJBAAAAA==.Herta:BAAANQAECgMIBgAAAA==.Hess:BAAANQAECgUIEgAAAA==.',
Hi='Hireque:BAABNQAECn8lAAIOAAkKVxk4GwCrAQAOAAkKVxk4GwCrAQAAAA==.Hitkilled:BAABNQAECn8cAAIOAAgKuQqUWQD7AAAOAAgKuQqUWQD7AAAAAA==.Hitkins:BAAANQAECgYIBgAAAA==.',
Ho='Hofpriest:BAAANQADCgUIBQAAAA==.Hoiac:BAAANQAECgUIEAAAAA==.Holycel:BAAANQAECgQICgABNQAFFAMIBwAEADASAA==.Holyscrim:BAAANQAECgEIAQAAAA==.Hoolylight:BAAANQAECgYICwAAAA==.Hordhunter:BAAANQAECgMIAwABNQAECgoKGwAFACgaAA==.',
Hu='Huelandita:BAAANQAECgcIDQAAAA==.Hunterpica:BAABNQAECn8lAAIOAAoKPB0uKQDzAgAOAAoKPB0uKQDzAgAAAA==.Huntmon:BAABNQAECn8XAAIOAAcKLR58mwDQAQAOAAcKLR58mwDQAQAAAA==.Huriah:BAAANQAECgIIBAAAAA==.Huskat:BAAANQAECgYIDAAAAA==.',
Hy='Hysillens:BAABNQAECn8WAAIcAAgKEgweDACiAQAcAAgKEgweDACiAQAAAA==.',
['Hã']='Hãn:BAAANQADCgEIAQAAAA==.',
['Hä']='Härü:BAAANQADCgUIAwAAAA==.',
['Hö']='Hölyfans:BAAANQAECgYIDwAAAA==.',
Ic='Icebïg:BAAANQAECgEIAQAAAA==.',
Ig='Ignicel:BAAANQAECgYICgABNQAFFAMIBwAEADASAA==.Igno:BAAANQAECgUIEgABNQAECgoKLgARAOIjAA==.Igubigu:BAAANQADCgQIBAAAAA==.',
Il='Ilane:BAAANQABCggIDAAAAA==.Ilidarilariê:BAAANQADCgYIBgAAAA==.Illidatrix:BAABNQAECn8fAAIGAAkKQAwqNwCLAQAGAAkKQAwqNwCLAQAAAA==.Illïndão:BAAANQADCggICAAAAA==.Ilovealtgirl:BAAANQADCggJFAAAAA==.',
In='Inladris:BAAANQAECgIIAwAAAA==.Inot:BAABNQAECn8eAAITAAkKTRcdMgA2AQATAAkKTRcdMgA2AQAAAA==.',
Ir='Irmãsafada:BAAANQADCgMIAwAAAA==.',
Is='Iscariotes:BAAANQABCgQIBAAAAA==.Ismael:BAAANQAECgUICgAAAA==.',
It='Italodpz:BAAANQAECgUIBQABNQAECggIHQAlAAITAA==.Itsälasca:BAAANQAECgQIBwAAAA==.',
Iu='Iuri:BAAANQAECggIEQAAAA==.',
Ix='Ixlzvaxtylxl:BAAANQADCgYIBgAAAA==.',
Iz='Izanna:BAAANQAECgYICQAAAA==.',
Ja='Jabäl:BAAANQAECgUIBQAAAA==.Jalinrabeidh:BAAANQAECgEIAQAAAA==.Jampack:BAACNQAFFH8GAAINAAMK6BWzDACyAAANAAMK6BWzDACyAAA1AAQKfyIAAw0ACgqSIlUYABIDAA0ACgqSIlUYABIDABEAAgq3EXx3AFMAAAAA.',
Je='Jeevas:BAABNQAECn8fAAIVAAgKgB5cLgCtAgAVAAgKgB5cLgCtAgAAAA==.Jefté:BAAANQADCgEIAQAAAA==.Jeguinha:BAAANQABCggIDgAAAA==.Jeu:BAAANQADCgcICQAAAA==.Jeyla:BAAANQADCgEIAQAAAA==.',
Jh='Jhasperr:BAAANQAECgQIBQAAAA==.',
Jo='Jocabiroca:BAABNQAECn8oAAMCAAoKvhY9gAB+AgACAAoKvhY9gAB+AgAbAAEKlwLtDgAqAAAAAA==.Johnez:BAAANQADCgcIBwAAAA==.Joral:BAAANQABCggICwAAAA==.Jotavê:BAAANQADCgUICQAAAA==.',
Jp='Jpleuk:BAABNQAECn8pAAIeAAoKIw6QJQAgAgAeAAoKIw6QJQAgAgAAAA==.',
Jr='Jrxamã:BAABNQAECn8dAAIRAAYKqx23GwBOAQARAAYKqx23GwBOAQAAAA==.',
Ju='Juliia:BAAANQAECgUIDgAAAA==.Jusgu:BAAANQAECgcICwABNQAECgoKHwACABEbAA==.',
['Jö']='Jönah:BAAANQADCgMIAwAAAA==.',
Ka='Kaaliel:BAAANQADCgQIBQAAAA==.Kagero:BAAANQADCgQIBAAAAA==.Kaiev:BAAANQADCgYICgAAAA==.Kaju:BAABNQAECn8cAAMXAAkKCyLnBADRAgAXAAkKCyLnBADRAgAbAAEKAAAFBQAAAAAAAA==.Kalinis:BAAANQAECgEJAQAAAA==.Kalliiope:BAABNQAECn8jAAMXAAoKhwu1DQDUAQAXAAoKhAu1DQDUAQACAAUK+QIEdAHWAAAAAA==.Kamesenin:BAAANQADCgUIBQAAAA==.Kamïlla:BAABNQAECn8jAAMaAAoKPA/DDQDtAQAaAAoKXA3DDQDtAQAjAAYKAg17FQBFAQAAAA==.Karak:BAAANQADCgIIAgAAAA==.Karamatsu:BAAANQAECgIIAgAAAA==.Karollus:BAAANQABCgIIAgAAAA==.Kath:BAAANQADCgYIBgAAAA==.Kathana:BAAANQABCggIDAAAAA==.Katona:BAABNQAECn8cAAIXAAkKohTgCgAYAgAXAAkKohTgCgAYAgAAAA==.Kauss:BAAANQAECgUIBQAAAA==.',
Kd='Kdakaisa:BAAANQAECgYICgAAAA==.Kdposa:BAAANQABCgQIBAAAAA==.',
Ke='Keior:BAAANQAECgEIAQAAAA==.Kenai:BAABNQAECn8aAAISAAkK+wqbJwBZAQASAAkK+wqbJwBZAQAAAA==.Kewenz:BAABNQAECn8xAAIOAAkK0yadAAAHBAAOAAkK0yadAAAHBAABNQAFFAUIDgAOAOkjAA==.Keylaa:BAAANQAECgcIEwAAAA==.',
Kh='Khasin:BAABNQAECn8jAAIdAAcKpgVqagCuAAAdAAcKpgVqagCuAAAAAA==.',
Ki='Kierke:BAAANQAECggIEwAAAA==.Kimyx:BAAANQAECgcIDQABNQAFFAUIDgAOAOkjAA==.Kindz:BAAANQAECgQIBAABNQAFFAUIDgAOAOkjAA==.Kiregeth:BAAANQAECgYIDQAAAA==.Kitrel:BAAANQAECgMIAwAAAA==.',
Kl='Kleiio:BAAANQAECgEIAQAAAA==.Kllauzz:BAABNQAECn8iAAIBAAgK0QyQLgCwAQABAAgK0QyQLgCwAQABNQAECgoKLAAWABUMAA==.Kllauzzmage:BAAANQAECgIIAgABNQAECgoKLAAWABUMAA==.Kllauzzpalla:BAABNQAECn8sAAIWAAoKFQzGRAA8AQAWAAoKFQzGRAA8AQAAAA==.',
Kn='Knufolgado:BAAANQADCgYIBgAAAA==.',
Ko='Kolyn:BAABNQAECn9GAAIOAAoKCyQFDgBwAwAOAAoKCyQFDgBwAwAAAA==.Komamurasou:BAAANQAECgQIBAAAAA==.',
Kr='Krastian:BAAANQAECgcIEwAAAA==.Kreegh:BAAANQAECgQIBQAAAA==.Krikixus:BAAANQADCgYIBgAAAA==.Krupper:BAAANQAECgMIAwABNQAECgYIDAAIAAAAAA==.Krynesa:BAAANQADCggICwAAAA==.',
Ku='Kukuatzo:BAAANQAECgUIDwAAAA==.',
Ky='Kyndin:BAAANQAECgQIBAABNQAFFAUIDgAOAOkjAA==.Kyrara:BAAANQAECgUIBQAAAA==.',
['Kä']='Kälini:BAAANQADCgcIDAABNQAECgQIBAAIAAAAAA==.Käyros:BAAANQADCgUJCgAAAA==.',
['Kó']='Kónar:BAAANQADCgEIAQAAAA==.',
['Kö']='Köndmänö:BAABNQAECn8bAAIRAAcKACPbLgDAAgARAAcKACPbLgDAAgAAAA==.Köri:BAABNQAECn8eAAMCAAkKpx09WADPAgACAAkKPh09WADPAgAXAAEKMx1UPgBIAAAAAA==.',
La='Lakaioo:BAABNQAECn8eAAMaAAcKjwtWygBiAQAaAAcKjwtWygBiAQAkAAIKkAMLQABAAAAAAA==.Lamiel:BAAANQAECgQIBQAAAA==.Lamont:BAABNQAECn8qAAIVAAgKGQ4aOgD+AAAVAAgKGQ4aOgD+AAAAAA==.Lampiião:BAABNQAECn82AAIOAAgKQRwBHACoAQAOAAgKQRwBHACoAQAAAA==.Lanllaniel:BAABNQAECn8ZAAMBAAgKow56MACgAQABAAcKSwx6MACgAQATAAMKogXu4ACHAAAAAA==.Largartixa:BAAANQADCgQJBAABNQAECgQJBAAIAAAAAA==.Larslion:BAAANQABCgYJBgAAAA==.Lawphos:BAAANQABCgMIAwAAAA==.',
Le='Lebelisco:BAABNQAECn8aAAIOAAkKnhiJVAB0AgAOAAkKnhiJVAB0AgAAAA==.Leehyori:BAABNQAECn8WAAQBAAcKtxRkDgAjAQABAAYKcRdkDgAjAQAUAAIKwAVIIwBOAAATAAEKXAFzDAEbAAAAAA==.Legëndaria:BAAANQAECgEIAQAAAA==.Lennorien:BAABNQAECn8tAAIYAAkKVRgMCACAAgAYAAkKVRgMCACAAgAAAA==.Lestard:BAAANQAECgYIDAAAAA==.Leturey:BAAANQADCgMIAwAAAA==.Leøric:BAAANQADCggICAAAAA==.',
Lh='Lhyunl:BAAANQADCgIIAgAAAA==.',
Li='Liciox:BAAANQADCgIIAgAAAA==.Lifestrream:BAABNQAECn8aAAMSAAgK5BL2IwB2AQASAAgKEw/2IwB2AQAZAAYKAQ4XHABDAQABNQAECgoKKAASAHoYAA==.Liftshertail:BAABNQAECn8pAAQfAAkKvBtYCwDuAgAfAAkKvBtYCwDuAgAmAAUKnwzMJQALAQAgAAIKawwXIABbAAAAAA==.Ligiaf:BAAANQAECgcIEgAAAA==.Liilum:BAAANQAECgMIAwAAAA==.Limeware:BAAANQADCgYICAAAAA==.Linë:BAAANQADCggIHwABNQAECgQIBAAIAAAAAA==.Linëa:BAAANQADCgIIBQAAAA==.Linüss:BAAANQAECgEIAQAAAA==.Lionarot:BAABNQAECn8WAAMOAAYKcgsgxAB6AQAOAAYKcgsgxAB6AQAeAAIKGwabOgA5AAAAAA==.Littleshelby:BAAANQADCgYJDwAAAA==.',
Lo='Lobinox:BAAANQADCggICgAAAA==.Lolzhe:BAAANQAECgYIBwABNQAECggIKAAiAFcaAA==.Longaim:BAABNQAECn8XAAIOAAcKohLjlwDYAQAOAAcKohLjlwDYAQAAAA==.Lorthaeron:BAABNQAECn8VAAIQAAgKARDgQQC+AQAQAAgKARDgQQC+AQAAAA==.Losdor:BAAANQAECgUIBgAAAA==.Lostminder:BAAANQAECgQIBgAAAA==.Lothbrok:BAABNQAECn8oAAIOAAoKOxVcMABgAQAOAAoKOxVcMABgAQAAAA==.',
Lu='Lucanor:BAAANQADCgUIBQAAAA==.Lucasbr:BAAANQADCggIDgAAAA==.Lucasyeah:BAACNQAFFH8fAAIaAAcK4hjdAgCQAQAaAAcK4hjdAgCQAQA1AAQKfysAAxoACgrBIrEoABcDABoACgoTIrEoABcDACMAAQrQIZQsAFIAAAAA.Lukanelas:BAAANQADCgcIDgAAAA==.Lulyssa:BAAANQADCggICwAAAA==.Luna:BAABNQAECn8bAAMTAAkK9hsqIwDhAgATAAkKkxoqIwDhAgAUAAQK/RN7EwDxAAAAAA==.Lunes:BAABNQAECn85AAINAAoKWB6SCQApAgANAAoKWB6SCQApAgAAAA==.Lunna:BAAANQAECgIIAgAAAA==.Luster:BAAANQADCggIEQAAAA==.Lusther:BAABNQAECn8YAAMVAAgKcQ2QcADGAQAVAAgKcQ2QcADGAQAFAAQKKRd0QwDlAAAAAA==.Luxdomini:BAAANQADCgEIAQAAAA==.Luzdacelesc:BAACNQAFFH8MAAIBAAUKvCRrBQDiAQABAAUKvCRrBQDiAQA1AAQKf0sAAwEACgpgJmUAAP0DAAEACgpgJmUAAP0DABMAAgp4DTbiAIMAAAAA.',
Ly='Lyaah:BAAANQADCggIGQAAAA==.Lyeer:BAAANQADCgIIAgAAAA==.',
['Lë']='Lënori:BAAANQAECgEIAgAAAA==.',
['Ló']='Lólzhé:BAAANQADCgYICwABNQAECggIKAAiAFcaAA==.',
['Lø']='Lølzhê:BAABNQAECn8oAAIiAAgKVxpfFQAlAgAiAAgKVxpfFQAlAgAAAA==.Løvizinha:BAAANQAECgQIBQAAAA==.',
['Lú']='Lúaprata:BAAANQAECgUIDgAAAA==.',
Ma='Maagnuss:BAAANQADCgIIAgAAAA==.Madbuddha:BAAANQADCggIDAAAAA==.Mageli:BAABNQAECn8ZAAICAAcKkRK3ZwDtAAACAAcKkRK3ZwDtAAAAAA==.Magodanilo:BAAANQAECgUIBwAAAA==.Magodavida:BAABNQAECn8bAAITAAYKXQ7+QQACAQATAAYKXQ7+QQACAQAAAA==.Magodotruco:BAAANQADCgIIAgAAAA==.Maguinax:BAAANQAECgEIAwABNQAFFAUICgAEAFoWAA==.Maheena:BAABNQAECn8WAAIOAAgKWBWOYwBOAgAOAAgKWBWOYwBOAgAAAA==.Mai:BAABNQAECn8kAAMbAAkKnA5ZAwDGAQAbAAgKJxBZAwDGAQACAAcK4AVxkgCiAAAAAA==.Mairon:BAAANQADCgcICQAAAA==.Makksha:BAAANQADCgEIAQAAAA==.Makoto:BAABNQAECn8jAAIlAAkKYhDeVQCcAQAlAAkKYhDeVQCcAQAAAA==.Malborion:BAAANQAECgUIEAAAAA==.Malevolent:BAAANQAECgcIEQAAAA==.Malignõ:BAABNQAECn8uAAIRAAoK4iO0CACiAwARAAoK4iO0CACiAwAAAA==.Mallphite:BAAANQAECgEIAQAAAA==.Malluria:BAAANQAECgIIAgAAAA==.Maltozo:BAABNQAECn8dAAIQAAgK7wusUABwAQAQAAgK7wusUABwAQAAAA==.Mandrakson:BAABNQAECn8mAAIQAAoK3QpmFgBXAQAQAAoK3QpmFgBXAQAAAA==.Mandubim:BAAANQAECgMIAwAAAA==.Mariiamil:BAABNQAECn8aAAIVAAcKzgNcRgDYAAAVAAcKzgNcRgDYAAAAAA==.Marvelos:BAAANQABCggJCgAAAA==.Marvvila:BAABNQAECn8mAAMOAAgKnhkaKwBwAQAOAAgKnhkaKwBwAQAeAAEK5QaFjgAxAAAAAA==.Marycristiny:BAABNQAECn8jAAMYAAoKZhicBgChAgAYAAkKhhqcBgChAgAdAAIKSgiEsAA/AAAAAA==.Mauwolf:BAAANQAECgQIBQAAAA==.Mazaky:BAABNQAECn8jAAITAAcKjw33LwA+AQATAAcKjw33LwA+AQAAAA==.',
Me='Medivi:BAAANQADCgMIAwAAAA==.Megi:BAAANQABCgIIAgAAAA==.Megumi:BAAANQAECgMIAwAAAA==.Meisterz:BAAANQADCgQIBAABNQAECgoKMAAJAOwaAA==.Memphis:BAAANQADCgcIBwAAAA==.Menorxidil:BAABNQAECn8lAAIiAAkKLxrvDwCAAgAiAAkKLxrvDwCAAgAAAA==.Mestredoido:BAAANQAECgQICQAAAA==.Mestreløck:BAAANQADCgMICQAAAA==.Metallicä:BAAANQADCgMIAwAAAA==.Meuhomen:BAAANQAECgMIAwABNQAECgkJKQAOAM8dAA==.',
Mh='Mhenb:BAABNQAECn8bAAMXAAkKyQ4NHQAGAQAXAAUKHg8NHQAGAQACAAgKRQvKhwC1AAAAAA==.Mhorgothh:BAAANQADCgQIBAAAAA==.',
Mi='Micherouc:BAAANQADCggIDgAAAA==.Midnights:BAAANQADCgUIBQAAAA==.Mierket:BAAANQADCgUIBQAAAA==.Mikal:BAABNQAECn8fAAIOAAgKwxGuLQBoAQAOAAgKwxGuLQBoAQAAAA==.Miniime:BAAANQADCgQIBAAAAA==.Minort:BAAANQAECgYIEgAAAA==.Minör:BAAANQAECgQIBwAAAA==.Mirisma:BAAANQADCgEIAQABNQAECgcIEQAIAAAAAA==.Missmarvel:BAAANQABCgYICgAAAA==.Mistogunn:BAAANQAECgIIBwAAAA==.Mithrael:BAAANQADCgUIBQAAAA==.Mizukagesou:BAABNQAECn8WAAMNAAYK0RxYDwDgAQANAAYK0RxYDwDgAQARAAQKexcyvwAUAQAAAA==.',
Mo='Monkbest:BAAANQADCggIFwAAAA==.Montedruids:BAAANQADCgEIAQAAAA==.Montej:BAAANQAECgMIBAAAAA==.Montäna:BAAANQABCgMIAwAAAA==.Mooncap:BAABNQAECn8jAAIPAAkKOhOeEABVAQAPAAkKOhOeEABVAQAAAA==.Moondragoon:BAAANQADCgcICQAAAA==.Morakhir:BAAANQADCgYICAABNQAECgcIHAAFAFgXAA==.Moranguinhö:BAAANQADCgEJAQAAAA==.Mordiidinha:BAAANQAECgQIBwABNQAECgoKLgARAOIjAA==.Morganviolet:BAABNQAECn8jAAIQAAcKUg73JAAOAQAQAAcKUg73JAAOAQAAAA==.',
Mu='Mugidinhaa:BAAANQABCgcIBQAAAA==.Murdoky:BAAANQADCgEIAQABNQAECgUIBwAIAAAAAA==.Musleira:BAABNQAECn8cAAMRAAoK/A55RQC8AAARAAYK3w15RQC8AAANAAQKlw3PbwBxAAAAAA==.',
My='Myllene:BAAANQADCgUIBQABNQADCgcIDwAIAAAAAA==.Mynuza:BAAANQADCgYIBgAAAA==.Myranor:BAAANQAECgcIDQAAAA==.Myrzin:BAAANQADCggIDAAAAA==.Mythariel:BAAANQAECgQIBgAAAA==.Mythcut:BAAANQAECgQIDAAAAA==.Mythjegue:BAAANQAECgIIAgAAAA==.Myø:BAAANQAECgYIBgABNQAFFAQICgAeAGIUAA==.',
['Mä']='Mägö:BAAANQADCgEIAQAAAA==.Mällü:BAABNQAECn8XAAINAAgKWB2eQgBWAgANAAgKWB2eQgBWAgAAAA==.Mälthazar:BAABNQAECn8uAAMFAAoKBx2+CAARAwAFAAoKBx2+CAARAwAWAAQKKBVNIQHoAAAAAA==.Määt:BAAANQADCggICAABNQAFFAcIFAAdANYXAA==.',
['Må']='Mågus:BAABNQAECn8eAAIXAAgKVxqhCABUAgAXAAgKVxqhCABUAgAAAA==.',
['Mò']='Mòrgan:BAAANQAECgEIAQAAAA==.',
['Mø']='Mørgåna:BAABNQAECn8WAAICAAcKAwiCFQFoAQACAAcKAwiCFQFoAQAAAA==.',
Na='Naamt:BAAANQADCgYIBgAAAA==.Naero:BAAANQADCgQIBAAAAA==.Naerylla:BAAANQAECgIIAQABNQAECgUICAAIAAAAAA==.Nagashina:BAAANQADCggIFgAAAA==.Naizow:BAAANQAECgYIDwAAAA==.Namisan:BAAANQAECgIIAwAAAA==.Namuhß:BAAANQAECgQIEQABNQAECgoKHwAMAHIOAA==.Namøøh:BAABNQAECn8fAAMMAAoKcg41LgCpAQAMAAoKcg41LgCpAQAPAAYKbg8/FgArAQAAAA==.Naomiy:BAAANQADCgYIEAAAAA==.Naoto:BAAANQAECgQIDQAAAA==.Napru:BAAANQADCgEIAQAAAA==.Nardalan:BAAANQADCgQJBAABNQAECgUICgAIAAAAAA==.Narjes:BAAANQAECgYICQAAAA==.Nathrezim:BAAANQADCgcIEAAAAA==.Nathÿ:BAAANQADCgIIAgAAAA==.',
Ne='Necrogélido:BAAANQADCgYIEwAAAA==.Nefariio:BAAANQADCgQIBAAAAA==.Neninhaa:BAAANQADCgcJBQAAAA==.Neopaladino:BAAANQAECgQICQAAAA==.Nerlock:BAABNQAECn8XAAMjAAcKNwWUIwCYAAAjAAQKMAaUIwCYAAAaAAcKUwSzjQCFAAAAAA==.',
Ni='Nicom:BAAANQADCgYIBgAAAA==.Nightforms:BAAANQADCggIEAAAAA==.Nikity:BAABNQAECn8kAAIHAAkK+RoVHQCxAgAHAAkK+RoVHQCxAgAAAA==.',
No='Noahwallker:BAAANQAECgIIAgAAAA==.Noazard:BAAANQAECgYIEAAAAA==.Nopainnogain:BAAANQAECgEIAQAAAA==.Normalin:BAAANQADCgEIAQAAAA==.Nortênho:BAABNQAECn8jAAIPAAkKLx+HFAAjAwAPAAkKLx+HFAAjAwAAAA==.Nosferüs:BAAANQAECgQIBwAAAA==.Nossilat:BAABNQAECn83AAIHAAoKrCTSAgDHAwAHAAoKrCTSAgDHAwAAAA==.',
Nu='Nuit:BAAANQAECgMICQAAAA==.',
Ny='Nysthiael:BAABNQAECn8vAAMdAAgKQhxLUQBhAgAdAAgKQhxLUQBhAgAcAAEKAAAvNAAqAAAAAA==.Nyxicel:BAAANQAECgUIDQABNQAFFAMIBwAEADASAA==.',
['Nã']='Nãoseicurar:BAAANQAECgUIDQAAAA==.',
['Nä']='Närem:BAAANQAECggIAQAAAA==.Nästÿ:BAAANQAFFAIIAgAAAA==.',
['Ní']='Níih:BAAANQADCgYIBgAAAA==.',
['Nö']='Nöturnö:BAAANQABCgYICgAAAA==.',
['Ný']='Nýmm:BAAANQAECgUIEAAAAA==.',
Oc='Ocon:BAAANQABCgQIBgAAAA==.',
Od='Odigo:BAAANQADCgIIAgAAAA==.Odio:BAAANQADCgEIAQAAAA==.',
Ok='Okrigg:BAAANQADCggILwAAAA==.',
Ol='Oldcook:BAAANQABCgYIBQAAAA==.Oliele:BAAANQAECgUIDAAAAA==.',
On='Onixpala:BAAANQAECgQIBwABNQAECgYICQAIAAAAAA==.Onlydruix:BAAANQADCgIIAgAAAA==.',
Oo='Oorun:BAAANQADCgcIBwAAAA==.',
Op='Opsdesculpa:BAABNQAECn8dAAMKAAkKTRNIMgAVAgAKAAgKvRRIMgAVAgALAAIKJQ19TwA5AAAAAA==.',
Or='Organ:BAAANQAECgQIBQAAAA==.Orinoldo:BAABNQAECn8kAAICAAkKYiKmRQD4AgACAAkKYiKmRQD4AgAAAA==.',
Os='Osiria:BAAANQABCgYICAAAAA==.',
Ot='Otacki:BAAANQADCgIIAgAAAA==.Otherside:BAAANQAECgcIDQABNQAECgoKNwAYADEYAA==.Otávio:BAAANQAECgUICAAAAA==.',
Ow='Owlcapøne:BAAANQAECgcICgAAAA==.',
Ox='Oxentedragon:BAAANQADCgUIBAAAAA==.',
Oz='Ozyi:BAABNQAECn8dAAIVAAkKqhfdTwAsAgAVAAkKqhfdTwAsAgAAAA==.',
Pa='Pachiinko:BAAANQAECgYJAgAAAA==.Pain:BAAANQADCgQIBAAAAA==.Painkke:BAAANQAECggIEAAAAA==.Pajeh:BAAANQADCgYIBwAAAA==.Paladinjr:BAAANQAECgEIAQAAAA==.Paladinoroca:BAAANQADCggICAAAAA==.Pallacetamal:BAAANQAECgUICwAAAA==.Palluz:BAAANQAECgUICAABNQAFFAMIBgAOAMUSAA==.Palyz:BAAANQADCggIEAAAAA==.Pandaphorte:BAAANQAECgcIBwAAAA==.Panicdeath:BAAANQAECgEIAQAAAA==.Parafinaisis:BAABNQAECn8eAAIMAAkKBQoUIADNAAAMAAkKBQoUIADNAAAAAA==.Parafinared:BAAANQAECgcIDgAAAA==.Parrot:BAAANQADCgEIAQAAAA==.Pauladinho:BAAANQADCgIIAgAAAA==.Paupacino:BAAANQADCgUIBQAAAA==.',
Pe='Pedrosolock:BAAANQADCgYICQAAAA==.Peltrow:BAAANQAFFAEIAQAAAA==.Penndrive:BAAANQAECgQIBAAAAA==.Perciwal:BAAANQADCgQIBAABNQAECgYIDQAIAAAAAA==.Pesaa:BAABNQAECn8wAAIaAAoKHCCbJQAiAwAaAAoKHCCbJQAiAwAAAA==.',
Ph='Phanttoz:BAAANQADCgIIAgAAAA==.Phesti:BAAANQABCgEIAQAAAA==.Philii:BAAANQADCggIDQAAAA==.',
Pi='Pirizin:BAABNQAECn81AAIWAAoKhRoBWgCJAgAWAAoKhRoBWgCJAgAAAA==.Pirus:BAAANQADCgUIDwAAAA==.',
Po='Popopeka:BAAANQADCgcIBwAAAA==.Porcaleta:BAABNQAECn8jAAIBAAgKrhLVKQDZAQABAAgKrhLVKQDZAQAAAA==.Portal:BAAANQAECgUICgABNQAECgcICgAIAAAAAA==.Portelamage:BAABNQAECn8tAAICAAkKiiApRwD1AgACAAkKiiApRwD1AgAAAA==.Portheus:BAAANQADCggIFwAAAA==.',
Pr='Praeglacius:BAABNQAECn80AAMRAAoK7BQJUgAxAgARAAoK7BQJUgAxAgANAAIK/ADkHwEvAAAAAA==.Pravuls:BAAANQAECgEIAQAAAA==.Priapista:BAAANQAECgQIBQAAAA==.Priyla:BAAANQABCgcICgAAAA==.Prosaic:BAAANQADCggICAABNQADCggJDwAIAAAAAA==.Pråhå:BAAANQAECgQICQABNQAECgoKHwAMAHIOAA==.',
Ps='Psicopanda:BAABNQAECn8WAAMNAAkKZyP+DAD7AQANAAkKZyP+DAD7AQARAAIKmw4KDAFzAAAAAA==.Psychiclink:BAACNQAFFH8GAAIBAAMKgx7TBgClAAABAAMKgx7TBgClAAA1AAQKfxgAAgEACgotIhcJAEwDAAEACgotIhcJAEwDAAE1AAUUBQgMAAEAvCQA.',
Pu='Puffys:BAAANQAECgEIAQABNQAECgcIDQAIAAAAAA==.',
Pw='Pwcca:BAAANQAECgEIAgAAAA==.',
['Pó']='Pórthosrox:BAAANQAECgEIAgAAAA==.',
['Pú']='Púh:BAAANQADCgQIBAABNQAECgoKMAAJAOwaAA==.',
Qu='Queirozm:BAAANQADCgYIBgAAAA==.',
Ra='Radork:BAABNQAECn80AAIjAAoKuyAJAQArAgAjAAoKuyAJAQArAgAAAA==.Raewyn:BAACNQAFFH8HAAIQAAMKsAvRBgDEAAAQAAMKsAvRBgDEAAA1AAQKfyEAAhAACQoDHKgaALUCABAACQoDHKgaALUCAAAA.Rafaelgame:BAAANQAECgQICAAAAA==.Ragbear:BAAANQAECgIIAgABNQAFFAUIBAAIAAAAAA==.Ragdead:BAACNQAFFH8FAAIlAAIKoA2AJABrAAAlAAIKoA2AJABrAAA1AAQKfyYAAyUACgo1GPkzAD0CACUACQqeG/kzAD0CABAAAQpVADN1AAkAAAE1AAUUBQgEAAgAAAAA.Ragdöll:BAAANQAECgUICgAAAA==.Ragnaryos:BAAANQAECgEIAQABNQAFFAUIBAAIAAAAAA==.Ragosan:BAAANQAFFAUIBAAAAA==.Rairone:BAABNQAECn8ZAAInAAgK3A0+BwAKAgAnAAgK3A0+BwAKAgAAAA==.Raparigaloka:BAAANQAECgUIDwAAAA==.Rapunxel:BAABNQAECn83AAMYAAoKMRinBADcAgAYAAoKMRinBADcAgAdAAUKjwgn6gD1AAAAAA==.Rarkion:BAABNQAECn8nAAMmAAoKqxvZBgAZAwAmAAoKqxvZBgAZAwAfAAMK5hfNNgDeAAAAAA==.Raulthalas:BAAANQADCgYIBgAAAA==.Rawrii:BAAANQADCgUIBQAAAA==.Raynmake:BAAANQAECgEIAQABNQAECgcIBwAIAAAAAA==.',
Rb='Rbchama:BAABNQAECn8YAAMRAAUKYwYB1QDqAAARAAUKYwYB1QDqAAANAAEKTwDtOAEVAAAAAA==.',
Re='Rebelk:BAAANQAECgUIBgAAAA==.Redvil:BAAANQADCgUJBwAAAA==.Revoltedhunt:BAAANQAECggICwABNQAFFAcIGwAeAHsSAA==.Revolthed:BAACNQAFFH8bAAMeAAcKexIfBwDcAQAeAAYK3BUfBwDcAQAOAAQKeA01FQAVAQA1AAQKfysAAx4ACgrmIVsNAAgDAB4ACgrGIVsNAAgDAA4ABQrnGBG4AJQBAAAA.Reygon:BAAANQADCggIEwAAAA==.',
Rh='Rhaadora:BAAANQAECgQIBAAAAA==.Rhaek:BAAANQAECgUIBQAAAA==.Rhoghar:BAABNQAECn8uAAMHAAoKGRzFCgCgAQADAAgKZRjeCQBCAgAHAAoKGRzFCgCgAQAAAA==.Rhoghardruid:BAAANQAECgYIDQABNQAECgoKLgAHABkcAA==.',
Ri='Riachu:BAAANQADCgcIBwAAAA==.Riluyu:BAAANQAECgUIBQAAAA==.Rimetail:BAAANQABCgQIBAAAAA==.',
Ro='Rokalf:BAABNQAECn8iAAIkAAgKhBOXFgDBAQAkAAgKhBOXFgDBAQAAAA==.Rossiten:BAABNQAECn8YAAICAAcKexlnxAD7AQACAAcKexlnxAD7AQAAAA==.Roverandom:BAAANQADCgEIAQAAAA==.Rowgomary:BAAANQABCgQIBAAAAA==.Roöf:BAAANQAECgUIEQAAAA==.',
Ru='Rubya:BAAANQAECgMIAwABNQAECgkJFwAMAMATAA==.Runavento:BAAANQADCgIIAgAAAA==.Ruélatórta:BAAANQAECgQICAAAAA==.',
['Rä']='Räidela:BAABNQAECn9CAAMdAAkKxR/MBgA/AgAdAAkKxR/MBgA/AgAYAAEK2hL+dAA5AAAAAA==.',
Sa='Sagman:BAAANQAECgEIAQAAAA==.Sagädegemeos:BAABNQAECn8kAAIWAAgKhRmHMwBmAQAWAAgKhRmHMwBmAQABNQAECgoKKQAOAEwcAA==.Salasär:BAABNQAECn8lAAIaAAkKWhpuWACCAgAaAAkKWhpuWACCAgABNQAECgkJJgAOADwdAA==.Saleyi:BAAANQAECgYIDwAAAA==.Saluton:BAAANQAECgEIAgAAAA==.Samidemon:BAAANQAECgYIDgAAAA==.Sarashi:BAAANQADCgUIDAAAAA==.Sarte:BAAANQAECgUICgAAAA==.Sarzlok:BAAANQAECgUIBwAAAA==.',
Sc='Scarf:BAAANQABCgYIBwABNQAECgoKMQABABMVAA==.Scarioth:BAAANQADCgcIBwAAAA==.Schaeppi:BAAANQAECgEIAQAAAA==.Schiabelle:BAAANQADCggIFAAAAA==.Schiabellee:BAAANQADCggIEQAAAA==.Scoobydruida:BAABNQAECn8lAAIPAAoKrhJBEABYAQAPAAoKrhJBEABYAQAAAA==.Screan:BAABNQAECn8xAAIBAAoKExUlBgCXAQABAAoKExUlBgCXAQAAAA==.Scrøøge:BAAANQAECgQICgAAAA==.',
Se='Sealgaire:BAAANQADCggIDwAAAA==.Seelyvorey:BAABNQAECn8/AAQQAAoKRCHMGwCsAgAQAAoKGyDMGwCsAgAEAAcKJyRiJwCdAgAlAAUK6xyeGAAlAQAAAA==.Selph:BAABNQAECn8bAAIFAAoKKBqjEACUAgAFAAoKKBqjEACUAgAAAA==.Sengos:BAAANQAECgQIBQAAAA==.Sens:BAAANQADCgUIBQAAAA==.Sephhiroth:BAAANQADCgcICgAAAA==.Serrase:BAABNQAECn8jAAICAAkKCxorbQCkAgACAAkKCxorbQCkAgAAAA==.',
Sh='Shaado:BAAANQAECgQIBgAAAA==.Shadowwlock:BAAANQAFFAMIBAAAAA==.Shaldorei:BAAANQADCgUIBwAAAA==.Shalivane:BAAANQAECggIDwAAAA==.Shalquoir:BAAANQAECgcICAABNQAECgkJKQAfALwbAA==.Sharckaron:BAABNQAECn8YAAIlAAYKgQr1MwCmAAAlAAYKgQr1MwCmAAAAAA==.Shedleass:BAABNQAECn8eAAIDAAkKnBedCgAuAgADAAkKnBedCgAuAgAAAA==.Shendalar:BAABNQAECn89AAMCAAgKjBuxPABEAQACAAgKjBuxPABEAQAbAAMKvgRSCQB1AAAAAA==.Shigami:BAAANQADCgcIBwAAAA==.Shigare:BAAANQAECgEIAQAAAA==.Shuräto:BAAANQAECgMIAwAAAA==.Shywa:BAAANQADCgQIBgAAAA==.Shërëkhan:BAAANQAECgEIAQAAAA==.Shîvas:BAAANQAECgcICwAAAA==.Shöstakövich:BAAANQABCgEIAQAAAA==.Shøtinha:BAABNQAECn8tAAMeAAoKVB2sEwDDAgAeAAgK8R6sEwDDAgAOAAQKVhfzDwHmAAAAAA==.Shøwtime:BAAANQAECgEIAQABNQAECggIKAAPAA4aAA==.',
Si='Sianus:BAAANQAECgIJBAAAAA==.Sicarious:BAAANQADCgYICwABNQAECgoKLgAWAE8XAA==.Sicariuz:BAABNQAECn8uAAIWAAoKTxdPCQBLAgAWAAoKTxdPCQBLAgAAAA==.Silara:BAAANQADCgYICQAAAA==.Silves:BAAANQABCgYICgAAAA==.',
Sk='Skybourne:BAAANQADCgMIAwAAAA==.',
Sl='Slickdaddy:BAAANQAECgYIBgABNQAECgoKNAAJAIUgAA==.',
Sm='Smarcão:BAAANQAECgcIBwAAAA==.',
Sn='Snipinho:BAABNQAECn8VAAIOAAcKDx5EbgA1AgAOAAcKDx5EbgA1AgAAAA==.Snowtail:BAAANQAECgQIDQAAAA==.',
So='Sodragon:BAAANQADCgQIBAAAAA==.Sokun:BAAANQAECgEIAQAAAA==.Solaryel:BAABNQAECn8ZAAICAAoKywO0AAGNAQACAAoKywO0AAGNAQAAAA==.Solidheals:BAAANQAECgIIBgAAAA==.Sougigante:BAAANQAECgQIDAAAAA==.Souillé:BAAANQAECgYIBgABNQAFFAYIEQAHABobAA==.Soulbinder:BAAANQADCgIJAgAAAA==.Soupombagira:BAAANQAECgMIAwAAAA==.Sovaco:BAAANQAECgUIBQAAAA==.',
Sp='Spelldruid:BAAANQAECgUICAAAAA==.Spellshadown:BAABNQAECn8xAAIdAAoK0BdtHQB6AQAdAAoK0BdtHQB6AQAAAA==.Spellshamy:BAABNQAECn8YAAIRAAoKuREjFwBnAQARAAoKuREjFwBnAQAAAA==.Spratch:BAAANQADCgQIBAAAAA==.',
Sr='Srburns:BAAANQAECgMIAwAAAA==.',
Ss='Sshar:BAAANQADCgYIBgAAAA==.',
St='Stalinbrs:BAAANQAECgEIAQABNQAECgcIIAAlANEcAA==.Stalindinho:BAAANQAECgcIDQAAAA==.Stanyzz:BAAANQAECgMIBQABNQAFFAMIBgAPANgKAA==.Stelluna:BAAANQAECgMIAwAAAA==.Stormimrage:BAAANQAECgUIDgAAAA==.Strexx:BAABNQAECn8WAAInAAgKOg56AwBJAQAnAAgKOg56AwBJAQAAAA==.Stronoffgard:BAABNQAECn8sAAIaAAgKqB43GACmAQAaAAgKqB43GACmAQAAAA==.Stronq:BAAANQADCggIFgAAAA==.',
Su='Sulfur:BAAANQAECgIIBAAAAA==.Surionn:BAAANQADCgcIBwAAAA==.',
['Sà']='Sàgadegemeos:BAABNQAECn8pAAMOAAoKTBwbSgCPAgAOAAcKDCEbSgCPAgAeAAUKehMvTQD8AAAAAA==.',
['Sï']='Sïlent:BAAANQADCgMIBAABNQAECggIGQAdAHkXAA==.',
Ta='Tacka:BAAANQAECgEIAQAAAA==.Tafoki:BAABNQAECn8wAAMJAAoK7BrZCgDEAgAJAAoK7BrZCgDEAgARAAIKFhNr+wCcAAAAAA==.Taloco:BAAANQAECgUIBQAAAA==.Tangdebanana:BAAANQAECgUICQABNQAECgoKKwAeACUfAA==.Tankairotty:BAAANQAECgQICAAAAA==.Tankeda:BAAANQADCgMIAwAAAA==.Tanrity:BAABNQAECn8XAAMMAAkKwBPNJAD+AQAMAAkKwBPNJAD+AQASAAEKAABQSwAAAAAAAA==.Tassali:BAAANQADCgQIBgAAAA==.',
Td='Tdarklord:BAABNQAECn8ZAAIcAAYKhQSRFQDxAAAcAAYKhQSRFQDxAAAAAA==.',
Te='Temeloorego:BAAANQAECgMIAwAAAA==.Temkutemmedo:BAAANQAECgIIBQABNQAECgQIBQAIAAAAAA==.Tennkkar:BAAANQAECgEIAQAAAA==.Texugojogatv:BAABNQAECn8hAAICAAoKyRZUdACVAgACAAoKyRZUdACVAgAAAA==.Texugosa:BAAANQAECgEJAQAAAA==.',
Th='Thaeeria:BAAANQAECggIDAAAAA==.Thamihime:BAABNQAECn8lAAIOAAgKQBBrjwDqAQAOAAgKQBBrjwDqAQAAAA==.Tharizdum:BAAANQAECgQICgAAAA==.Theedarknes:BAAANQADCgUIBwAAAA==.Thlrall:BAAANQAECgQICAABNQAECgEIBgAIAAAAAA==.Thontonas:BAAANQADCgIIAgAAAA==.Thornus:BAACNQAFFH8HAAIjAAUKohkYAQBqAQAjAAUKohkYAQBqAQA1AAQKfx8AAiMACQqMIeEFALoCACMACQqMIeEFALoCAAAA.Thorudos:BAAANQADCgQIAgAAAA==.Thrandu:BAAANQADCgYIBgAAAA==.Thulin:BAAANQADCgMIAwAAAA==.Thunderburp:BAAANQAECgUIBQABNQAECggIJQAYAG8kAA==.Thuzalduum:BAAANQADCgIIAgAAAA==.Thânatos:BAAANQADCgIIAgAAAA==.',
Ti='Tiadobil:BAABNQAECn8XAAIoAAgKRwAAAAAAAAARAAgKRwAAAAAAAAAAAA==.',
To='Toni:BAAANQAECgUIEQAAAA==.Toshyo:BAABNQAECn8XAAIFAAoKuxsfDQDJAgAFAAoKuxsfDQDJAgAAAA==.Tostão:BAAANQADCgcIDwAAAA==.Touchhme:BAAANQAECgIIAgAAAA==.Toven:BAAANQADCgQIBAABNQADCgUICQAIAAAAAA==.Toykiller:BAAANQADCgYIDQAAAA==.',
Tp='Tprdmage:BAABNQAECn8bAAICAAYKPg7IjgCpAAACAAYKPg7IjgCpAAAAAA==.Tprdtank:BAAANQABCgQIBAAAAA==.',
Tr='Trighit:BAAANQADCgYICQAAAA==.Triixie:BAAANQAECgEIAQABNQAECgQIBwAIAAAAAA==.Trolhöl:BAABNQAECn8XAAIPAAgKRg1VTQCsAQAPAAgKRg1VTQCsAQAAAA==.Trollrogue:BAABNQAECn8XAAMNAAcKpwLU2wCwAAANAAYKsgHU2wCwAAARAAIKBwTUmQAtAAAAAA==.Trosobado:BAAANQAECgQICAAAAA==.Troyana:BAAANQADCggICAABNQAFFAcIFQAaAJ4XAA==.',
Tu='Tukiel:BAAANQAECgcIDAAAAA==.Tunkav:BAAANQABCgYJCQAAAA==.Tuska:BAAANQADCgUIBAAAAA==.',
Ty='Tyde:BAABNQAECn8fAAMMAAgKAxiuCwB/AQAMAAgKAxiuCwB/AQAPAAIKYQkYoQBbAAAAAA==.Typol:BAABNQAECn8lAAIXAAcKuQyTFwA+AQAXAAcKuQyTFwA+AQAAAA==.',
['Tó']='Tóten:BAAANQADCgUIBQAAAA==.',
['Tö']='Törtz:BAABNQAECn8dAAINAAgK+BceTQAvAgANAAgK+BceTQAvAgAAAA==.',
Ug='Ugabugah:BAAANQADCgIIAgAAAA==.',
Ul='Ulish:BAAANQAECgEIAQAAAA==.',
Um='Umburana:BAAANQADCgMIAwABNQADCgUICQAIAAAAAA==.Umehara:BAACNQAFFH8UAAMeAAYKDhvVCwCBAQAeAAUK3BfVCwCBAQAOAAMKNB2TCgC8AAA1AAQKfzkAAx4ACgo+HssHAFQDAB4ACgr3HcsHAFQDAA4AAQotHKGyAFEAAAAA.Umterço:BAAANQADCgcICwAAAA==.',
Un='Unbrøken:BAAANQAECgMICAAAAA==.Unclearnaldo:BAAANQADCgYIBgABNQAECgkJFgANAGcjAA==.',
Uo='Uolokoelfo:BAABNQAECn8rAAIaAAgKYiBoTACkAgAaAAgKYiBoTACkAgAAAA==.',
Ur='Urannia:BAABNQAECn8pAAIOAAkKAhXtZwBEAgAOAAkKAhXtZwBEAgAAAA==.Urgath:BAAANQAECgYIEQAAAA==.',
Ut='Uther:BAAANQAECgUICQABNQAECgkJOwAXAH0UAA==.',
Va='Vaehn:BAAANQAECgEIAwAAAA==.Valan:BAAANQAECgEIAgAAAA==.Valdeco:BAAANQADCggIDAAAAA==.Valdevino:BAABNQAECn8sAAITAAoKdBALVAAnAgATAAoKdBALVAAnAgAAAA==.Valk:BAAANQADCgIIAgAAAA==.Varyssa:BAAANQADCggIDgAAAA==.Vatoo:BAAANQAECgIIAgAAAA==.Vazgoroth:BAAANQADCgYICgAAAA==.',
Ve='Venator:BAABNQAECn8rAAQeAAoKJR/wBgB5AQAOAAUK2CHeoQDCAQAeAAoKdhzwBgB5AQAnAAMKMx6EDAAOAQAAAA==.Venonpoison:BAAANQADCgMIAgAAAA==.Vermeryn:BAAANQAECgUIDQAAAA==.Vermithór:BAAANQAECgYICwAAAA==.',
Vi='Viciadø:BAAANQAECggIDgABNQAFFAQICgAeAGIUAA==.Villalobos:BAAANQAECgcIDQAAAA==.Vits:BAABNQAECn8lAAMOAAoKJBhcUgB5AgAOAAoKJBhcUgB5AgAeAAYK/QeQKQBpAAAAAA==.',
Vo='Voidsurge:BAAANQAECgUIDwAAAA==.Voidwar:BAAANQAECgMIAwABNQAECgUIDwAIAAAAAA==.Vollin:BAABNQAECn8cAAQLAAoKBA3xHADrAQALAAoKBA3xHADrAQAKAAIKEgN3mABSAAApAAEKAAAeHQArAAAAAA==.Volrun:BAAANQADCggIDAAAAA==.Voragem:BAAANQAECgcIDgAAAA==.Vougam:BAAANQAECgIIBQAAAA==.',
Vu='Vulkova:BAAANQADCgQIBQAAAA==.',
Wa='Warlockdoido:BAAANQAECgQIBQAAAA==.Warlôka:BAAANQADCgUIBQAAAA==.Warriorbeso:BAAANQADCgIIAgAAAA==.',
Wi='Wiillord:BAAANQAECgQICAAAAA==.Willbm:BAABNQAECn88AAMWAAoK9w2kTQApAQAWAAoKwA2kTQApAQAFAAYKawwcQAD5AAAAAA==.Winnettou:BAABNQAECn8UAAIWAAgKJwWH7QBBAQAWAAgKJwWH7QBBAQAAAA==.Wipalogo:BAAANQAECgQIBQAAAA==.Wise:BAABNQAECn8vAAIWAAoKbSM6LAAXAwAWAAoKbSM6LAAXAwAAAA==.',
Wm='Wmana:BAABNQAECn8YAAICAAQKDxUsigCxAAACAAQKDxUsigCxAAAAAA==.',
Wr='Wrathi:BAAANQAECgQIBgAAAA==.',
Wu='Wuan:BAABNQAECn8kAAMhAAkKDRcBHwA4AgAhAAkKDRcBHwA4AgAiAAQKPQ8UNADKAAAAAA==.',
Xa='Xamanico:BAAANQAECgQICQAAAA==.Xanasmanas:BAAANQAECgcIEgAAAA==.Xazon:BAAANQADCgUIBwAAAA==.',
Xh='Xharlios:BAAANQAECgUIDwAAAA==.',
Xi='Xingorila:BAAANQADCgQIBAAAAA==.',
Xu='Xusp:BAAANQADCggIDgAAAA==.',
Xx='Xxbizu:BAAANQAECgUICAAAAA==.Xxnicoxx:BAAANQADCggIEQAAAA==.',
Xy='Xymor:BAACNQAFFH8TAAQmAAYKeA1zBQBjAQAmAAYKeA1zBQBjAQAgAAEKAACiDABGAAAfAAEKHwLsGQA5AAA1AAQKfysAAyYACgprH9AHAAADACYACgprH9AHAAADAB8AAQrlAotRACoAAAE1AAQKBggLAAgAAAAA.Xyuwan:BAAANQADCgUIBQAAAA==.',
['Xä']='Xäm:BAAANQAECgEIAQAAAA==.',
Ya='Yagaami:BAAANQADCgQIBAAAAA==.Yant:BAAANQADCgYIBgAAAA==.',
Ye='Yenniferxd:BAAANQABCgUIBQAAAA==.',
Yl='Ylanna:BAABNQAECn8hAAQTAAoKaRUGCQBWAgATAAgKJxYGCQBWAgAUAAcKAxUkCQDKAQABAAIK0wVFaABgAAAAAA==.',
Yn='Ynit:BAAANQAECgQIDAAAAA==.',
Yo='Yonnyson:BAAANQADCgEIAQAAAA==.Yoodoo:BAAANQABCgUJBQAAAA==.Yoriko:BAAANQAECgYICwAAAA==.Yorú:BAABNQAECn8mAAIWAAgKvRoZagBeAgAWAAgKvRoZagBeAgAAAA==.',
Yu='Yulaw:BAAANQADCgQIBAAAAA==.',
['Yá']='Yásuo:BAAANQAECgEIAQAAAA==.',
Za='Zambrotta:BAAANQADCgcIDAAAAA==.Zamii:BAAANQAECgQICgABNQAECgkJIQAOAGIcAA==.Zarik:BAAANQADCgcIBwAAAA==.',
Ze='Zenolis:BAAANQADCgcJFAAAAA==.Zerathir:BAAANQAECgQICgAAAA==.',
Zh='Zhalazar:BAAANQAECgUIDAAAAA==.Zhenb:BAAANQAECgIIAgAAAA==.',
Zi='Zigosmar:BAAANQAECgEJAQAAAA==.',
Zo='Zolet:BAAANQAECgUIBwAAAA==.Zones:BAAANQAECgUICgABNQAECggIHQANAPgXAA==.',
Zu='Zumbix:BAAANQADCgcIBwAAAA==.',
['Ág']='Ágripa:BAAANQABCgYIBgAAAA==.',
['Äl']='Älexandër:BAAANQADCgYIBgAAAA==.',
['Än']='Ängron:BAAANQAECgUIDgAAAA==.Änä:BAAANQADCggIFAAAAA==.',
['Är']='Ärthås:BAAANQAECgUICQAAAA==.',
['Äz']='Äzra:BAAANQAECgEIAgAAAA==.',
['Ær']='Ærikão:BAABNQAECn8UAAIaAAcKehg5kQDxAQAaAAcKehg5kQDxAQAAAA==.',
['Æt']='Ætherfel:BAAANQAECgIIAgAAAA==.',
['Ét']='Étel:BAAANQAECgEIAQAAAA==.',
['Ðr']='Ðrakko:BAAANQADCgQICAAAAA==.',
['Ðã']='Ðãntë:BAAANQAECgQIAgAAAA==.',
['Ök']='Ökamì:BAAANQADCgIIAgAAAA==.',
['Ör']='Örigem:BAABNQAECn8dAAMaAAoKYwo0HgCLAQAaAAoKYwo0HgCLAQAkAAEKAAC/SQAhAAAAAA==.',
['ßa']='ßardeolitico:BAAANQAECgEIAQABNQAECgkJKgAWAAIUAA==.',
['ßl']='ßlåkehunter:BAAANQAECgEIAQAAAA==.',
['ßr']='ßradvi:BAAANQADCggIDgAAAA==.ßrutalßarbie:BAAANQADCgYIBgAAAA==.',
['ßø']='ßøreas:BAAANQADCgQIBAAAAA==.',
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
