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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Hunter-BeastMastery','Priest-Holy','Unknown-Unknown','Druid-Feral','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Mage-Arcane','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Evoker-Devastation','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Mage-Frost','Shaman-Enhancement','Rogue-Outlaw','Druid-Guardian','Rogue-Assassination','Hunter-Marksmanship','Priest-Discipline','Evoker-Preservation','Hunter-Survival','Druid-Restoration','Warrior-Fury','Monk-Mistweaver',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aamix:BAACNQAFFH8QAAQBAAUKGQ79IwDiAAABAAMK1xP9IwDiAAACAAEKAAAJEABEAAADAAEKnQLXIwBBAAA1AAQKf0MAAwEACQq7HbktAMwCAAEACAqvHLktAMwCAAMABgo0DgIhAGcBAAAA.Aarom:BAACNQAFFH8XAAIEAAcK8xkUAwA7AgAEAAcK8xkUAwA7AgA1AAQKfyIAAgQACQq+I7QOAPMCAAQACQq+I7QOAPMCAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAABNQAECn8ZAAIFAAgKpR8ALADoAgAFAAgKpR8ALADoAgAAAA==.Abrakastaba:BAAANQAECgcIBwABNQAFFAUIEwAGALweAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aelyndra:BAAANQAECgYIBgAAAA==.Aequitas:BAAANQADCgcIDAAAAA==.Aerius:BAAANQAECgQICAAAAA==.',
Af='Affliclock:BAACNQAFFH8LAAICAAUKOBnfAAChAQACAAUKOBnfAAChAQA1AAQKfxwAAgIACQpkIaECAOwCAAIACQpkIaECAOwCAAAA.',
Ai='Aingerfal:BAAANQAECgUIBgABNQAECgYIBgAHAAAAAA==.',
Aj='Aj:BAAANQAECgYIDAAAAA==.',
Ak='Akasori:BAABNQAECn84AAIIAAkK0CJ4AgCMAwAIAAkK0CJ4AgCMAwAAAA==.Akisori:BAAANQAECgcICgABNQAECgkJOAAIANAiAA==.Akosori:BAAANQAECgIIAgABNQAECgkJOAAIANAiAA==.',
Al='Alistaier:BAAANQAECgEIAQABNQAECgkJLwAJANsaAA==.Alterboyy:BAAANQAECgUIEAAAAA==.Alîsonshammy:BAACNQAFFH8QAAMKAAUKNR3NBwDUAQAKAAUKNR3NBwDUAQALAAMKtgZzHQDKAAA1AAQKfyAAAwoACQq7IkgQAEADAAoACQq7IkgQAEADAAsACArlG4hOADoCAAAA.',
Am='Ambersulfr:BAAANQAECgYIEwAAAA==.Amrazz:BAABNQAECn8cAAMGAAkKbhl6JwDJAgAGAAkKbhl6JwDJAgAMAAIKQwdAaABbAAAAAA==.Amzey:BAEBNQAECn8wAAINAAkKnh/sLwAsAwANAAkKnh/sLwAsAwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcICwAHAAAAAA==.Andromeda:BAABNQAECn8sAAIOAAkKOhrRBwDXAgAOAAkKOhrRBwDXAgAAAA==.Anneaux:BAAANQAECgIJAgAAAA==.Antimortem:BAAANQADCgcIFgAAAA==.',
Ar='Aridillo:BAAANQAECgEIAQAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgUICwAAAA==.Astralus:BAAANQAECgQIDQAAAA==.Astramis:BAAANQAECgYIEwAAAA==.',
At='Athennaa:BAAANQADCgYIBgAAAA==.Atomicbarbie:BAABNQAECn8iAAIPAAkKdhjTSQCpAgAPAAkKdhjTSQCpAgABNQAFFAUIEAAKADUdAA==.Atriøx:BAAANQAECgIIAwAAAA==.Atziri:BAABNQAECn8tAAILAAkKyhkuNgCbAgALAAkKyhkuNgCbAgAAAA==.',
Av='Avalinia:BAAANQADCgIIAgAAAA==.',
Az='Azamia:BAAANQAECgQIDAABNQABCgIIAwAHAAAAAA==.',
Ba='Babyknife:BAAANQAECgIIAgABNQAFFAcIFwAEAPMZAA==.Backlash:BAABNQAECn8dAAIQAAgK3xg8HgBcAgAQAAgK3xg8HgBcAgAAAA==.Balzhac:BAABNQAECn8ZAAMRAAkKNSBrFQBTAgARAAcKDiFrFQBTAgASAAMKsB6dBgENAQAAAA==.Bam:BAAANQADCggICAABNQAFFAYIFwAJAIAdAA==.Bamplify:BAABNQAECn8VAAINAAkKZh19TQDmAgANAAkKZh19TQDmAgABNQAFFAYIFwAJAIAdAA==.Barrierbobo:BAAANQAECgYIEwAAAA==.Barthold:BAAANQADCggIHAAAAA==.',
Be='Beleaf:BAAANQAECgcIBgAAAA==.Bellmonte:BAAANQADCgYIDwABNQAECggIIQATAJsZAA==.Belmonk:BAAANQAECgQIBQAAAA==.Berdron:BAABNQAECn8zAAQDAAkKzxEOCgBWAgADAAkKzxEOCgBWAgABAAIKRAjjJQFrAAACAAEKAAAEMwAsAAAAAA==.',
Bi='Biden:BAAANQAECgMIBAAAAA==.',
Bl='Bladeliger:BAABNQAECn8sAAIUAAkKYRvvHQDYAgAUAAkKYRvvHQDYAgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECn8hAAIPAAkKiyTSHgA7AwAPAAkKiyTSHgA7AwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAABNQAECn8bAAMVAAcK/B3tCgBeAgAVAAcK/B3tCgBeAgAEAAEKAADLbQArAAAAAA==.Bonemair:BAACNQAFFH8dAAIWAAYK7htECQDCAQAWAAYK7htECQDCAQA1AAQKfy8AAhYACQqwIkASABkDABYACQqwIkASABkDAAAA.Boomguy:BAAANQADCgQIBAABNQAECggIIwAXAJMPAA==.Boredasf:BAAANQADCgYIBgAAAA==.Boricuazo:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIHgAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQAECggIDAAHAAAAAA==.',
Bu='Bubblehooker:BAAANQAECgIJAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAUIEwAGALweAA==.Bullteesta:BAAANQAECgQICgAAAA==.Burkhard:BAAANQADCggIBwAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgMIBQAAAA==.',
Ca='Caldec:BAACNQAFFH8dAAMYAAcKGiR9AADBAgAYAAcKGiR9AADBAgAZAAUKig93BwCgAQA1AAQKfzAAAhgACQp9JqMFAIQDABgACQp9JqMFAIQDAAAA.',
Ch='Chainizard:BAAANQAECggIDAAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECggIDAAHAAAAAA==.Chaosofelune:BAAANQAECgIIAgAAAA==.Chaosoflife:BAAANQAECgIJAgAAAA==.Chaosoflight:BAAANQAECgUIBQAAAA==.Cheeno:BAABNQAECn8oAAMQAAkKDyV5AgC1AwAQAAkKDyV5AgC1AwAaAAEKPSLlKgBYAAAAAA==.Chihiro:BAAANQAECgUIDQAAAA==.Chillyblinks:BAAANQAFFAIIBAAAAA==.Chillyfists:BAAANQADCgUIBQAAAA==.Chloris:BAAANQADCgMIAwABNQAECgQIBQAHAAAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Ci='Cinderheart:BAAANQABCgYIBgAAAA==.Ciymi:BAAANQAECgcICAABNQAFFAcICgANAP8SAA==.',
Cl='Clarabelle:BAACNQAFFH8KAAMNAAcK/xIxEADwAQANAAYKABUxEADwAQAbAAEK+QrDDQBUAAA1AAQKfyIAAw0ACQrIIs8fAFoDAA0ACQp2Is8fAFoDABsAAgo4I4wjAM0AAAAA.Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMJAwABNQAECggIDAAHAAAAAA==.Computer:BAACNQAFFH8FAAIBAAQK6w7DGQAsAQABAAQK6w7DGQAsAQA1AAQKfyMAAwMACQqCH/YEANECAAMACArtIfYEANECAAEACAq8HJdQAGACAAAA.Cootin:BAAANQAECggIDgAAAA==.',
Cp='Cpteddie:BAABNQAECn8eAAMRAAkKUR7REQCBAgARAAkKUR7REQCBAgASAAMKahF/TAGeAAABNQAFFAYIEwAWAEAaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Crelam:BAACNQAFFH8eAAIcAAcKpA7hAABIAgAcAAcKpA7hAABIAgA1AAQKfy8AAhwACQrLGyAMAKwCABwACQrLGyAMAKwCAAAA.Critherine:BAAANQAECgUIDgAAAA==.Cronatherus:BAAANQAECgEIAQAAAA==.Cruentis:BAABNQAECn8oAAIdAAgKjBhsBwA/AgAdAAgKjBhsBwA/AgAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIDwAHAAAAAA==.Crysus:BAAANQAECgcIDwAAAA==.',
Da='Dabo:BAABNQAECn8fAAIUAAkKnB0vGgD1AgAUAAkKnB0vGgD1AgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJIQAPAIskAA==.Darwin:BAABNQAECn8ZAAMZAAcKuhgEVQC6AQAZAAYKIRwEVQC6AQAYAAcKYg4hTgB2AQAAAA==.Dasmoodhayn:BAAANQAECgQIBwAAAA==.Davalanch:BAABNQAECn8fAAILAAkKxRY4QwBmAgALAAkKxRY4QwBmAgAAAA==.Dazizejr:BAACNQAFFH8HAAIWAAMKuB1HFAATAQAWAAMKuB1HFAATAQA1AAQKfy4AAhYACQr4JBIFAKADABYACQr4JBIFAKADAAAA.',
De='Deathisbrew:BAAANQAECggICAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Denïed:BAAANQADCgYICgAAAA==.Deonand:BAAANQADCggICQAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQADCgYICQAAAA==.',
Di='Dibstrum:BAAANQAECgUIDgAAAA==.Digduug:BAAANQAECgUIEQAAAA==.Dixqt:BAAANQAECgQICwAAAA==.',
Do='Dogfight:BAACNQAFFH8WAAQZAAYKDxV+CQB7AQAZAAUKDxV+CQB7AQAYAAEKYQAkIgAqAAAWAAEKAAAENQAoAAA1AAQKfysABBkACQqZHD0oAJYCABkACQqVGj0oAJYCABgAAgpHC8eaAFUAABYAAQoAAN/LAC8AAAAA.Doilookfatou:BAABNQAECn8aAAMeAAkKrhsCDACkAgAeAAgKDB8CDACkAgAUAAYKKgegbwAHAQAAAA==.',
Dr='Draxus:BAABNQAECn8ZAAIfAAcKuAYHVQBgAQAfAAcKuAYHVQBgAQAAAA==.Dresel:BAABNQAECn8dAAIFAAkKNRjxNgDDAgAFAAkKNRjxNgDDAgAAAA==.Drewpeebahlz:BAABNQAECn8YAAIXAAgKmBpRNACQAgAXAAgKmBpRNACQAgABNQABCgIIAgAHAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQAECgIIAgAAAA==.Durto:BAAANQADCgcIDQAAAA==.',
Dy='Dyami:BAABNQAECn8pAAMFAAkKJyIfNADNAgAFAAcKdiQfNADNAgAgAAYKZBvhLwDLAQAAAA==.Dynas:BAABNQAECn8YAAQhAAcKkApSEAAiAQAhAAYK/QtSEAAiAQAGAAUKkwTmwwDMAAAMAAIKcgHIjwAYAAAAAA==.',
Ea='Earthcake:BAACNQAFFH8FAAMLAAMKnQxGJACYAAALAAIKnQxGJACYAAAKAAEKeQQrLQA/AAA1AAQKfywAAwsACQpXIQMVAEkDAAsACQpXIQMVAEkDAAoAAwojB1r4AHQAAAAA.',
Ed='Eddielich:BAACNQAFFH8TAAIWAAYKQBq9BgD4AQAWAAYKQBq9BgD4AQA1AAQKfyQAAhYACQrkJYgJAGoDABYACQrkJYgJAGoDAAAA.Eddiepope:BAAANQABCgIIAgABNQAFFAYIEwAWAEAaAA==.Eddieteddie:BAAANQAECgcIBwABNQAFFAYIEwAWAEAaAA==.',
Eg='Eggfumonk:BAAANQAECggIDAAAAA==.',
Eh='Ehlo:BAAANQADCgEIAQABNQADCgcIBwAHAAAAAA==.',
El='Elasmon:BAAANQAECgcIEwAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQAECgIIAgAAAA==.Ellan:BAABNQAECn8ZAAINAAkK3hRslwBRAgANAAkK3hRslwBRAgAAAA==.',
Em='Emongalkar:BAAANQADCgQIBAAAAA==.',
Er='Erragal:BAAANQAECgIIAgAAAA==.',
Es='Escanõr:BAABNQAECn8XAAISAAkK1hKugwAcAgASAAkK1hKugwAcAgAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.Faustyne:BAAANQAECgcIEQABNQAFFAUICAAFAGkTAA==.',
Fe='Felir:BAAANQADCggICAAAAA==.Felover:BAAANQAECgMIAwAAAA==.Felurián:BAAANQAECgUICgABNQADCgcIGgAHAAAAAA==.Fexli:BAAANQADCgcIEQAAAA==.',
Fi='Fireteeth:BAAANQADCggIEwAAAA==.Fiverunner:BAAANQADCgQIBAAAAA==.Fizc:BAAANQADCgcIBwAAAA==.',
Fl='Flurtty:BAAANQADCgYIDwAAAA==.',
Fo='Folklore:BAABNQAECn8XAAIeAAcKcRQBHwCgAQAeAAcKcRQBHwCgAQAAAA==.Forklift:BAAANQAECgIIAgABNQAECgkJKQAiAKofAA==.Foxrocks:BAAANQABCgMIAwAAAA==.',
Fr='Frighrish:BAAANQAECgEIAQAAAA==.Frigomortis:BAAANQAECgUICAABNQAECgUIDQAHAAAAAA==.Frozown:BAABNQAECn8fAAINAAcK6hX72gDPAQANAAcK6hX72gDPAQAAAA==.Fruits:BAAANQAECgUICgAAAA==.Fruitsack:BAAANQAECgcIDQABNQAECgUICgAHAAAAAA==.',
Ft='Ftfw:BAAANQAECgYIDgAAAA==.',
Fu='Funfanfare:BAAANQAECgYICAAAAA==.Furrylife:BAAANQAECgIIAgAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQAHAAAAAA==.Fuzzychin:BAAANQAECgYIDQABNQAFFAIIBAAHAAAAAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAABNQAECn8gAAIjAAgKdhN7BgAtAgAjAAgKdhN7BgAtAgABNQAFFAcIHgAcAKQOAA==.Gardettos:BAABNQAECn8pAAIiAAkKqh+hCQAIAwAiAAkKqh+hCQAIAwAAAA==.Gargingoyles:BAAANQADCgIJAgAAAA==.',
Gh='Gharghael:BAAANQAECgQICgAAAA==.Ghostthunter:BAAANQADCgQIBAABNQAECggIFAAYAFYdAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAABNQAECn8XAAIRAAcKAR0VGAA1AgARAAcKAR0VGAA1AgABNQAFFAYIHQAWAO4bAA==.Glimmer:BAAANQADCggIDQAAAQ==.',
Gn='Gnxrli:BAEANQADCgIIAgABNQAFFAIIBgAEALsiAA==.Gnxrly:BAEANQAECgEIAQABNQAFFAIIBgAEALsiAA==.Gnxrr:BAECNQAFFH8GAAIEAAIKuyL0DADKAAAEAAIKuyL0DADKAAA1AAQKfykAAgQACQryJFMDAKEDAAQACQryJFMDAKEDAAAA.',
Go='Gooncaine:BAAANQAECgYICgAAAA==.Gorammasta:BAAANQAECgcIBwABNQAECgcIEwAHAAAAAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQAECgUICwAAAA==.',
Gr='Gregorz:BAAANQAECgIIAgAAAA==.Greyanna:BAAANQAECgYIEQAAAA==.Gridon:BAAANQADCgYIBgAAAA==.Gripguy:BAAANQADCggICAABNQAECggIIwAXAJMPAA==.Gromthrall:BAAANQAECgYIDAAAAA==.',
Gw='Gworp:BAAANQAECgIJAwAAAA==.Gwynhwyfar:BAAANQAECgIIAgABNQAECggIGgAFABAWAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hangsut:BAAANQABCgQICgAAAA==.',
Hb='Hbhealthen:BAACNQAFFH8cAAIiAAcK9BkdAwBiAgAiAAcK9BkdAwBiAgA1AAQKfz0AAyIACQqRI1YDAIIDACIACQqRI1YDAIIDABMAAgrnEBkzAHEAAAAA.',
He='Hellhore:BAAANQAECgMICwAAAA==.Hemila:BAAANQAECgYICQABNQAECggICQAHAAAAAQ==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAAANQAECggIEgAAAA==.',
Ho='Holdenc:BAAANQAECgMIBQABNQAECgkJLAAKAOAdAA==.Hoodz:BAABNQAECn8rAAIPAAkK5SIKEwBvAwAPAAkK5SIKEwBvAwAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQAECgUIDwAAAA==.',
Hu='Huatli:BAAANQADCggIEgAAAA==.Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICAAAAA==.',
Ic='Icerod:BAAANQADCgUIBQABNQAECgUICgAHAAAAAA==.',
Id='Idtrapdat:BAACNQAFFH8HAAMFAAMKoh8xHwC0AAAFAAIKoh8xHwC0AAAgAAIKIQ4jHACMAAA1AAQKfy8AAwUACQrjJMoQAF4DAAUACQrjJMoQAF4DACAAAgo8FHdqAH4AAAAA.',
Il='Illyana:BAABNQAECn8WAAMYAAgKryP/DwANAwAYAAgKHiL/DwANAwAZAAYK5yFLNABWAgAAAA==.Ilse:BAABNQAECn8sAAIXAAkKFR78GAATAwAXAAkKFR78GAATAwAAAA==.',
Im='Imagined:BAACNQAFFH8eAAMNAAcKLRWLBQBlAgANAAcKLRWLBQBlAgAbAAIK/QeGCQB9AAA1AAQKfy0AAg0ACQq1HopWANMCAA0ACQq1HopWANMCAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIDAAAAA==.Infidelic:BAAANQADCgYICwABNQAECgUIDwAHAAAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAABNQAECn8fAAIBAAkK2g6KXgA4AgABAAkK2g6KXgA4AgAAAA==.Ivannalot:BAAANQADCggIGgAAAA==.Ivracha:BAAANQAECgEJAQAAAA==.',
Ja='Jage:BAAANQAECgcICwAAAA==.Jarsham:BAAANQAECgUIDQAAAA==.Jaràdan:BAAANQAECggIDgABNQAECgkJKgANAG8ZAA==.Jawshua:BAAANQAECgEIAQAAAA==.',
Je='Jeff:BAABNQAECn8wAAIPAAkK6R99KwALAwAPAAkK6R99KwALAwAAAA==.',
Jo='Joran:BAAANQAECgQICwAAAA==.Jordie:BAAANQADCgIIAgAAAA==.Joredin:BAAANQADCgcIBwAAAA==.Jorlannee:BAAANQADCgEIAQABNQADCgcIGgAHAAAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Ju='Judelene:BAAANQAECgQIBAAAAA==.',
Jw='Jwrs:BAABNQAECn8ZAAIPAAcKkxQdpAC+AQAPAAcKkxQdpAC+AQAAAA==.',
['Jï']='Jïbril:BAABNQAECn8iAAIWAAkKbxhpLwBSAgAWAAkKbxhpLwBSAgAAAA==.',
Ka='Kabbala:BAAANQAECgcIDgABNQAFFAcIHgANAC0VAA==.Kahlani:BAABNQAECn8sAAIKAAkKuRG2VQAOAgAKAAkKuRG2VQAOAgAAAA==.Kahlua:BAAANQAECgQIBQAAAA==.Kailan:BAABNQAECn8YAAIQAAYKXxpwKAD9AQAQAAYKXxpwKAD9AQABNQAECgkJMQAMAIwhAA==.Kalathios:BAAANQABCgIIAgABNQAECgQIBQAHAAAAAA==.Kaldro:BAAANQAECgYICgAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAABNQAECn8qAAIVAAkKXw3bEQDFAQAVAAkKXw3bEQDFAQAAAA==.Kano:BAAANQAECgMIBAAAAA==.Kariana:BAABNQAECn8vAAMLAAkKmhVFQgBpAgALAAkKmhVFQgBpAgAKAAgKyQQmogAsAQAAAA==.Kathry:BAAANQADCggIGgAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAABNQAECn8qAAIkAAkKAxPTHwApAgAkAAkKAxPTHwApAgAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keme:BAAANQADCggICAABNQAECgUICQAHAAAAAA==.Keybricker:BAAANQAECgYIBgABNQAFFAUIEwAGALweAA==.Keymebrah:BAABNQAECn8bAAMNAAkKmhI2wgD+AQANAAkKHBI2wgD+AQAbAAMKnRFMLgCIAAAAAA==.',
Ki='Killeh:BAAANQADCggIFAAAAA==.',
Ko='Korda:BAAANQAECgIIAgAAAA==.Korinä:BAABNQAECn8aAAIfAAgKVwt3PgDPAQAfAAgKVwt3PgDPAQAAAA==.Kosh:BAAANQAECgIIAgAAAA==.Koyra:BAACNQAFFH8ZAAITAAcKCSUdAAAAAwATAAcKCSUdAAAAAwA1AAQKfy0AAhMACQooJvUBAJ4DABMACQooJvUBAJ4DAAAA.',
Kr='Kreyden:BAAANQAECgMIAwAAAA==.Krump:BAAANQAECgEIAQAAAA==.',
Ku='Kubbles:BAAANQADCggICAAAAA==.Kubs:BAAANQADCgcIDAAAAA==.Kubwa:BAAANQABCgcIDwAAAA==.Kungfugimp:BAAANQAECgcIDwAAAA==.Kurral:BAACNQAFFH8dAAMUAAcK0RExBwAVAgAUAAcK0RExBwAVAgAkAAQK/AAfDgC+AAA1AAQKfysAAxQACQrUHt8bAOcCABQACQrUHt8bAOcCACQABArrBJ1aAJgAAAAA.Kurralium:BAABNQAECn8aAAIbAAgKww3HDgC8AQAbAAgKww3HDgC8AQABNQAFFAcIHQAUANERAA==.Kurstina:BAAANQADCgYICQAAAA==.Kuzushi:BAAANQAECggIDQAAAA==.',
Ky='Kyramus:BAAANQAECgYIEwAAAA==.',
La='Laconia:BAABNQAECn8hAAITAAgKmxmtDQCDAgATAAgKmxmtDQCDAgAAAA==.Lashstorm:BAAANQAECgcIDAAAAA==.Lattsatnar:BAAANQAECgQICwAAAA==.',
Le='Lebron:BAAANQAECggIDgAAAA==.Lelesobi:BAAANQADCgUIBgAAAA==.Lennel:BAAANQAECgQICQAAAA==.Lewd:BAAANQAECggIAgAAAA==.',
Lg='Lga:BAAANQADCgYIEAAAAA==.',
Li='Lilsnick:BAAANQAECgUIDQABNQAECgUIDwAHAAAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQAHAAAAAA==.',
Ll='Llanthyl:BAABNQAECn8ZAAIlAAcKURBAEAChAQAlAAcKURBAEAChAQAAAA==.',
Lo='Lockbawx:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.',
Lu='Lucía:BAABNQAFFH8GAAIWAAUKCxffDgBhAQAWAAUKCxffDgBhAQAAAA==.Luecien:BAAANQADCgUIBQAAAA==.Lunafalia:BAABNQAECn8uAAIbAAkKQhjYBQCsAgAbAAkKQhjYBQCsAgAAAA==.Lupon:BAAANQAECggICAAAAA==.Lurosa:BAACNQAFFH8MAAIkAAUKcx+1BADVAQAkAAUKcx+1BADVAQA1AAQKfycAAiQACQoPJncAAOUDACQACQoPJncAAOUDAAAA.Luxeria:BAAANQAECgcIDQAAAA==.Luxray:BAAANQABCggIFQAAAA==.',
Lv='Lvck:BAEANQADCgcIBwABNQAFFAIIBgAEALsiAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBwAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgYICwAAAA==.',
Ma='Macready:BAACNQAFFH8JAAIOAAMK5yFGAwAsAQAOAAMK5yFGAwAsAQA1AAQKfysAAg4ACQqoJbIGAPQCAA4ACQqoJbIGAPQCAAAA.Madmimm:BAAANQADCgcIBwAAAA==.Magenin:BAAANQAECgIIAgAAAA==.Maggotgut:BAAANQAECgQICAAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairbear:BAAANQAECgcIBwABNQAFFAYIHQAWAO4bAA==.Mairiachi:BAAANQAECgEIAQABNQAFFAYIHQAWAO4bAA==.Maltessa:BAAANQADCgUICgABNQAECgkJMQAMAIwhAA==.Marload:BAACNQAFFH8OAAMFAAUK+xGAEwAmAQAFAAQK+xGAEwAmAQAgAAQK3w0jFAD4AAA1AAQKfzMAAyAACQqVHusZAIQCACAACQpGFusZAIQCAAUACQrQHeVNAIICAAAA.Mathy:BAAANQAECggIEQAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.Melreu:BAAANQADCgEIAQABNQAECgkJKAAQAA8lAA==.',
Mi='Midletons:BAAANQAECgUICQAAAA==.Minikub:BAABNQAECn8dAAIEAAcKBA18NwBTAQAEAAcKBA18NwBTAQAAAA==.Mischievous:BAAANQAECggICAAAAA==.Mixxy:BAAANQAECgQIBwABNQAFFAcIFwAEAOAXAA==.Mizu:BAAANQAECgUICQAAAA==.',
Mn='Mnzn:BAAANQADCggIGgAAAA==.',
Mo='Moobubble:BAAANQAECggIEAABNQAFFAMIBQALAJ0MAA==.Moodroo:BAAANQAECgUICwAAAA==.Moonanoke:BAAANQAECgUICwAAAA==.Moovoker:BAABNQAECn8vAAIiAAkK3yEnBQBZAwAiAAkK3yEnBQBZAwAAAA==.Morseques:BAABNQAECn8qAAMZAAkKdiIiDABYAwAZAAkKdiIiDABYAwAWAAEKAACNsgBhAAAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAACNQAFFH8OAAMZAAYKyhoiBgC8AQAZAAUKyhoiBgC8AQAWAAEKAABQIwBuAAA1AAQKfzAAAxkACQpjJjUEALADABkACQpjJjUEALADABgAAwoeFbJ4ALkAAAAA.Muguda:BAAANQADCgMIAwAAAA==.',
Mx='Mxkebfistin:BAACNQAFFH8XAAIEAAcK4Bc3AwA0AgAEAAcK4Bc3AwA0AgA1AAQKfygAAgQACQqcIdYLABYDAAQACQqcIdYLABYDAAAA.Mxkebspinnin:BAAANQADCggICAABNQAFFAcIFwAEAOAXAA==.',
Na='Narama:BAACNQAFFH8XAAMBAAYKjQXlGQArAQABAAUKqQXlGQArAQADAAIKZQPmEgB9AAA1AAQKfy0ABAMACQpDE00lAEgBAAEACQrtEcJkACgCAAMABgpMDk0lAEgBAAIAAQoAAJ80ACYAAAAA.',
Ne='Nekka:BAAANQAECgUIEAAAAA==.Nethanos:BAAANQAECgQICgABNQAECgUICAAHAAAAAA==.Neverrmore:BAAANQAECgEIAQAAAA==.',
Ni='Ninæ:BAACNQAFFH8QAAIiAAUKPBc/CQCaAQAiAAUKPBc/CQCaAQA1AAQKfycAAiIACQr1IBcFAFoDACIACQr1IBcFAFoDAAAA.Nitewïng:BAAANQAECgUIFAABNQADCggIDQAHAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgQICQAHAAAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAABNQAECn8YAAINAAcKkR1LsgAdAgANAAcKkR1LsgAdAgAAAA==.',
Ny='Nyoz:BAAANQAECgUICgAAAA==.Nyxxadra:BAABNQAECn8tAAIBAAkKIRBNawAXAgABAAkKIRBNawAXAgAAAA==.',
Oa='Oakshion:BAAANQAECgEIAQAAAA==.',
Om='Omegadeed:BAABNQAECn8pAAMBAAkKQxWgUQBdAgABAAkKQxWgUQBdAgADAAEKAAAOawBJAAAAAA==.',
On='Onne:BAAANQAECgIIAgAAAA==.',
Or='Orcinus:BAACNQAFFH8FAAIiAAIKKQGtFgBhAAAiAAIKKQGtFgBhAAA1AAQKfyQAAiIACQrWEOsXADsCACIACQrWEOsXADsCAAAA.Orcishfist:BAAANQAECgcIDgAAAA==.Orvar:BAAANQAECgQIBQABNQABCgIIAgAHAAAAAA==.',
Pa='Pakaru:BAABNQAECn8kAAISAAkK1xjtUwCWAgASAAkK1xjtUwCWAgAAAA==.Pam:BAACNQAFFH8XAAIJAAYKgB3xBAANAgAJAAYKgB3xBAANAgA1AAQKfygAAwkACQqOJKIPACIDAAkACQqOJKIPACIDABAAAgpdHr9WAKoAAAAA.Parathin:BAAANQADCggIFAAAAA==.',
Pe='Peorä:BAABNQAECn8gAAMGAAgKhgvmewChAQAGAAgKhgvmewChAQAMAAcKZwO7SQDuAAAAAA==.Perfectdark:BAACNQAFFH8eAAIQAAcK2B01AQCSAgAQAAcK2B01AQCSAgA1AAQKfzEAAxAACQp8JIoGAGgDABAACQp8JIoGAGgDAAkAAgrBIF5uALoAAAAA.Perse:BAAANQAECgUIBgAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQAECgUIDQAHAAAAAA==.Pheadas:BAAANQADCgUJBQAAAA==.Phleez:BAAANQADCggICwABNQAECgIIAgAHAAAAAA==.',
Pi='Picklesnrye:BAAANQADCgMIAwAAAA==.Pieper:BAABNQAECn8aAAIFAAgKEBa7bAA2AgAFAAgKEBa7bAA2AgAAAA==.Pipa:BAABNQAECn8xAAIKAAkKZiQzBQCdAwAKAAkKZiQzBQCdAwAAAA==.Pippit:BAABNQAECn8fAAIXAAgK3xKOXwD3AQAXAAgK3xKOXwD3AQABNQAECgkJMQAKAGYkAA==.',
Pl='Plokane:BAABNQAECn8mAAMBAAgKfiCMUABgAgABAAcKZx6MUABgAgADAAIK9CMSQADBAAAAAA==.',
Po='Poacher:BAAANQADCgMIBAAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgQIBgABNQAECggIDgAHAAAAAA==.Powar:BAAANQAECgcIDwAAAA==.',
Pr='Provence:BAAANQADCgYICgAAAA==.',
Py='Pyreynna:BAAANQAECgUIDgAAAA==.',
['Pè']='Pèppèr:BAABNQAECn8ZAAISAAcKTRU9oQDaAQASAAcKTRU9oQDaAQABNQAECgkJLAAOADoaAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ragarn:BAAANQAECgEIAQABNQAECgkJLAAKAOAdAA==.Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAABNQAECn8ZAAIKAAcK9BKWewCVAQAKAAcK9BKWewCVAQAAAA==.Rapsodia:BAAANQAECgUICQABNQAFFAcICgANAP8SAA==.Raschild:BAAANQAECgcIEgAAAA==.',
Re='Realfrojd:BAABNQAECn8yAAIWAAgKyAh4YQBpAQAWAAgKyAh4YQBpAQAAAA==.Regginunchuk:BAABNQAECn8wAAIEAAkKmx+JCgAoAwAEAAkKmx+JCgAoAwAAAA==.Releronastus:BAAANQAECgQICAAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECn81AAMSAAkKAx8nPwDVAgASAAkK/RsnPwDVAgARAAgKpx4kEgB8AgAAAA==.Reyson:BAABNQAECn8rAAINAAkKaw1XsAAhAgANAAkKaw1XsAAhAgAAAA==.',
Rh='Rhunon:BAABNQAECn8/AAIWAAkKnx76GQDcAgAWAAkKnx76GQDcAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rimlaol:BAAANQADCggICQAAAA==.Rinchi:BAAANQADCgYIDAAAAA==.Rinthia:BAABNQAECn8xAAIMAAkKjCFcBgBxAwAMAAkKjCFcBgBxAwAAAA==.Ripyeet:BAABNQAECn8cAAISAAgKchjpgQAgAgASAAgKchjpgQAgAgAAAA==.',
Ro='Rol:BAAANQAECgUIDQAAAA==.Rolden:BAAANQADCggIJwAAAA==.',
Ru='Rukaji:BAABNQAECn8bAAIPAAcK1Bf5kgDoAQAPAAcK1Bf5kgDoAQAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIFQABNQADCgQIBQAHAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAABNQAECn8qAAIPAAkK0xY7WgB6AgAPAAkK0xY7WgB6AgAAAA==.Samayel:BAAANQAECgMIBAAAAA==.Sarkang:BAABNQAECn8tAAMWAAgKxRaQNAA4AgAWAAYKER6QNAA4AgAZAAgKng5SXACbAQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgkJLAAOADoaAA==.',
Sc='Schmeebie:BAAANQAECgIIAgABNQAECgUICQAHAAAAAA==.Schutze:BAACNQAFFH8HAAIjAAQKVhbiAABiAQAjAAQKVhbiAABiAQA1AAQKfx4AAiMACQqCJF4CABoDACMACQqCJF4CABoDAAAA.',
Sd='Sdadfeg:BAABNQAECn8pAAIcAAkK/yTlAADBAwAcAAkK/yTlAADBAwAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECgkJJwAFAPEZAA==.Senco:BAAANQAECgQICQAAAA==.Sephroth:BAAANQAECgEIAQABNQAECgIIAgAHAAAAAA==.',
Sh='Shabobado:BAABNQAECn8ZAAINAAgKxxeHmwBJAgANAAgKxxeHmwBJAgAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shammin:BAAANQAECgQIBAAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shayder:BAAANQAFFAEIAQAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shura:BAAANQAFFAEIAQAAAA==.Shuten:BAAANQAECgUICAAAAA==.Shxdow:BAAANQADCgEJAQAAAA==.Shøck:BAAANQAECgMIAwAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQAECgcICAAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Silverie:BAAANQAECgQICAABNQAECgkJMQAKAGYkAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinill:BAAANQADCggIDwAAAA==.Sinterklaas:BAABNQAECn8eAAIKAAkKWRY2QgBVAgAKAAkKWRY2QgBVAgAAAA==.',
Sk='Skjald:BAAANQAECgMJAwABNQAFFAUIEwAGALweAA==.Skylee:BAABNQAECn8aAAMNAAgKWhr5rQAlAgANAAcK8Bv5rQAlAgAbAAEKahIIQQBAAAAAAA==.',
Sl='Slark:BAAANQAECgcIEwAAAA==.Slawth:BAABNQAECn8WAAMZAAgKuQ+OVwCvAQAZAAgKuQ+OVwCvAQAWAAEKEQTAywAwAAAAAA==.Slayermonde:BAAANQAECgIIAgAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAABNQAECn8aAAIPAAgKmRhUcgA6AgAPAAgKmRhUcgA6AgAAAA==.Smeyplus:BAACNQAFFH8SAAMSAAYKriB3BwDTAQASAAUKriB3BwDTAQARAAEKAAD5DABxAAA1AAQKfyoAAxIACQrlJvUEANEDABIACQrlJvUEANEDABEAAQoAADhaAG8AAAAA.',
Sn='Snaccident:BAAANQAECggIDQAAAA==.Snickeris:BAAANQAECgUIDwAAAA==.Snofawl:BAAANQAECgYIDQAAAA==.Snoranir:BAAANQAECgYIDwAAAA==.Snurchbasher:BAAANQAECgUIEQAAAA==.',
Sp='Spanfrontals:BAAANQAECgYIBgABNQAFFAUIEwAGALweAA==.Sparrowhawk:BAAANQABCgQIBAAAAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAABNQAECn8sAAIKAAkK4B1QJADTAgAKAAkK4B1QJADTAgAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQADCgMIBAAAAA==.',
St='Stars:BAABNQAECn8YAAMJAAgKzhhEKwBEAgAJAAgKzhhEKwBEAgAQAAYK+QkOQgA5AQABNQAFFAMIBwAFAKIfAA==.Sterra:BAAANQADCgcIBwAAAA==.Stinkiepete:BAAANQAECgIIAgAAAA==.',
Su='Sureno:BAAANQAECgcIEwAAAA==.',
Sw='Swaglordxtqt:BAAANQAECgMIAgAAAA==.',
Sx='Sxyhealz:BAAANQAECgQIBAAAAA==.Sxyheålz:BAACNQAFFH8GAAIGAAQKaAiiGgARAQAGAAQKaAiiGgARAQA1AAQKfy0AAgYACQqPF40zAJcCAAYACQqPF40zAJcCAAAA.',
Ta='Taffybonkins:BAAANQAECgQIBAAAAA==.Taliä:BAAANQADCgcIDAAAAA==.Tanndari:BAAANQADCgcIHQAAAA==.Tartare:BAAANQAECgcIDQAAAA==.Tashaman:BAACNQAFFH8MAAMKAAUKOw2sDgBeAQAKAAUKOw2sDgBeAQALAAEKAABpNgAzAAA1AAQKfzgAAwoACQrRFKlVAA4CAAoACQrRFKlVAA4CAAsABQq7Be7WAOIAAAAA.',
Te='Teajuan:BAAANQADCgcIBwAAAA==.Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQADCggIDwAAAA==.Teriheals:BAAANQAECgQICQAAAA==.',
Th='Thejorlane:BAAANQADCgcIGgAAAA==.Thiccholy:BAACNQAFFH8NAAMXAAUKwgpSDgB4AQAXAAUKwgpSDgB4AQARAAIKfwJNDwBNAAA1AAQKfygABBcACQrpFvNSAB4CABcACArOFfNSAB4CABEACQrdDKMqAIQBABIABgpBCf4UAfUAAAAA.Thiccshields:BAAANQADCgQIBAABNQAFFAUIDQAXAMIKAA==.Thicctotemz:BAAANQAECgUICwABNQAFFAUIDQAXAMIKAA==.Thogo:BAABNQAECn8rAAIlAAkKaB/LAgBAAwAlAAkKaB/LAgBAAwAAAA==.',
Ti='Tikaa:BAAANQAECgUICgAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAABNQAECn8qAAIRAAkK8CT2AgCWAwARAAkK8CT2AgCWAwABNQAFFAUIBgAWAAsXAA==.Tomerto:BAABNQAECn8sAAMXAAkKSx49FAAvAwAXAAkKSx49FAAvAwASAAUK/QwoFgHzAAAAAA==.Toobeastly:BAABNQAECn8eAAQLAAkKqh4mJgDpAgALAAgKuyAmJgDpAgAcAAQKMRUhIwAiAQAKAAEKRhXoGgExAAAAAA==.Toonerdin:BAAANQAECgUIDgAAAA==.Toymonkey:BAAANQADCggIDQAAAA==.',
Tr='Tril:BAAANQAECgIJAwAAAA==.Trolazo:BAAANQADCgIIAgAAAA==.Trox:BAAANQADCgcIEwAAAA==.Trydrodruid:BAAANQAECgYIEgABNQAECggICQAHAAAAAA==.Tryingmybest:BAACNQAFFH8TAAIGAAUKvB5ICQDvAQAGAAUKvB5ICQDvAQA1AAQKfykABAYACQpIJa4FAJkDAAYACQpIJa4FAJkDACEABwpeGvEGAA8CAAwAAQoAALuEACMAAAAA.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCggICQABNQAECgIIAgAHAAAAAA==.',
Ty='Tydrodh:BAAANQAECggICQAAAQ==.Tydropally:BAAANQAECggICAABNQAECggICQAHAAAAAA==.Tydroshaman:BAAANQADCgUIBQAAAA==.Tyestaumin:BAAANQADCgcIBwABNQAECgQICAAHAAAAAA==.Tyralen:BAABNQAECn8vAAIFAAkKTxieOgC4AgAFAAkKTxieOgC4AgAAAA==.Tyrandras:BAABNQAECn8qAAIeAAkKrRIqFgABAgAeAAkKrRIqFgABAgABNQAECgkJLwAFAE8YAA==.Tyronnius:BAAANQAECgYICgAAAA==.Tyrïon:BAABNQAECn8tAAIPAAkKAyOVGgBMAwAPAAkKAyOVGgBMAwAAAA==.',
Un='Unforgiven:BAAANQAECggIBgAAAA==.Unlyfe:BAAANQAECgQIBQAAAA==.Unnamed:BAAANQAECgEIAQABNQAFFAUIEwAGALweAA==.',
Va='Vaero:BAABNQAECn8mAAIQAAkKriFVCABMAwAQAAkKriFVCABMAwAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgEIAQAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAFFAYIEgATAFsKAA==.Velyssa:BAABNQAECn8ZAAIFAAcK3SCQQACmAgAFAAcK3SCQQACmAgAAAA==.',
Vi='Vibez:BAAANQAECgcIBwABNQAECgkJJgAiAJ0cAA==.Vibin:BAABNQAECn8mAAIiAAkKnRzrCwDkAgAiAAkKnRzrCwDkAgAAAA==.Vineeshewah:BAABNQAECn8ZAAICAAcKPB3wBACAAgACAAcKPB3wBACAAgAAAA==.',
Vo='Voidguy:BAAANQAECgYIDgABNQAECggIIwAXAJMPAA==.',
Vu='Vulsted:BAAANQADCggIFwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
['Vî']='Vîctorîe:BAAANQADCggICAAAAA==.',
Wa='Wantedd:BAAANQAECggIDwABNQAECgkJLAAKAOAdAA==.',
Wh='Whalend:BAAANQADCgYIBgAAAA==.Whatapal:BAAANQAECgUIDQAAAA==.',
Wi='Wilbo:BAABNQAECn8XAAILAAkKZRn8QwBiAgALAAkKZRn8QwBiAgABNQAFFAYIFgAZAA8VAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAABNQAECn8ZAAIFAAcKwgTyywBkAQAFAAcKwgTyywBkAQAAAA==.',
Wo='Wolfdrudu:BAAANQAECgYIDgAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQAECgQICQAAAA==.Wormszer:BAAANQAECgQICgAAAA==.Wotan:BAAANQADCgIJAgAAAA==.Woth:BAAANQADCggIDgAAAA==.',
Wr='Wrâîth:BAAANQADCgYICwABNQAECgUIDQAHAAAAAA==.',
Wy='Wynds:BAACNQAFFH8ZAAIiAAcKPCanAAAeAwAiAAcKPCanAAAeAwA1AAQKfzQAAiIACQr4JhAAAA4EACIACQr4JhAAAA4EAAAA.Wyngs:BAAANQAECgcIEgABNQAFFAcIGQAiADwmAA==.',
Xe='Xeres:BAAANQABCgIJBAAAAA==.',
Xi='Xi:BAABNQAECn8qAAIiAAkKLw1EHQD3AQAiAAkKLw1EHQD3AQAAAA==.Xiaozhi:BAEBNQAECn8ZAAMmAAcKDR8vEQBnAgAmAAcKDR8vEQBnAgAEAAMK8g6EUwCbAAAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAAANQAECgYIDgAAAA==.',
Yo='Yodda:BAAANQADCgUIBQAAAA==.Yoirr:BAAANQAECgYIDAAAAA==.',
['Yë']='Yëëter:BAAANQADCgUICQAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECggIGQAFAKUfAA==.Zanori:BAABNQAECn8rAAQYAAkKGxSPLgApAgAYAAkKGxSPLgApAgAZAAYKhgaNiwDxAAAWAAEKAACKywAwAAAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgkJKwAYABsUAA==.',
Ze='Zellyne:BAAANQAECggIEQABNQAFFAUIEAAiADwXAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAACNQAFFH8IAAIFAAUKaRNICwCWAQAFAAUKaRNICwCWAQA1AAQKfzUAAgUACQoZJK8TAE8DAAUACQoZJK8TAE8DAAAA.Zoyn:BAAANQADCgYIBgAAAA==.',
Zy='Zygo:BAAANQAECgIIAgAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Åm']='Åmnèsia:BAAANQADCgUIBQAAAA==.',
['Êv']='Êvelyn:BAAANQADCggIHAAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQAHAAAAAA==.',
['Ýu']='Ýuno:BAAANQADCgYIDgAAAA==.',
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
