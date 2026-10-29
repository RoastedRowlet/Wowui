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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Mage-Arcane','Druid-Feral','DemonHunter-Havoc','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Unknown-Unknown','Warrior-Protection','Mage-Frost','Warrior-Arms','DemonHunter-Devourer','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Guardian','Rogue-Assassination','Paladin-Holy','Hunter-Marksmanship','Priest-Discipline','Evoker-Preservation','Druid-Restoration','Hunter-Survival','Warrior-Fury','Mage-Fire',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aamix:BAACNQAFFH8RAAQBAAYKWAuUJQDWAAABAAQKQQ6UJQDWAAACAAEKAABZEABEAAADAAEKnQLkIwBBAAA1AAQKf1AAAwEACgr+HTUeAEgCAAEACQoiHTUeAEgCAAMABgo0DjUhAGcBAAAA.Aarom:BAACNQAFFH8XAAIEAAcK8xkyAwA7AgAEAAcK8xkyAwA7AgA1AAQKfycAAgQACgpfI+0OAPMCAAQACgpfI+0OAPMCAAAA.Aaronk:BAAANQADCggIDwAAAA==.',
Ab='Abdltdoc:BAABNQAECn8ZAAIFAAgKpR/ELADnAgAFAAgKpR/ELADnAgAAAA==.Abrakastaba:BAAANQAECgcIBwABNQAFFAUIEwAGALweAA==.',
Ae='Aelyn:BAAANQADCgQIBAAAAA==.Aelyndra:BAABNQAECn8VAAIHAAgKrwqdGQBEAQAHAAgKrwqdGQBEAQAAAA==.Aequitas:BAAANQAECgQIBAAAAA==.Aerius:BAAANQAECgUICAAAAA==.',
Af='Affliclock:BAACNQAFFH8LAAICAAUKOBnhAAChAQACAAUKOBnhAAChAQA1AAQKfxwAAgIACQpkIasCAOsCAAIACQpkIasCAOsCAAAA.',
Ai='Aingerfal:BAAANQAECgUIBgABNQAECggIFQAHAK8KAA==.',
Aj='Aj:BAABNQAECn8YAAIIAAoKawwthgA2AQAIAAoKawwthgA2AQAAAA==.',
Ak='Akasori:BAABNQAECn89AAIJAAoKiyKBAgCMAwAJAAoKiyKBAgCMAwAAAA==.Akisori:BAAANQAECgcIDAABNQAECgoKPQAJAIsiAA==.Akosori:BAAANQAECgIIAwABNQAECgoKPQAJAIsiAA==.',
Al='Alistaier:BAAANQAECgEIAQABNQAECgoKPgAKAFUbAA==.Allnaturale:BAAANQAECgUIBQAAAA==.Alterboyy:BAAANQAECgUIEAAAAA==.Alîsonshammy:BAACNQAFFH8QAAMLAAUKNR0FCADUAQALAAUKNR0FCADUAQAMAAMKtgYEHgDKAAA1AAQKfywAAwsACgp4I5gQAEADAAsACgp4I5gQAEADAAwACAr3HKdPADkCAAAA.',
Am='Ambersulfr:BAABNQAECn8cAAINAAgKoRrZFgD7AQANAAgKoRrZFgD7AQAAAA==.Ambrus:BAAANQADCgYIBgAAAA==.Amrazz:BAABNQAECn8eAAMGAAoKDBktKADJAgAGAAoKDBktKADJAgAHAAIKQweFaQBbAAAAAA==.Amzey:BAEBNQAECn80AAIIAAoKbR+YMQAoAwAIAAoKbR+YMQAoAwAAAA==.',
An='Anahata:BAAANQADCgEIAgABNQADCgcICwAOAAAAAA==.Andromeda:BAABNQAECn88AAIPAAoKhhzpAwCLAgAPAAoKhhzpAwCLAgAAAA==.Anneaux:BAAANQAECgIJAgAAAA==.Antimortem:BAAANQAECgQIBAAAAA==.',
Ar='Arcaneråge:BAAANQADCgUIBgABNQADCgQIBQAOAAAAAA==.Aridillo:BAAANQAECgEIAQAAAA==.Armani:BAAANQADCgIIAgAAAA==.',
As='Ashaea:BAAANQAECgEIAQAAAA==.Ashaka:BAAANQAECgUIDAAAAA==.Astralus:BAABNQAECn8XAAIQAAcKaRhsDgDEAQAQAAcKaRhsDgDEAQAAAA==.Astramis:BAABNQAECn8nAAIQAAgKPgiqFgBIAQAQAAgKPgiqFgBIAQAAAA==.',
At='Athennaa:BAAANQADCgYIBgAAAA==.Atomicbarbie:BAABNQAECn8qAAIRAAkKWhwBSwCoAgARAAkKWhwBSwCoAgABNQAFFAUIEAALADUdAA==.Atriøx:BAAANQAECgIIAwAAAA==.Atziri:BAABNQAECn84AAIMAAoKhxrMHAAVAgAMAAoKhxrMHAAVAgAAAA==.',
Av='Avalinia:BAAANQADCgIIAgAAAA==.',
Az='Azamia:BAAANQAECgUIEgABNQABCgIIAwAOAAAAAA==.',
Ba='Babyknife:BAAANQAECgIIAgABNQAFFAcIFwAEAPMZAA==.Backlash:BAABNQAECn8kAAISAAkKGBmMHgBcAgASAAkKGBmMHgBcAgAAAA==.Balzhac:BAABNQAECn8oAAMTAAoKNB//BwBRAgATAAkKmx//BwBRAgAUAAgKIRYxiwA7AQAAAA==.Bam:BAAANQADCggICAABNQAFFAcIHAAKABEYAA==.Bamplify:BAABNQAECn8dAAIIAAoKFh+dTwDiAgAIAAoKFh+dTwDiAgABNQAFFAcIHAAKABEYAA==.Barrierbobo:BAABNQAECn8oAAIGAAgKUhgUKQAmAgAGAAgKUhgUKQAmAgAAAA==.Barthold:BAAANQAECgQIBAAAAA==.',
Be='Beleaf:BAABNQAECn8WAAMEAAkKUwYHIQAeAQAEAAkKUwYHIQAeAQAVAAcKogViGwDYAAAAAA==.Bellmonte:BAAANQADCgYIDwABNQAECgkJJgAWAFAZAA==.Belmonk:BAAANQAECgQIBQAAAA==.Berdron:BAABNQAECn9BAAQDAAoKCRUiAgDtAQADAAoKCRUiAgDtAQABAAMKBQZm0gBUAAACAAEKAAB4MwAsAAAAAA==.',
Bi='Biden:BAAANQAECgMIBAAAAA==.',
Bl='Bladeliger:BAABNQAECn88AAIXAAoKeBkaEABGAgAXAAoKeBkaEABGAgAAAA==.Blazin:BAAANQAECgEIAQAAAA==.Bledsmasher:BAAANQADCgUIBQAAAA==.Blouses:BAABNQAECn8hAAIRAAkKiyRxHwA6AwARAAkKiyRxHwA6AwAAAA==.',
Bo='Boltsgobrr:BAAANQADCgIIAgAAAA==.Boned:BAABNQAECn8cAAMYAAgKrBsKCwBeAgAYAAcK/B0KCwBeAgAEAAIKIBBgRQA+AAAAAA==.Bonemair:BAACNQAFFH8iAAIZAAYK7huOCQDBAQAZAAYK7huOCQDBAQA1AAQKfzwAAhkACgo8ImgGAPMCABkACgo8ImgGAPMCAAAA.Boneseye:BAAANQADCgQIBAAAAA==.Boomguy:BAAANQADCgQIBwABNQAECggIDwAOAAAAAA==.Boredasf:BAAANQADCgYIBgAAAA==.Boricuazo:BAAANQADCgYIBgAAAA==.',
Br='Bradocks:BAAANQADCggIJwAAAA==.Brahn:BAAANQAECgIIAgAAAA==.Breezeblocks:BAAANQADCgEIAQAAAA==.Bryteblade:BAAANQADCgMIAwABNQAECggIDQAOAAAAAA==.Bräum:BAAANQADCgIIAgAAAA==.',
Bu='Bubblehooker:BAAANQAECggIAgAAAA==.Buffnbeers:BAAANQADCgYICwABNQAFFAUIEwAGALweAA==.Bullteesta:BAAANQAECgUICwAAAA==.Burkhard:BAAANQADCggIBwAAAA==.',
Bw='Bwonurjor:BAAANQADCgQIBAAAAA==.',
['Bó']='Bónes:BAAANQAECgMIBQAAAA==.',
Ca='Caldec:BAACNQAFFH8jAAMaAAcKGiSFAAC/AgAaAAcKGiSFAAC/AgAbAAUKig+QBwChAQA1AAQKfz0AAhoACgqAJlEBAG4DABoACgqAJlEBAG4DAAAA.',
Ch='Chainizard:BAAANQAECggIDAAAAA==.Chainpwn:BAAANQAECgUIBQABNQAECggIDAAOAAAAAA==.Chaosofelune:BAAANQAECgIIAgAAAA==.Chaosoflife:BAAANQAECgIJAgAAAA==.Chaosoflight:BAAANQAECgUIBQAAAA==.Cheeno:BAABNQAECn8yAAMSAAoK/CSPAgC0AwASAAoK/CSPAgC0AwAcAAEKPSKLKwBYAAAAAA==.Cheesyqueso:BAAANQABCgUIBAAAAA==.Chihiro:BAABNQAECn8YAAIKAAYKsAKzSwCXAAAKAAYKsAKzSwCXAAAAAA==.Chillay:BAAANQADCgEIAQAAAA==.Chillyblinks:BAACNQAFFH8LAAMQAAQK2BeOBACaAAAQAAIKPReOBACaAAAIAAIKDhn6MgBVAAA1AAQKfxcAAwgACQq0Fo3aANIBAAgACAr2FY3aANIBABAAAgp7Dn41AGUAAAAA.Chillyfists:BAAANQADCgUIBQAAAA==.Chillygowosh:BAAANQADCgEIAQABNQAFFAQICwAQANgXAA==.Chloris:BAAANQADCgMIAwABNQAECgQIBQAOAAAAAA==.Chuffed:BAAANQAECgEIAQAAAA==.',
Ci='Cinderheart:BAAANQABCgYIBgAAAA==.Ciymi:BAAANQAECgcICAABNQAFFAcICwAIAP8SAA==.',
Cl='Clarabelle:BAACNQAFFH8LAAMIAAcK/xLREADxAQAIAAYKABXREADxAQAQAAEK+QoYDgBUAAA1AAQKfykAAwgACgqgIn4gAFgDAAgACgoEIX4gAFgDABAABAqRJCUIAKABAAAA.Clisholder:BAAANQADCgQIBAAAAA==.',
Co='Coaltaine:BAAANQADCgMJAwABNQAECggIDQAOAAAAAA==.Computer:BAACNQAFFH8FAAIBAAQK6w73GgAfAQABAAQK6w73GgAfAQA1AAQKfyMAAwMACQqCH/8EANECAAMACArtIf8EANECAAEACAq8HBpSAF8CAAAA.Cootin:BAABNQAECn8VAAIIAAkKLwv88ACpAQAIAAkKLwv88ACpAQAAAA==.',
Cp='Cpteddie:BAABNQAECn8eAAMTAAkKUR4UEgCAAgATAAkKUR4UEgCAAgAUAAMKahFpUQGeAAABNQAFFAYIEwAZAEAaAA==.',
Cr='Craigg:BAAANQADCgYIBgAAAA==.Crate:BAAANQADCgQIBAABNQAECgEIAQAOAAAAAA==.Crelam:BAACNQAFFH8kAAINAAcKpA6tAABvAQANAAcKpA6tAABvAQA1AAQKfzwAAg0ACgrpHagFAIUCAA0ACgrpHagFAIUCAAAA.Critherine:BAAANQAECgUIDgAAAA==.Cronatherus:BAAANQAECgYICQAAAA==.Cruentis:BAABNQAECn8uAAIdAAoKTRZ0BwA/AgAdAAoKTRZ0BwA/AgAAAA==.Crysuh:BAAANQAECgMIAwABNQAECgcIDwAOAAAAAA==.Crysus:BAAANQAECgcIDwAAAA==.',
Da='Dabo:BAABNQAECn8jAAIXAAoKmB50GgD1AgAXAAoKmB50GgD1AgAAAA==.Damarisalynn:BAAANQADCgUIBQAAAA==.Darkurgekris:BAAANQADCggICAABNQAECgkJIQARAIskAA==.Darwin:BAABNQAECn8pAAMbAAgKfRbdVQC6AQAbAAYKIRzdVQC6AQAaAAgKxw7VMwBRAQAAAA==.Dasmoodhayn:BAAANQAECgYIDQAAAA==.Davalanch:BAABNQAECn8fAAIMAAkKxRZARABlAgAMAAkKxRZARABlAgAAAA==.Dazizejr:BAACNQAFFH8LAAIZAAQKuB26CgDlAAAZAAQKuB26CgDlAAA1AAQKfzwAAhkACgotJqEBAGEDABkACgotJqEBAGEDAAAA.',
De='Deathisbrew:BAAANQAECggIEAAAAA==.Deathxrage:BAAANQADCgcIDwAAAA==.Decor:BAAANQADCgYICgAAAA==.Deerhunter:BAAANQAECggICAAAAA==.Denïed:BAAANQADCgYICgAAAA==.Deonand:BAAANQADCggIEQAAAA==.Deramooke:BAAANQADCgcIBwAAAA==.Dethkløk:BAAANQAECgMIAwAAAA==.',
Di='Dibstrum:BAABNQAECn8dAAIIAAcKRQsElAAcAQAIAAcKRQsElAAcAQAAAA==.Digduug:BAABNQAECn8XAAIBAAYKLw/JwABKAQABAAYKLw/JwABKAQAAAA==.Dixqt:BAAANQAECgcIDgAAAA==.',
Do='Dogfight:BAACNQAFFH8WAAQbAAYKDxWfCQB7AQAbAAUKDxWfCQB7AQAaAAEKYQDxIgAqAAAZAAEKAADCNQAoAAA1AAQKfy0ABBsACgqLG54oAJcCABsACgrIGZ4oAJcCABoAAgpHC/WdAFUAABkAAQoAAMbNAC8AAAAA.Doilookfatou:BAABNQAECn8aAAMeAAkKrhs9DAClAgAeAAgKDB89DAClAgAXAAYKKge0cAAHAQAAAA==.',
Dr='Dragonguts:BAAANQADCgMIAwAAAA==.Draxus:BAABNQAECn8gAAIfAAcK6QZPLwCyAAAfAAcK6QZPLwCyAAAAAA==.Dresel:BAABNQAECn8dAAIFAAkKNRjsNwDCAgAFAAkKNRjsNwDCAgAAAA==.Drewpeebahlz:BAABNQAECn8bAAIgAAoKExrlNACQAgAgAAoKExrlNACQAgABNQABCgIIAgAOAAAAAA==.Drshakaloo:BAAANQADCggIHQAAAA==.',
Du='Dunnome:BAAANQAECgIIAgAAAA==.Durto:BAAANQADCgcIDQAAAA==.',
Dy='Dyami:BAABNQAECn86AAMFAAoK5STiBABAAwAFAAoK5STiBABAAwAhAAYKZBthMADLAQAAAA==.Dynas:BAABNQAECn8fAAQiAAcKkApsEAAiAQAiAAYK/QtsEAAiAQAGAAUKkwRexgDMAAAHAAYKjAMYOABsAAAAAA==.',
Ea='Earthcake:BAACNQAFFH8MAAMMAAQKbxElCgDmAAAMAAQKbxElCgDmAAALAAEKHwYDLgA/AAA1AAQKfzkAAwwACgqxIvMGABIDAAwACgqxIvMGABIDAAsABgqlCJyKAKsAAAAA.',
Ed='Eddielich:BAACNQAFFH8TAAIZAAYKQBoGBwD4AQAZAAYKQBoGBwD4AQA1AAQKfyUAAhkACgqGIqQJAGoDABkACgqGIqQJAGoDAAAA.Eddieteddie:BAAANQAFFAEIAQABNQAFFAYIEwAZAEAaAA==.',
Eg='Eggfumonk:BAAANQAECggIDQAAAA==.',
Eh='Ehlo:BAAANQADCgEIAQABNQAECgUICwAOAAAAAA==.',
El='Elasmon:BAABNQAECn8UAAIdAAgKuBUsCQD+AQAdAAgKuBUsCQD+AQAAAA==.Elbodeep:BAAANQADCgQIBAAAAA==.Elfpen:BAAANQAECgUICAAAAA==.Ellan:BAABNQAECn8pAAMIAAoKJhiQNQAcAgAIAAoKJhiQNQAcAgAQAAEKqQsjKwA9AAAAAA==.',
Em='Emongalkar:BAAANQADCgQIBAAAAA==.',
Er='Erragal:BAAANQAECgUICAAAAA==.',
Es='Escanõr:BAABNQAECn8XAAIUAAkK1hLohQAbAgAUAAkK1hLohQAbAgAAAA==.',
Ez='Ezindrozar:BAAANQADCggICwAAAA==.',
Fa='Falek:BAAANQAECgEIAQAAAA==.Faustyne:BAABNQAECn8gAAIBAAgKpgf+XgBHAQABAAgKpgf+XgBHAQABNQAFFAYIDQAFAMsUAA==.',
Fe='Felir:BAAANQADCggICAAAAA==.Felover:BAAANQAECgcICwAAAA==.Felurián:BAAANQAECgcIDAABNQADCgcIGgAOAAAAAA==.Fexli:BAAANQAECgUIBgAAAA==.',
Fi='Fireteeth:BAAANQADCggIEwAAAA==.Fiverunner:BAAANQADCgYIFQAAAA==.Fizc:BAAANQAECggIBwAAAA==.',
Fl='Flurtty:BAAANQADCgYIEwAAAA==.',
Fo='Folklore:BAABNQAECn8gAAIeAAcKmhSWHwCgAQAeAAcKmhSWHwCgAQAAAA==.Forklift:BAAANQAECgIIBAABNQAECgoKNAAjAPwgAA==.Foxrocks:BAAANQABCgMIAwAAAA==.',
Fr='Frighrish:BAAANQAECgEIAQAAAA==.Frigomortis:BAAANQAECgUIDAABNQAECgYIGwAMACMIAA==.Frozown:BAABNQAECn8jAAIIAAcK6hVZ3QDNAQAIAAcK6hVZ3QDNAQAAAA==.Fruits:BAAANQAECgUICgAAAA==.Fruitsack:BAABNQAECn8fAAUJAAoKkxW3FADoAAAXAAUKLxjOWQBsAQAkAAQK7RhPLQD5AAAJAAQKEBq3FADoAAAeAAIK9iBWQABfAAABNQAECgUICgAOAAAAAA==.',
Ft='Ftfw:BAAANQAECgYIDgAAAA==.',
Fu='Funfanfare:BAAANQAECgYICAAAAA==.Furrylife:BAAANQAECgIIAgAAAA==.Fusebawx:BAAANQADCgUIBgABNQAECgEIAQAOAAAAAA==.Fuzzychin:BAAANQAECgYIDQABNQAFFAQICwAQANgXAA==.',
['Fò']='Fòrlorn:BAAANQABCgEIAQAAAA==.',
Ga='Galram:BAABNQAECn8vAAIlAAkKRxjQAgAnAgAlAAkKRxjQAgAnAgABNQAFFAcIJAANAKQOAA==.Gardettos:BAABNQAECn80AAIjAAoK/CDNCQAGAwAjAAoK/CDNCQAGAwAAAA==.Gargingoyles:BAAANQADCgIJAgAAAA==.',
Gh='Gharghael:BAAANQAECgUICgAAAA==.Ghostthunter:BAAANQADCgQIBAABNQAECggIFgAaAFYdAA==.',
Gi='Gip:BAAANQADCggICAAAAA==.',
Gl='Glimmair:BAABNQAECn8gAAITAAkKPBvKCgAHAgATAAkKPBvKCgAHAgABNQAFFAYIIgAZAO4bAA==.Glimmer:BAAANQADCggIEgAAAQ==.',
Gn='Gnxrli:BAEANQADCgIIAgABNQAFFAQICgAEACkjAA==.Gnxrly:BAEANQAECgIIBAABNQAFFAQICgAEACkjAA==.Gnxrlyy:BAEANQAECggIDwABNQAFFAQICgAEACkjAA==.Gnxrr:BAECNQAFFH8KAAIEAAQKKSNQBQDxAAAEAAQKKSNQBQDxAAA1AAQKfzYAAgQACgp9JV0DAKEDAAQACgp9JV0DAKEDAAAA.',
Go='Goblino:BAAANQADCgIIAgAAAA==.Gooncaine:BAAANQAECgYICgAAAA==.Gorammasta:BAAANQAECggICwABNQAECggIFAAdALgVAA==.Gorbstrasz:BAAANQAECgEIAQAAAA==.Gorpse:BAAANQAECgUIDAAAAA==.',
Gr='Gregorz:BAAANQAECgUIBgAAAA==.Greyanna:BAABNQAECn8lAAIFAAgKtwficwBOAQAFAAgKtwficwBOAQAAAA==.Gridon:BAAANQADCgYIBgAAAA==.Gripguy:BAAANQADCggICAABNQAECggIDwAOAAAAAA==.Gromthrall:BAABNQAECn8ZAAIUAAkKkA21fwBSAQAUAAkKkA21fwBSAQAAAA==.',
Gw='Gwaea:BAAANQADCgUIBwAAAA==.Gworp:BAAANQAECgIJAwAAAA==.Gwynhwyfar:BAAANQAECgMIBAABNQAECgoKKAAFABMWAA==.',
['Gú']='Gúi:BAAANQAECgEIAQAAAA==.',
Ha='Hailin:BAAANQADCgcICwAAAA==.Hammersplash:BAAANQADCgQIBAAAAA==.Hangsut:BAAANQABCgQICgAAAA==.',
Hb='Hbhealthen:BAACNQAFFH8eAAIjAAcKNxtFAwBiAgAjAAcKNxtFAwBiAgA1AAQKf0UAAyMACgpRI2EDAIIDACMACgpRI2EDAIIDABYAAgrnEIUzAHEAAAAA.',
He='Hellhore:BAABNQAECn8VAAIIAAUKeAHqFgFHAAAIAAUKeAHqFgFHAAAAAA==.Hemila:BAAANQAECgYICwABNQAECgkJFAAUAAsLAQ==.Hetamala:BAAANQADCgMIAwAAAA==.',
Hi='Highego:BAABNQAECn8UAAIgAAkKGBqGJwDLAgAgAAkKGBqGJwDLAgAAAA==.',
Ho='Holdenc:BAAANQAECgUIBQABNQAECgoKOAALAJsiAA==.Hoodz:BAABNQAECn84AAIRAAoKaiSVCQAdAwARAAoKaiSVCQAdAwAAAA==.Houseplant:BAAANQAECgUIBQAAAA==.Howard:BAAANQAECgYIEAAAAA==.',
Hu='Huatli:BAAANQADCggIEgAAAA==.Huntguy:BAAANQADCggICAABNQAECggIDwAOAAAAAA==.Huzzarr:BAAANQABCgIIAgAAAA==.',
Hy='Hypnos:BAAANQADCgEIAQAAAA==.',
Ib='Ibearprofen:BAAANQAECgQICAAAAA==.',
Ic='Icerod:BAAANQADCgUIBQABNQAECgUICgAOAAAAAA==.',
Id='Idtrapdat:BAACNQAFFH8HAAMFAAMKoh/3HwCzAAAFAAIKoh/3HwCzAAAhAAIKIQ6qHACMAAA1AAQKfzsAAwUACgq6IyQRAF0DAAUACgq6IyQRAF0DACEABgptFCAjAOUAAAAA.',
Il='Illyana:BAABNQAECn8hAAMaAAoKZiMZBwD2AgAaAAoKwyIZBwD2AgAbAAYK5yHbNABWAgAAAA==.Ilse:BAABNQAECn81AAMgAAoKWR5eGQATAwAgAAoKWR5eGQATAwAUAAIKKQcDRAE1AAAAAA==.',
Im='Imagined:BAACNQAFFH8kAAMIAAcKORXhBQBlAgAIAAcKORXhBQBlAgAQAAIK/QfBCQB9AAA1AAQKfzoAAggACgpSIPUOAOICAAgACgpSIPUOAOICAAAA.',
In='Indihunter:BAAANQADCgEIAQAAAA==.Infernis:BAAANQADCgcIDAAAAA==.Infidelic:BAAANQAECgUIBQABNQAECgYIEAAOAAAAAA==.Infidelity:BAAANQAECgEIAQABNQAECgYIEAAOAAAAAA==.',
Ir='Ironchords:BAAANQADCgEIAQAAAA==.',
Iv='Ivank:BAABNQAECn8sAAIBAAoKgg/8XwA4AgABAAoKgg/8XwA4AgAAAA==.Ivracha:BAAANQAECgEJAQAAAA==.',
Ja='Jage:BAAANQAECgcICwAAAA==.Jararacuh:BAAANQAECgIIAgABNQAECgoKOwAIAFkdAA==.Jarsham:BAABNQAECn8bAAIMAAYKIwgmrQA5AQAMAAYKIwgmrQA5AQAAAA==.Jaràdan:BAABNQAECn8aAAIBAAoK9hCeSgCFAQABAAoK9hCeSgCFAQABNQAECgoKOwAIAFkdAA==.Jawshua:BAAANQAECgEIAQAAAA==.',
Je='Jeff:BAABNQAECn84AAIRAAoKvx9iLAALAwARAAoKvx9iLAALAwAAAA==.',
Jo='Joran:BAABNQAECn8aAAIKAAcKcwcNOgDoAAAKAAcKcwcNOgDoAAAAAA==.Jordie:BAAANQADCgIIAgAAAA==.Joredin:BAAANQADCgcIBwABNQAECgUICwAOAAAAAA==.Jorlannee:BAAANQADCgEIAQABNQADCgcIGgAOAAAAAA==.',
Jr='Jroc:BAAANQAFFAEIAQAAAA==.',
Ju='Judelene:BAAANQAECgQICAAAAA==.',
Jw='Jwrs:BAABNQAECn8kAAIRAAkKsBMCdwApAQARAAkKsBMCdwApAQAAAA==.',
['Jï']='Jïbril:BAABNQAECn8lAAIZAAoKMxfcLwBSAgAZAAoKMxfcLwBSAgAAAA==.',
Ka='Kabbala:BAABNQAECn8XAAIBAAgK2wwnZwAyAQABAAgK2wwnZwAyAQABNQAFFAcIJAAIADkVAA==.Kahlani:BAABNQAECn88AAILAAoKVBMtMADiAQALAAoKVBMtMADiAQAAAA==.Kahlua:BAAANQAECgUIDQAAAA==.Kailan:BAABNQAECn8gAAISAAcKzhj5KAD8AQASAAcKzhj5KAD8AQABNQAECgoKPwAHANIhAA==.Kalathios:BAAANQABCgIIAgABNQAECgQIBQAOAAAAAA==.Kaldro:BAAANQAECgcICwAAAA==.Kaliae:BAAANQADCgYIBAAAAA==.Kaly:BAABNQAECn86AAIYAAoKnQyJCABaAQAYAAoKnQyJCABaAQAAAA==.Kano:BAAANQAECgMIBAAAAA==.Kariana:BAABNQAECn87AAMMAAoKahU/QwBpAgAMAAoKahU/QwBpAgALAAgKyQTcowAsAQAAAA==.Kathry:BAAANQADCggIHwAAAA==.',
Ke='Keelzya:BAAANQAECggICAAAAA==.Keepdreaming:BAABNQAECn86AAIkAAoKURi4CADDAgAkAAoKURi4CADDAgAAAA==.Kefkka:BAAANQADCgEIAQAAAA==.Keme:BAAANQAECgcICAABNQAECgkJGwAgADIYAA==.Keybricker:BAAANQAECgYICgABNQAFFAUIEwAGALweAA==.Keymebrah:BAABNQAECn8bAAMIAAkKmhLpxAD6AQAIAAkKHBLpxAD6AQAQAAMKnRHTLgCIAAAAAA==.',
Ki='Killeh:BAAANQADCggIFAAAAA==.',
Ko='Korda:BAAANQAECgIIAgAAAA==.Korinä:BAABNQAECn8pAAIfAAkKRhH5CwC/AQAfAAkKRhH5CwC/AQAAAA==.Kosh:BAAANQAECgQIBgAAAA==.Koyra:BAACNQAFFH8fAAIWAAcKpSUeAAD+AgAWAAcKpSUeAAD+AgA1AAQKfzoAAhYACgqMJikAAIEDABYACgqMJikAAIEDAAAA.',
Kr='Kreyden:BAAANQAECgMIAwAAAA==.Krump:BAAANQAECgUIBgAAAA==.',
Ku='Kubbles:BAAANQADCggICAAAAA==.Kubs:BAAANQADCgcIDAAAAA==.Kubwa:BAAANQABCgcIDwAAAA==.Kungfugimp:BAAANQAECggIEwAAAA==.Kurral:BAACNQAFFH8jAAMXAAcK0RF0BwAVAgAXAAcK0RF0BwAVAgAkAAcK/gBfCQC4AAA1AAQKfzgAAxcACgoWINIGAO8CABcACgoWINIGAO8CACQABArrBO1bAJgAAAAA.Kurralium:BAABNQAECn8pAAMQAAkKDA7pDgC7AQAQAAgKxQ/pDgC7AQAIAAgKSAaIdwBVAQABNQAFFAcIIwAXANERAA==.Kurstina:BAAANQADCgYICQAAAA==.Kuzushi:BAABNQAECn8bAAIUAAkKggct4QBZAQAUAAkKggct4QBZAQAAAA==.',
Ky='Kyramus:BAABNQAECn8lAAIPAAgKiSWoBQAWAwAPAAgKiSWoBQAWAwAAAA==.',
La='Laconia:BAABNQAECn8mAAIWAAkKUBnYDQCCAgAWAAkKUBnYDQCCAgAAAA==.Lashstorm:BAAANQAECggIEQAAAA==.Lattsatnar:BAAANQAECgQICwAAAA==.',
Le='Lebron:BAAANQAECggIDwAAAA==.Lelesobi:BAAANQADCgUIBgAAAA==.Lemonwhiskey:BAAANQAECgIIAgAAAA==.Lennel:BAAANQAECgQICQAAAA==.Lewd:BAAANQAECggIAgAAAA==.',
Li='Lightningguy:BAAANQADCgYIBgABNQAECggIDwAOAAAAAA==.Lilsnick:BAABNQAECn8cAAIGAAcKBBY3SACQAQAGAAcKBBY3SACQAQAAAA==.Lisaluv:BAAANQAECggICAAAAA==.Litterbawx:BAAANQADCgYIBgABNQAECgEIAQAOAAAAAA==.',
Ll='Llanthyl:BAABNQAECn8qAAImAAkKAhefBQD2AQAmAAkKAhefBQD2AQAAAA==.',
Lo='Loadtoad:BAAANQAECgIIAgABNQAECgQIBgAOAAAAAA==.Lockbawx:BAAANQAECgEIAQABNQAECgEIAQAOAAAAAA==.Loktardogard:BAAANQADCgUIBQAAAA==.Loku:BAAANQADCgIIAgAAAA==.',
Lu='Lucía:BAABNQAFFH8HAAIZAAYKMhRGDwBhAQAZAAYKMhRGDwBhAQAAAA==.Luecien:BAAANQADCgUIBQAAAA==.Lunafalia:BAABNQAECn87AAIQAAoKVBjqBQCrAgAQAAoKVBjqBQCrAgAAAA==.Lupon:BAAANQAECggICAAAAA==.Lurosa:BAACNQAFFH8NAAIkAAYK+B7mBADUAQAkAAYK+B7mBADUAQA1AAQKfzcAAyQACgr8JXoAAOUDACQACgr8JXoAAOUDABcABgo8FVslAFkBAAAA.Luxeria:BAAANQAECgcIDQAAAA==.Luxray:BAAANQABCggIFQAAAA==.',
Ly='Lyrae:BAAANQADCgYIBwAAAA==.',
['Lî']='Lîlydan:BAAANQADCgUIBwAAAA==.',
['Lï']='Lïchkinged:BAAANQAECgcICwAAAA==.',
Ma='Macready:BAACNQAFFH8RAAIPAAUKViP9AAAsAQAPAAUKViP9AAAsAQA1AAQKfzgAAg8ACgqsJfcAAEwDAA8ACgqsJfcAAEwDAAAA.Madmimm:BAAANQADCgcIBwAAAA==.Magenin:BAAANQAECgcICQAAAA==.Maggotgut:BAAANQAECgUICQAAAA==.Magoren:BAAANQADCgUIBgAAAA==.Mairbear:BAAANQAECgcIBwABNQAFFAYIIgAZAO4bAA==.Mairiachi:BAAANQAECgYIBwABNQAFFAYIIgAZAO4bAA==.Maltessa:BAAANQADCgUICgABNQAECgoKPwAHANIhAA==.Marload:BAACNQAFFH8PAAMFAAYKURICFAAmAQAFAAUKURICFAAmAQAhAAQK3w2DFAD4AAA1AAQKfzsAAyEACgpdHkcaAIMCACEACQpGFkcaAIMCAAUACgqwHTdPAIECAAAA.Mathy:BAABNQAECn8fAAMNAAoKXRJnCgACAgANAAoKXRJnCgACAgALAAIKJAP+CwFQAAAAAA==.',
Me='Melath:BAAANQADCggIFQAAAA==.Melreu:BAAANQADCgEIAQABNQAECgoKMgASAPwkAA==.',
Mi='Midletons:BAABNQAECn8WAAIUAAcKxQ8JmAAjAQAUAAcKxQ8JmAAjAQAAAA==.Minikub:BAABNQAECn8sAAIEAAgKvA1sHABJAQAEAAgKvA1sHABJAQAAAA==.Mischievous:BAABNQAECn8nAAMmAAoK0ABtNgAsAAAmAAkKqwBtNgAsAAAPAAoKkwCiNQAmAAAAAA==.Mixxy:BAAANQAECgQIBwABNQAFFAgIGQAEABgXAA==.Mizu:BAABNQAECn8bAAIgAAkKMhijGgBuAgAgAAkKMhijGgBuAgAAAA==.',
Mn='Mnzn:BAAANQADCggIGgAAAA==.',
Mo='Moobubble:BAABNQAECn8ZAAIUAAoKPRaodABEAgAUAAoKPRaodABEAgABNQAFFAQIDAAMAG8RAA==.Moodroo:BAAANQAECgUIEAAAAA==.Moonanoke:BAAANQAECgUICwAAAA==.Moovoker:BAABNQAECn9CAAIjAAoKmiJuAQCbAwAjAAoKmiJuAQCbAwAAAA==.Morseques:BAABNQAECn83AAMbAAoKkCJIDABYAwAbAAoKkCJIDABYAwAZAAEKAAAXtABhAAAAAA==.Mortimer:BAAANQAECgMIBQAAAA==.Mothra:BAAANQADCggICAAAAA==.Moz:BAAANQADCgMIAwAAAA==.',
Mu='Muggy:BAACNQAFFH8RAAQbAAcKlBo5BgC8AQAbAAUKyho5BgC8AQAZAAEKAADkIwBuAAAaAAEKvRlgEgBaAAA1AAQKf0MAAxsACgptJvMAAHADABsACgptJvMAAHADABoACQpWIK0SAEoCAAAA.Muguda:BAAANQADCgMIAwAAAA==.',
Mx='Mxkebfistin:BAACNQAFFH8ZAAIEAAgKGBddAwA0AgAEAAgKGBddAwA0AgA1AAQKfzMAAgQACgrvIgUMABUDAAQACgrvIgUMABUDAAAA.Mxkebspinnin:BAAANQADCggICAABNQAFFAgIGQAEABgXAA==.',
Na='Narama:BAACNQAFFH8dAAMBAAcKGAYgDAD0AAABAAYKUAYgDAD0AAADAAIKZQMzEwB7AAA1AAQKfzoABAEACgpSF3EeAEcCAAEACgoPF3EeAEcCAAMABgpMDnslAEgBAAIAAQoAABg1ACYAAAAA.',
Ne='Nekka:BAABNQAECn8aAAILAAcKyxbdOwCqAQALAAcKyxbdOwCqAQAAAA==.Nethanos:BAAANQAECgcIDwAAAA==.Neverrmore:BAAANQAECgEIAQAAAA==.Nexotic:BAAANQADCgcICAABNQAECgQIDAAOAAAAAA==.',
Ni='Ninæ:BAACNQAFFH8RAAIjAAYKuBV2CQCaAQAjAAYKuBV2CQCaAQA1AAQKfzEAAiMACgosIzYFAFgDACMACgosIzYFAFgDAAAA.Nitewïng:BAAANQAECgcIIAABNQADCggIEgAOAAAAAQ==.',
No='Nofeet:BAAANQADCgYICwABNQAECgQICQAOAAAAAA==.Nohomoh:BAAANQADCgUIBgAAAA==.Nootau:BAABNQAECn8YAAIIAAcKkR0itQAZAgAIAAcKkR0itQAZAgAAAA==.',
Ny='Nyoz:BAAANQAECgUIEAAAAA==.Nyxxadra:BAABNQAECn8+AAIBAAoKHBChNADYAQABAAoKHBChNADYAQAAAA==.',
Oa='Oakshion:BAAANQAECgEIAQAAAA==.',
Om='Omegadeed:BAABNQAECn82AAMBAAoKjRaKKAARAgABAAoKjRaKKAARAgADAAEKAACnawBJAAAAAA==.',
On='Onne:BAAANQAECgUIBgAAAA==.',
Or='Orcinus:BAACNQAFFH8JAAIjAAQKiwL1CQDSAAAjAAQKiwL1CQDSAAA1AAQKfygAAiMACgrFECkYADoCACMACgrFECkYADoCAAAA.Orcishfist:BAAANQAECgcIDgAAAA==.Orvar:BAAANQAECgQIBQABNQABCgIIAgAOAAAAAA==.',
Pa='Pakaru:BAABNQAECn8wAAIUAAoK2BlzQAD5AQAUAAoK2BlzQAD5AQAAAA==.Pam:BAACNQAFFH8cAAIKAAcKERggBQANAgAKAAcKERggBQANAgA1AAQKfzIAAwoACgpzJP0PACIDAAoACgpzJP0PACIDABIAAgpdHg1YAKkAAAAA.Parathin:BAAANQADCggIFAAAAA==.',
Pe='Peorä:BAABNQAECn8vAAMGAAkKeA7ERACeAQAGAAkKeA7ERACeAQAHAAcKZwOKSgDuAAAAAA==.Perfectdark:BAACNQAFFH8jAAISAAcK2B1GAQCRAgASAAcK2B1GAQCRAgA1AAQKfz4AAxIACgqJI74CAB8DABIACgqJI74CAB8DAAoAAgrCIOpvALoAAAAA.Perse:BAAANQAECgYIBwAAAA==.',
Ph='Phathottie:BAAANQABCgMIBAABNQAECgYIGwAMACMIAA==.Pheadas:BAAANQADCgUJBQAAAA==.Phleez:BAAANQADCggIEQABNQAECgIIAgAOAAAAAA==.',
Pi='Picklesnrye:BAAANQADCggIDwAAAA==.Pieper:BAABNQAECn8oAAIFAAoKExZ9KQA7AgAFAAoKExZ9KQA7AgAAAA==.Pietrov:BAAANQAECggICAABNQAECgoKJQAIAGcUAA==.Pinkee:BAAANQAECggICAAAAA==.Pipa:BAABNQAECn9BAAILAAoKgSVWBQCdAwALAAoKgSVWBQCdAwAAAA==.Pippit:BAABNQAECn8iAAIgAAgK3xJvYAD3AQAgAAgK3xJvYAD3AQABNQAECgoKQQALAIElAA==.',
Pl='Plokane:BAABNQAECn8uAAMBAAkKASA5UgBeAgABAAgKLx45UgBeAgADAAIK9CPDEACWAAAAAA==.',
Po='Poacher:BAAANQADCgMIBAAAAA==.Poppapally:BAAANQADCgYICQAAAA==.Porque:BAAANQAECgQIBgABNQAECggIDwAOAAAAAA==.Powar:BAABNQAECn8VAAImAAkKthqMCABcAgAmAAkKthqMCABcAgAAAA==.',
Pr='Provence:BAAANQAECgIIAgAAAA==.',
Py='Pyreynna:BAABNQAECn8WAAIBAAcKIxRGugBZAQABAAcKIxRGugBZAQAAAA==.',
['Pè']='Pèppèr:BAABNQAECn8ZAAIUAAcKTRXlowDZAQAUAAcKTRXlowDZAQABNQAECgoKPAAPAIYcAA==.',
Qs='Qsteve:BAAANQADCgYIBgAAAA==.',
Ra='Ragarn:BAAANQAECgEIAQABNQAECgoKOAALAJsiAA==.Rainier:BAAANQADCgIIAgAAAA==.Ralnorin:BAABNQAECn8kAAILAAgKwRZ+OgCwAQALAAgKwRZ+OgCwAQAAAA==.Rapsodia:BAAANQAECgcIDAABNQAFFAcICwAIAP8SAA==.Raschild:BAAANQAECgcIEgAAAA==.',
Re='Realfrojd:BAABNQAECn83AAIZAAoKewhAYgBpAQAZAAoKewhAYgBpAQAAAA==.Redeyed:BAAANQAECgEIAQAAAA==.Regginunchuk:BAABNQAECn88AAIEAAoKVB+4CgAoAwAEAAoKVB+4CgAoAwAAAA==.Releronastus:BAAANQAECgYIDgAAAA==.Reliquary:BAAANQAECgEIAQAAAA==.Rextallion:BAABNQAECn9FAAMUAAoK3R41KQBcAgATAAgKpx5iEgB8AgAUAAoKOBw1KQBcAgAAAA==.Reyson:BAABNQAECn87AAIIAAoK0A3TVACuAQAIAAoK0A3TVACuAQAAAA==.',
Rh='Rhunon:BAABNQAECn9DAAIZAAoKUhxEGgDcAgAZAAoKUhxEGgDcAgAAAA==.Rhythma:BAAANQADCgYIBAAAAA==.',
Ri='Rimlaol:BAAANQAECgYICwAAAA==.Rinchi:BAAANQADCgYIDAAAAA==.Rinthia:BAABNQAECn8/AAMHAAoK0iF5BgBwAwAHAAoK0iF5BgBwAwAGAAEKhwWmxQA4AAAAAA==.Ripyeet:BAABNQAECn8cAAIUAAgKchg8hAAfAgAUAAgKchg8hAAfAgAAAA==.',
Ro='Rol:BAABNQAECn8hAAILAAoKIRvCFgCQAgALAAoKIRvCFgCQAgAAAA==.',
Ru='Rukaji:BAABNQAECn8hAAIRAAgK/BfvlADnAQARAAgK/BfvlADnAQAAAA==.',
['Rå']='Rågeadin:BAAANQADCgYIFQABNQADCgQIBQAOAAAAAA==.Rågè:BAAANQADCgQIBQAAAA==.',
Sa='Saetheline:BAABNQAECn86AAIRAAoK0hduLQAlAgARAAoK0hduLQAlAgAAAA==.Sainteddie:BAAANQABCgIIAgAAAA==.Samayel:BAAANQAECgcIDgAAAA==.Sarkang:BAABNQAECn84AAMZAAgKxRYtNQA3AgAZAAcKbhktNQA3AgAbAAgKng5FXQCaAQAAAA==.Satdurrday:BAAANQADCgQIBAABNQAECgoKPAAPAIYcAA==.',
Sc='Schecter:BAAANQAECgQIAwAAAA==.Schmeebie:BAAANQAECgIIAgABNQAECgcIGwAnAPwcAA==.Schutze:BAACNQAFFH8IAAIlAAUK7xHlAABiAQAlAAUK7xHlAABiAQA1AAQKfy0AAyUACgq5I2UCABkDACUACgq5I2UCABkDACEACArrCRoWAGEBAAAA.',
Sd='Sdadfeg:BAABNQAECn82AAINAAoKfiXtAADAAwANAAoKfiXtAADAAwAAAA==.',
Se='Sebastien:BAAANQADCggICAABNQAECgoKMAAhAE0YAA==.Senco:BAAANQAECgYIDwAAAA==.Sephroth:BAAANQAECgEIAQABNQAECgIIAgAOAAAAAA==.',
Sh='Shabobado:BAABNQAECn8ZAAIIAAgKxxf7nABHAgAIAAgKxxf7nABHAgAAAA==.Shadowleaf:BAAANQADCgQIBAAAAA==.Shammin:BAAANQAECgYIDwAAAA==.Shampyre:BAAANQADCgUIBQAAAA==.Shayder:BAAANQAFFAEIAQAAAA==.Shiipo:BAAANQADCggIEgAAAA==.Shura:BAABNQAECn8VAAINAAoKox9hBAC0AgANAAoKox9hBAC0AgAAAA==.Shuten:BAAANQAECgYICgAAAA==.Shxdow:BAAANQADCgEJAQAAAA==.Shøck:BAAANQAECgMIAwAAAA==.',
Si='Sibble:BAAANQADCgYIDAAAAA==.Siegfried:BAAANQAECgcICwAAAA==.Silbanuz:BAAANQAECgQIBQAAAA==.Silverie:BAAANQAECgQICAABNQAECgoKQQALAIElAA==.Simplejakk:BAAANQAECgcIBwAAAA==.Sinill:BAAANQADCggIDwAAAA==.Sinterklaas:BAABNQAECn8rAAILAAoKMhUMQwBUAgALAAoKMhUMQwBUAgAAAA==.',
Sk='Skjald:BAAANQAECggIDQABNQAFFAUIEwAGALweAA==.Skylee:BAABNQAECn8qAAMIAAoKBBrGRQDiAQAIAAkK5RrGRQDiAQAQAAEK2xOrJwBKAAAAAA==.',
Sl='Slark:BAABNQAECn8XAAMYAAkKaQVoHAAgAQAYAAgKaQVoHAAgAQAVAAUKYQuMMgDVAAAAAA==.Slawth:BAABNQAECn8jAAQbAAoKABAWFwDFAQAbAAoKABAWFwDFAQAZAAEKEQSszQAwAAAaAAEKAADvngAAAAAAAA==.Slayermonde:BAAANQAECgUICAAAAA==.Sleepel:BAAANQADCgYICgAAAA==.',
Sm='Smexytimes:BAABNQAECn8rAAIRAAoKDx6cFwCrAgARAAoKDx6cFwCrAgAAAA==.Smeyplus:BAACNQAFFH8VAAMUAAcKAiD3BwDNAQAUAAYKAiD3BwDNAQATAAEKAAAuDQBxAAA1AAQKfzcABBQACgrjJigFANADABQACgrjJigFANADACAABQqlF6hNAGABABMAAQoAADZbAG8AAAAA.',
Sn='Snaccident:BAAANQAECggIEAAAAA==.Snickeris:BAAANQAECgYIEAABNQAECgcIHAAGAAQWAA==.Snofawl:BAAANQAECgYIDQAAAA==.Snoranir:BAAANQAECgcIEQAAAA==.Snurchbasher:BAABNQAECn8ZAAIjAAcKDxXbEwAtAQAjAAcKDxXbEwAtAQAAAA==.',
Sp='Spanfrontals:BAABNQAECn8UAAMSAAoKAhjLCwA0AgASAAkKAhjLCwA0AgAcAAcKjguyFQBRAQABNQAFFAUIEwAGALweAA==.Speedpuss:BAAANQADCgUIBQAAAA==.Spiko:BAABNQAECn84AAILAAoKmyLPAgDIAwALAAoKmyLPAgDIAwAAAA==.Spratticus:BAAANQADCgYICgAAAA==.',
Sq='Squidd:BAAANQADCgMIBAAAAA==.',
St='Stars:BAABNQAECn8oAAMKAAoKqxsFDwBbAgAKAAoKqxsFDwBbAgASAAYK+QnRQgA5AQABNQAFFAMIBwAFAKIfAA==.Sterra:BAAANQADCgcIDgAAAA==.Stinkiepete:BAAANQAECgIIAgAAAA==.',
Su='Sureno:BAABNQAECn8eAAIUAAoKIiD5MgAtAgAUAAoKIiD5MgAtAgAAAA==.',
Sw='Swaglordxtqt:BAAANQAECgMIAgAAAA==.',
Sx='Sxyhealz:BAAANQAECggIDgAAAA==.Sxyheålz:BAACNQAFFH8HAAIGAAUK7AYxGwARAQAGAAUK7AYxGwARAQA1AAQKfz4AAgYACgqZGo0kAEQCAAYACgqZGo0kAEQCAAAA.',
Ta='Taffybonkins:BAAANQAECgcIEQAAAA==.Taliä:BAAANQADCgcIDAAAAA==.Tanndari:BAAANQADCgcIIQAAAA==.Tartare:BAABNQAECn8WAAIUAAoKigs/hABIAQAUAAoKigs/hABIAQAAAA==.Tashaman:BAACNQAFFH8MAAMLAAUKOw0XDwBeAQALAAUKOw0XDwBeAQAMAAEKAABdNwAzAAA1AAQKf0AAAwsACgq+E6NWAA4CAAsACgq+E6NWAA4CAAwABQq7BavZAOEAAAAA.',
Te='Teajuan:BAAANQADCgcIBwAAAA==.Tenderheart:BAAANQABCgIIAgAAAA==.Tenzin:BAAANQADCggIDwAAAA==.Teriheals:BAAANQAECgUICQAAAA==.',
Th='Thebishop:BAAANQADCgIIAgAAAA==.Thejorlane:BAAANQADCgcIGgAAAA==.Thiccholy:BAACNQAFFH8NAAMgAAUKwgq1DgB4AQAgAAUKwgq1DgB4AQATAAIKfwKODwBNAAA1AAQKfy8ABCAACgqAFw1UAB4CACAACgqAFw1UAB4CABMACQrdDCQrAIQBABQABgpBCRcZAfUAAAAA.Thiccshields:BAAANQAECgQIAwABNQAFFAUIDQAgAMIKAA==.Thicctotemz:BAAANQAECgUICwABNQAFFAUIDQAgAMIKAA==.Thickkicks:BAAANQAECgMIAwABNQAFFAUIDQAgAMIKAA==.Thogo:BAABNQAECn84AAImAAoK+CGrAQDlAgAmAAoK+CGrAQDlAgAAAA==.',
Ti='Tikaa:BAAANQAECgUIEAAAAA==.Tipnontotems:BAAANQADCgUIBQAAAA==.',
To='Tokiya:BAACNQAFFH8FAAITAAMKERk/CwCPAAATAAMKERk/CwCPAAA1AAQKfzQAAhMACgp7JAUDAJYDABMACgp7JAUDAJYDAAE1AAUUBggHABkAMhQA.Tomerto:BAABNQAECn83AAMgAAoKfCAPCgAnAwAgAAoKfCAPCgAnAwAUAAUK/Qw4GgHzAAAAAA==.Toobeastly:BAABNQAECn8sAAQMAAoKGx/DJgDoAgAMAAkKFiDDJgDoAgANAAkKixxYBgBwAgALAAEKRhUWHgExAAAAAA==.Toonerdin:BAAANQAECgUIDgAAAA==.Toymonkey:BAAANQADCggIDQAAAA==.',
Tr='Tril:BAAANQAECgIJAwAAAA==.Trolazo:BAAANQADCggICgAAAA==.Trox:BAAANQADCgcIEwAAAA==.Trydrodruid:BAABNQAECn8WAAQJAAcK5Q3VLACrAAAXAAUKFw5UdAD5AAAJAAUKCAnVLACrAAAeAAEKnBvRVwBJAAABNQAECgkJFAAUAAsLAA==.Tryingmybest:BAACNQAFFH8TAAIGAAUKvB6bCQDvAQAGAAUKvB6bCQDvAQA1AAQKfykABAYACQpIJdEFAJkDAAYACQpIJdEFAJkDACIABwpeGgMHAA8CAAcAAQoAAH2GACMAAAAA.',
Ts='Tsugi:BAAANQAECgIIAgAAAA==.',
Tw='Twozero:BAAANQADCggICQABNQAECgIIAgAOAAAAAA==.',
Ty='Tydrodh:BAAANQAECggICQABNQAECgkJFAAUAAsLAQ==.Tydromage:BAAANQAECgQIBAABNQAECgkJFAAUAAsLAA==.Tydropally:BAABNQAECn8UAAIUAAkKCwv4pwAGAQAUAAkKCwv4pwAGAQAAAA==.Tydroshaman:BAAANQADCgUIBQAAAA==.Tyestaumin:BAAANQADCgcIBwABNQAECgYIDgAOAAAAAA==.Tyralen:BAABNQAECn87AAIFAAoKWxjXOwC2AgAFAAoKWxjXOwC2AgAAAA==.Tyrandras:BAABNQAECn86AAIeAAoKUBJ9EQCYAQAeAAoKUBJ9EQCYAQABNQAECgoKOwAFAFsYAA==.Tyronnius:BAABNQAECn8cAAMDAAgKuBWGAwCJAQADAAgKuBWGAwCJAQABAAQKWwTEEgGlAAAAAA==.Tyrïon:BAABNQAECn89AAIRAAoKOyIQGwBLAwARAAoKOyIQGwBLAwAAAA==.',
Un='Unforgiven:BAAANQAECggIBgAAAA==.Unlyfe:BAAANQAECgQIBQAAAA==.Unnamed:BAAANQAECgEIAQABNQAFFAUIEwAGALweAA==.',
Va='Vaero:BAABNQAECn82AAISAAoKhSFxCABMAwASAAoKhSFxCABMAwAAAA==.Vampirate:BAAANQADCgcIBwAAAA==.Vandenar:BAAANQAECgQIBQAAAA==.',
Vd='Vdarkadin:BAAANQADCgEIAQAAAA==.',
Ve='Vee:BAAANQADCgEIAQABNQAFFAcIFwAWAKgJAA==.Velyssa:BAABNQAECn8pAAIFAAgKFyC6QQClAgAFAAgKFyC6QQClAgAAAA==.',
Vi='Vibez:BAAANQAECgcIDwABNQAECgoKLAAjADsdAA==.Vibin:BAABNQAECn8sAAIjAAoKOx0TDADjAgAjAAoKOx0TDADjAgAAAA==.Vineeshewah:BAABNQAECn8pAAICAAgKNBz8BAB/AgACAAgKNBz8BAB/AgAAAA==.',
Vo='Voidguy:BAAANQAECggIDwAAAA==.',
Vu='Vulsted:BAAANQADCggIFwAAAA==.',
Vy='Vykx:BAAANQADCgMIBQAAAA==.',
['Vî']='Vîctorîe:BAAANQADCggICAAAAA==.',
Wa='Wantedd:BAABNQAECn8fAAIGAAoK+xgMFwCsAgAGAAoK+xgMFwCsAgABNQAECgoKOAALAJsiAA==.Warriorguy:BAAANQABCgIIAgABNQAECggIDwAOAAAAAA==.',
Wh='Whalend:BAAANQAECgQIBAAAAA==.Whatapal:BAABNQAECn8XAAITAAcKwRaFFgBPAQATAAcKwRaFFgBPAQAAAA==.',
Wi='Wilbo:BAABNQAECn8YAAIMAAoKZhnYRABiAgAMAAoKZhnYRABiAgABNQAFFAYIFgAbAA8VAA==.Wily:BAAANQAECgMIBAAAAA==.Wisperwing:BAABNQAECn8gAAIFAAcKwgR/zgBkAQAFAAcKwgR/zgBkAQAAAA==.',
Wo='Wolfdrudu:BAABNQAECn8WAAIeAAcK+Qw4MwAIAQAeAAcK+Qw4MwAIAQAAAA==.Wordbet:BAAANQADCgcIBwAAAA==.Worldfire:BAAANQAECgYICQAAAA==.Wormadina:BAAANQAECgcICwAAAA==.Wormszer:BAAANQAECggIEQAAAA==.Wotan:BAAANQADCgIIAgAAAA==.Woth:BAAANQADCggIDgAAAA==.',
Wr='Wrâîth:BAAANQADCgYICwABNQAECgYIGwAMACMIAA==.',
Wy='Wynds:BAACNQAFFH8fAAIjAAcK7ia1AAAeAwAjAAcK7ia1AAAeAwA1AAQKf0MAAiMACgrMJhAAAA0EACMACgrMJhAAAA0EAAAA.Wyngs:BAABNQAECn8bAAIgAAgKeSXPEQC/AgAgAAgKeSXPEQC/AgABNQAFFAcIHwAjAO4mAA==.',
Xe='Xeres:BAAANQABCgIJBAAAAA==.',
Xi='Xi:BAABNQAECn86AAIjAAoKChCYCgD5AQAjAAoKChCYCgD5AQAAAA==.Xiaozhi:BAEBNQAECn8pAAMVAAgKVSLaAwAZAwAVAAgKVSLaAwAZAwAEAAMK8g6mVACbAAAAAA==.',
Xt='Xtend:BAAANQAECgEIAQAAAA==.',
Xz='Xzariana:BAABNQAECn8WAAIFAAgKugiDugCOAQAFAAgKugiDugCOAQAAAA==.',
Yo='Yodda:BAAANQADCgUIBQAAAA==.Yoirr:BAABNQAECn8eAAIGAAkK6STIBwBiAwAGAAkK6STIBwBiAwAAAA==.',
['Yë']='Yëëter:BAAANQADCgcIDgAAAA==.',
Za='Zach:BAAANQAECgEIAQABNQAECggIGQAFAKUfAA==.Zanori:BAABNQAECn9DAAQaAAoKmRTKHADmAQAaAAoKABTKHADmAQAbAAYKhgbejADxAAAZAAUKWAeiTQCwAAAAAA==.Zansijo:BAAANQADCgUIBQABNQAECgoKQwAaAJkUAA==.',
Ze='Zellyne:BAABNQAECn8YAAMkAAoK2B39EwCrAgAkAAkKRR39EwCrAgAJAAEKTAl4QwAzAAABNQAFFAYIEQAjALgVAA==.Zenwalkah:BAAANQAECgUIBQAAAA==.',
Zo='Zolajin:BAAANQADCgYICQAAAA==.Zorriya:BAACNQAFFH8NAAIFAAYKyxTLBABVAQAFAAYKyxTLBABVAQA1AAQKf0IAAgUACgo7JTcEAEkDAAUACgo7JTcEAEkDAAAA.Zoyn:BAAANQAECgUIBAAAAA==.',
Zy='Zygo:BAAANQAECgIIAgAAAA==.',
['Ár']='Áries:BAAANQAECgMIBwAAAA==.',
['Åm']='Åmnèsia:BAAANQADCgcICwAAAA==.',
['Êv']='Êvelyn:BAAANQAECgQIBgAAAA==.',
['Ít']='Ítsaßünny:BAAANQADCgQIBQAAAA==.',
['Ðe']='Ðemonic:BAAANQAECgEIAQABNQAECgEIAQAOAAAAAA==.Ðemonicßlaze:BAAANQADCggIEAABNQAECgEIAQAOAAAAAA==.',
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
