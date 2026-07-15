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

local lookup = {'Druid-Restoration','Paladin-Retribution','Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Warlock-Affliction','DeathKnight-Blood','Priest-Discipline','Monk-Brewmaster','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Abrácadabra:BAAALgAECgMJAwABLgAECgkJPwABAOgVAA==.',
Ac='Achilles:BAABLgAFFH8GAAICAAQJCQviHQD4AAACAAQJCQviHQD4AAAAAA==.',
Ad='Aderan:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAADAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwAEAAYhAA==.Aesalon:BAABLgAECn80AAQFAAkJ1CMHBADHAgAFAAkJ1CMHBADHAgAGAAIJrRTjeQA+AAAHAAIJGBMIcwA0AAABLgAECgkJHgAIAOEdAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMEAAkJBiFuBwA5AwAEAAkJBiFuBwA5AwAJAAEJ8gwQswAnAAAAAA==.',
Ai='Aimspet:BAABLgAECn8WAAIEAAYJmBOKXwA+AQAEAAYJmBOKXwA+AQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAIKAAkJIQ1sTQC6AQAKAAkJIQ1sTQC6AQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAABLgAECn8YAAICAAcJBxSIDgAsAQACAAcJBxSIDgAsAQAAAA==.Amonet:BAABLgAECn8ZAAILAAYJ1wfwGwC3AAALAAYJ1wfwGwC3AAAAAA==.',
An='Anaelcheese:BAABLgAECn8cAAQMAAcJ1xoPIwBfAQAMAAcJ1xoPIwBfAQANAAEJkg0sLgAnAAAOAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8uAAIPAAkJmBR2IQC3AQAPAAkJmBR2IQC3AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAEALgADCgYJCAAAAA==.Angras:BAABLgAECn9AAAIQAAkJOhhZLwBCAgAQAAkJOhhZLwBCAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgAECgcJBwAAAA==.Anolana:BAABLgAECn8+AAMRAAkJZiL6BADoAgARAAkJZiL6BADoAgASAAEJixEPJwA3AAAAAA==.Anrom:BAAALgAECgEJAQAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn9HAAITAAkJWRjbAAD4AQATAAkJWRjbAAD4AQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Arane:BAAALgAECgUJBwAAAA==.Ariûs:BAABLgAECn8gAAIUAAgJMxVtBwAbAQAUAAgJMxVtBwAbAQAAAA==.Arlin:BAABLgAECn8hAAIVAAYJLSOfAQA3AgAVAAYJLSOfAQA3AgAAAA==.Arlorian:BAABLgAECn85AAISAAkJLhWJBQAeAgASAAkJLhWJBQAeAgAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCAAAAA==.Arrowsmites:BAABLgAECn8zAAIKAAkJhRx5HQB0AgAKAAkJhRx5HQB0AgAAAA==.',
Au='Aubani:BAABLgAECn8xAAMVAAkJFCBlCQD1AgAVAAkJFCBlCQD1AgACAAUJIxII2wDkAAAAAA==.',
Aw='Awishanay:BAAALgADCgQJBAAAAA==.',
Ax='Axelot:BAAALgAECgQJBgAAAA==.',
Ay='Ayperos:BAABLgAECn9cAAMWAAkJ6BvIAABQAgAWAAkJ6BvIAABQAgAUAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJKwAXACQXAA==.',
Ba='Baboyago:BAAALgAECggJEQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJMAACAE4JAA==.Bakedpally:BAABLgAECn8wAAICAAkJTgnQFwDRAAACAAkJTgnQFwDRAAAAAA==.Bandomar:BAABLgAECn8uAAIGAAgJXBBfBABfAQAGAAgJXBBfBABfAQAAAA==.Baniemo:BAAALgAECgIJBQAAAA==.Banigor:BAAALgAECgYJEwAAAA==.Basak:BAAALgAECgYJCwABLgAFFAYJHQADAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Beargrillz:BAAALgAECgIJAgAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAICAAkJliEuEgDXAgACAAkJliEuEgDXAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJDwAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAABLgAECn8eAAIKAAYJKRYyDgA8AQAKAAYJKRYyDgA8AQAAAA==.Berreydingle:BAAALgAECgUJEAAAAA==.',
Bi='Bigfuut:BAAALgADCgEJAQAAAA==.Bigkitty:BAABLgAECn8qAAIUAAkJnhlLGgAbAgAUAAkJnhlLGgAbAgAAAA==.Bikinibrenda:BAABLgAFFH8FAAIWAAMJAAcmDwCsAAAWAAMJAAcmDwCsAAAAAA==.Birchum:BAAALgADCgcJBwABLgAECgYJCgADAAAAAA==.Biz:BAAALgADCgYJBwABLgAECgkJGwAYAOEhAA==.',
Bl='Blackanvil:BAABLgAECn8aAAIUAAgJ7BCkCQDsAAAUAAgJ7BCkCQDsAAAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECggJHwAUAPcbAA==.Blackhuuf:BAAALgADCgkJDAAAAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8nAAMZAAkJABZaBQCzAQAZAAkJABZaBQCzAQAYAAIJ5g2tlQA6AAAAAA==.Bloodsmage:BAAALgAECgMJAwAAAA==.Bloodymagi:BAABLgAECn8sAAILAAkJhQfJgwBwAQALAAkJhQfJgwBwAQAAAA==.Bluesummer:BAABLgAECn8fAAQUAAgJ9xsNJQDOAQAUAAcJrR4NJQDOAQAaAAYJxBrAGQCCAQAWAAEJCAzpQQA1AAAAAA==.',
Bo='Bobeh:BAAALgAECgUJCwABLgAECgkJMgACAEIfAA==.Boboh:BAAALgAECgUJBQABLgAECgkJMgACAEIfAA==.Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMHAAkJuhoBCgBIAgAHAAkJuhoBCgBIAgAGAAQJdQbVbQBtAAAAAA==.Borat:BAAALgAECgUJCgABLgAECgkJOAACAFolAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8bAAIYAAkJ4SH+CQCjAgAYAAkJ4SH+CQCjAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECggJDwAAAA==.Bròly:BAAALgAECgEJAQAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIbAAkJIxS3DgCKAQAbAAkJIxS3DgCKAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calquo:BAAALgAECgMJAwABLgAECggJNgARACEgAA==.Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgAECgYJCgAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAABLgAECn8ZAAIcAAYJDAUpDgCTAAAcAAYJDAUpDgCTAAAAAA==.Castration:BAABLgAECn8YAAIcAAYJ3AmOTgDVAAAcAAYJ3AmOTgDVAAAAAA==.Catavitch:BAAALgADCgIJAgAAAA==.',
Ce='Ceylan:BAABLgAECn8xAAMLAAkJgxlpMABXAgALAAkJgxlpMABXAgAdAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgYJCwAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMcAAkJhBZ4HADhAQAcAAkJhBZ4HADhAQAPAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheat:BAAALgAECgYJDQAAAA==.Cheatdr:BAABLgAECn8yAAIBAAkJgQ/6NQDCAQABAAkJgQ/6NQDCAQAAAA==.Cheatpriest:BAACLgAFFH8FAAIPAAMJpQqvDwCLAAAPAAMJpQqvDwCLAAAuAAQKfz8AAg8ACQmbGWkaAPcBAA8ACQmbGWkaAPcBAAAA.Chepis:BAAALgAECgUJCgAAAA==.Chesthyr:BAAALgAECgQJBQAAAA==.Chesto:BAABLgAECn89AAQeAAkJ7hx7BABVAgAeAAkJZBp7BABVAgATAAcJ4xplCgCeAQAIAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQAWADUeAA==.Chokea:BAAALgAECgkJDwAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.Chyrstal:BAAALgAECgEJAQAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAACLgAFFH8NAAIKAAMJxR5NIQD9AAAKAAMJxR5NIQD9AAAuAAQKf3IAAgoACQkcJl0BAIMDAAoACQkcJl0BAIMDAAAA.Coldvengance:BAABLgAECn89AAIUAAkJAQpoNgBuAQAUAAkJAQpoNgBuAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAADAAAAAA==.Cranknstein:BAAALgAECgIJAgABLgAECgIJBAADAAAAAA==.Crazycalla:BAABLgAFFH8FAAICAAMJiweKPwB+AAACAAMJiweKPwB+AAAAAA==.Critias:BAAALgADCgEJAQAAAA==.Crosbyy:BAAALgAECgUJCgAAAA==.Crànk:BAAALgAECgIJAwABLgAECgIJBAADAAAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIfAAkJCxrgDAA+AgAfAAkJCxrgDAA+AgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Daithi:BAABLgAECn8UAAIgAAYJXgtJQAAKAQAgAAYJXgtJQAAKAQAAAA==.Dakotà:BAABLgAECn8uAAIKAAkJyBtLLwAfAgAKAAkJyBtLLwAfAgAAAA==.Darc:BAAALgAECgUJBwAAAA==.Daredayo:BAAALgAECgEJAQAAAA==.Darkangelz:BAAALgAECgIJAgAAAA==.Darkkubo:BAAALgAECgEJAQAAAA==.Darklite:BAAALgADCgYJGAAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8lAAIKAAkJHhkWKwAxAgAKAAkJHhkWKwAxAgAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAABLgAECn8WAAIQAAgJdQk9FgDCAAAQAAgJdQk9FgDCAAAAAA==.Dejno:BAABLgAECn8YAAIUAAcJMiDjLACfAQAUAAcJMiDjLACfAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJLAAQADwlAA==.Demonicly:BAABLgAECn8YAAINAAgJPBLiDgBiAQANAAgJPBLiDgBiAQAAAA==.Demonred:BAAALgADCggJCAAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgAECgQJBAAAAA==.Dezign:BAACLgAFFH8ZAAILAAcJMxvOJQDiAQALAAcJMxvOJQDiAQAuAAQKfykAAgsACQl2IOooAM8CAAsACQl2IOooAM8CAAAA.Dezígn:BAABLgAFFH8IAAIIAAQJAhKeVAAdAQAIAAQJAhKeVAAdAQABLgAFFAcJGQALADMbAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMhAAYJQQxuUQC9AAAhAAUJvA5uUQC9AAAYAAEJVQIkwAAYAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAFFAMJBgAIABEOAA==.',
Do='Dobbi:BAAALgAFFAEJAQAAAA==.Dolgorukov:BAABLgAECn8vAAIKAAkJXhNORQDSAQAKAAkJXhNORQDSAQAAAA==.Dologony:BAABLgAECn8jAAIBAAkJmg4sQACRAQABAAkJmg4sQACRAQAAAA==.Dorgar:BAAALgAECgMJAwAAAA==.',
Dr='Dracigor:BAAALgAECgQJBwAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Dreåm:BAAALgADCgQJBAABLgAFFAMJBgAIABEOAA==.Drikken:BAACLgAFFH8GAAMNAAMJjA/CBQB2AAANAAIJqw7CBQB2AAAOAAIJbgzeNgBvAAAuAAQKf0YABA4ACQkTHXMHAE0BAA4ACQmnG3MHAE0BAA0ABQnbG+AUAAcBAAwABQmAFkYwAAYBAAAA.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAIMAAkJVxgdGADCAQAMAAkJVxgdGADCAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJLAAQADwlAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8lAAMbAAcJ9gy7GQAFAQAbAAUJMg67GQAFAQAQAAcJWwdpygDwAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMTAAgJIhX0CQCmAQATAAgJIhX0CQCmAQAIAAIJZwswDQFbAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECggJDwAAAA==.Effinfu:BAABLgAECn8pAAIhAAkJ3RIoAwAxAQAhAAkJ3RIoAwAxAQAAAA==.',
Ei='Eitent:BAACLgAFFH8JAAIVAAMJTxq3DQDjAAAVAAMJTxq3DQDjAAAuAAQKfzAAAxUACQm7HcUNAKoCABUACQm7HcUNAKoCAAIABwm6EhF2AI4BAAEuAAUUAwkKACAAqxMA.Eitentormu:BAAALgAECggJCAABLgAFFAMJCgAgAKsTAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJIQAVAN4gAA==.Ellesthara:BAABLgAECn8UAAIBAAcJNwlrDgB3AAABAAcJNwlrDgB3AAAAAA==.Ellysiaa:BAABLgAECn8XAAIFAAYJ3QWeMgCVAAAFAAYJ3QWeMgCVAAAAAA==.Elrïc:BAAALgAECgYJCgAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8zAAMGAAkJwRV+GQAAAgAGAAkJwRV+GQAAAgABAAcJMA0rWAAwAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgcJHAAAAA==.Enyxea:BAABLgAECn8bAAIEAAkJ8ReaKgARAgAEAAkJ8ReaKgARAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJEQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgIJAwAAAA==.',
Es='Esmeray:BAEBLgAECn8eAAIgAAkJQhYmEgBUAgAgAAkJQhYmEgBUAgABLgAECgkJKwAXACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8kAAIiAAkJVh8LBADHAgAiAAkJVh8LBADHAgAAAA==.Eyewana:BAABLgAECn8kAAIMAAkJchKbHQCPAQAMAAkJchKbHQCPAQAAAA==.',
Ez='Ezzka:BAACLgAFFH8JAAIQAAMJKSA4JAAjAQAQAAMJKSA4JAAjAQAuAAQKfycAAhAACQkJHWkgAIcCABAACQkJHWkgAIcCAAAA.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8eAAQIAAkJ4R0KHwBqAgAIAAgJ+x0KHwBqAgATAAMJGBxCIQCkAAAeAAEJNBPrOQBBAAAAAA==.Farzix:BAABLgAECn8qAAIJAAkJKQn3PABCAQAJAAkJKQn3PABCAQAAAA==.Façade:BAABLgAECn8mAAIQAAkJDxMYYACpAQAQAAkJDxMYYACpAQAAAA==.',
Fe='Feelgood:BAAALgAECgcJCwAAAA==.Fefifiona:BAACLgAFFH8FAAIgAAIJOA2fQAB3AAAgAAIJOA2fQAB3AAAuAAQKfxkAAiAACQkqF2sQAGoCACAACQkqF2sQAGoCAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAgADgNAA==.Fefifuredric:BAAALgAECgQJBQABLgAFFAIJBQAgADgNAA==.Felvira:BAABLgAECn8dAAMOAAgJPgTO1ACLAAAOAAYJbQPO1ACLAAAMAAUJWwRCWgBZAAAAAA==.',
Fi='Finnw:BAABLgAECn8hAAIVAAcJ3iDmEACPAgAVAAcJ3iDmEACPAgAAAA==.Firelite:BAABLgAECn8oAAIJAAkJYw/9OwBFAQAJAAkJYw/9OwBFAQAAAA==.',
Fl='Flairlock:BAABLgAECn8/AAMeAAkJZyGxAgCfAgAeAAkJZyGxAgCfAgATAAIJBhW3PAA5AAAAAA==.Flee:BAABLgAECn8iAAIRAAkJqRoKDwA7AgARAAkJqRoKDwA7AgAAAA==.Flexo:BAAALgAECgYJBQABLgAECgkJHgAIAOEdAA==.',
Fo='Fookster:BAABLgAECn8ZAAILAAkJyhPfQAAaAgALAAkJyhPfQAAaAgAAAA==.Forsetee:BAABLgAFFH8GAAIhAAIJTReHRACQAAAhAAIJTReHRACQAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAISAAkJUxCwBwDcAQASAAkJUxCwBwDcAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAADAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgAQACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAABLgAECn8hAAIaAAYJzRNsBAAJAQAaAAYJzRNsBAAJAQAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJMAAQANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.Genericeric:BAAALgADCgQJBAAAAA==.',
Gi='Gilas:BAAALgADCgYJEAAAAA==.',
Gl='Glacialkitty:BAABLgAECn8vAAIBAAkJ4gvhRgB0AQABAAkJ4gvhRgB0AQAAAA==.Glizzygoblin:BAAALgAECgEJAQAAAA==.',
Go='Googoobler:BAABLgAECn8mAAIMAAgJ7QmqLwAJAQAMAAgJ7QmqLwAJAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECgkJKgAUAJ4ZAA==.Goudanight:BAAALgAECgMJBQABLgAECgkJKgAUAJ4ZAA==.Goudavibes:BAAALgAECgEJAQABLgAECgkJKgAUAJ4ZAA==.',
Gr='Greenmagus:BAAALgAECgQJBAAAAA==.Grenadon:BAABLgAECn8eAAIHAAYJrQU4DAB/AAAHAAYJrQU4DAB/AAAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQeAAgJ/wSbEQATAQAeAAgJ9gSbEQATAQAIAAMJBAMCMQE5AAATAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gulem:BAAALgADCgYJBgAAAA==.Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn9AAAIcAAkJOx0NDQCCAgAcAAkJOx0NDQCCAgAAAA==.Hakitua:BAABLgAECn8mAAINAAkJ2w1pDgBqAQANAAkJ2w1pDgBqAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDgAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn9AAAIUAAkJ1A/3KAC2AQAUAAkJ1A/3KAC2AQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAABLgAECn83AAQaAAkJBibGAABpAwAaAAkJBibGAABpAwAUAAcJ7hyOHgD6AQAWAAMJvxAeTQCbAAABLgAFFAMJBgAIABEOAA==.Heis:BAABLgAECn8hAAIUAAYJERo2BACDAQAUAAYJERo2BACDAQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAICAAkJABcwQwD9AQACAAkJABcwQwD9AQAAAA==.',
Hi='Hiko:BAABLgAECn8fAAMhAAgJjhAzBAD6AAAhAAgJjhAzBAD6AAAYAAEJggNDugAfAAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMEAAYJJgqFAgC9AQAEAAYJJgqFAgC9AQAJAAUJFB/mHQAuAQAuAAQKfyEAAwkACQlzIWYDAG0DAAkACQlzIWYDAG0DAAQABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgAEACYKAA==.Holyangus:BAAALgAECgUJDQAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.Hulahoof:BAAALgAECgcJDgAAAA==.',
Ib='Ibbert:BAAALgAECgEJAQAAAA==.',
Ic='Icculus:BAABLgAECn8sAAIKAAgJzxsVBAAyAgAKAAgJzxsVBAAyAgAAAA==.Iceticles:BAAALgAECgYJBQAAAA==.',
Il='Illuyanka:BAAALgAECgIJAgAAAA==.',
Im='Imaresmashy:BAAALgAECgMJAwABLgAECgkJJAADAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIhAAkJaSTgAQBKAwAhAAkJaSTgAQBKAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgADAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Iy='Iyrus:BAAALgAECgkJCQAAAA==.',
Ja='Jacolynn:BAABLgAECn8ZAAIZAAcJBRLsKwBXAQAZAAcJBRLsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.',
Jo='Joansnow:BAAALgAECgcJBwABLgAECgkJJwAZAAAWAA==.Joatmoa:BAACLgAFFH8GAAIFAAMJNRTlDQDbAAAFAAMJNRTlDQDbAAAuAAQKfxQAAgUACQmIHP8PALcBAAUACQmIHP8PALcBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Johnlebron:BAAALgAECgEJAgABLgAECgcJDgADAAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECggJEgAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCggJJgAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAABLgAECn8eAAITAAgJkhamCwCFAQATAAgJkhamCwCFAQAAAA==.Kaitoi:BAABLgAECn8jAAMFAAkJ7BzPBACtAgAFAAkJ7BzPBACtAgAHAAUJKwi0TAB4AAAAAA==.Kalinth:BAAALgADCgIJAgAAAA==.Kallah:BAACLgAFFH8lAAIVAAgJcB8ZCAA/AgAVAAgJcB8ZCAA/AgAuAAQKfzcAAhUACQnsI44BAGsDABUACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9BAAQjAAkJHBkSCQBZAgAjAAgJjxkSCQBZAgAXAAkJnBGJBwDCAQAkAAEJMRl5EwBEAAAAAA==.Kamakizeg:BAACLgAFFH8FAAICAAIJIQ1SkwCNAAACAAIJIQ1SkwCNAAAuAAQKfy8AAgIACQl3FA1RANUBAAIACQl3FA1RANUBAAAA.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8oAAILAAkJdh2kIQCXAgALAAkJdh2kIQCXAgAAAA==.',
Ke='Kestrelle:BAABLgAECn8ZAAIPAAcJCQoKCADmAAAPAAcJCQoKCADmAAABLgAECgkJVgABAFQSAA==.Keyzeus:BAABLgAECn8lAAMXAAgJCxibBgDjAQAXAAgJCxibBgDjAQAkAAEJ5xsAhwBOAAAAAA==.',
Kh='Khas:BAAALgADCgkJHQAAAA==.Khui:BAACLgAFFH8cAAIZAAcJ7SQDCgBoAgAZAAcJ7SQDCgBoAgAuAAQKfyUAAxkACAkWJcACAFcDABkACAkWJcACAFcDABgAAwkwGLdSAL4AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8bAAMQAAgJ2xekJQDWAQAQAAcJ2xekJQDWAQAfAAEJAAB8VgAAAAAuAAQKfygAAhAACQn9INMSAAsDABAACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIZAAkJ/RciFgBpAgAZAAkJ/RciFgBpAgABLgAFFAgJGwAQANsXAA==.',
Ko='Koltharaz:BAABLgAFFH8IAAIkAAUJqAeQEQALAQAkAAUJqAeQEQALAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAADAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krankthas:BAAALgAECgIJAgABLgAECgIJBAADAAAAAA==.Krazylock:BAAALgAECgQJCAAAAA==.Krazysniper:BAABLgAECn8oAAMKAAgJCRy0MAAZAgAKAAcJEB+0MAAZAgAlAAEJ4wmKYgA3AAAAAA==.Kreepa:BAAALgADCgIJAgAAAA==.Krokk:BAABLgAECn8UAAIJAAcJ9QdiVQDlAAAJAAcJ9QdiVQDlAAAAAA==.Kruulock:BAAALgADCgcJBwAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAYJHQADAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMCAAgJFh66KgB5AgACAAgJFh66KgB5AgAVAAYJOBheOwBbAQAAAA==.Lacosanostra:BAABLgAECn8UAAMYAAYJ2wRPDAB3AAAYAAYJ2wRPDAB3AAAZAAMJkQSdJwA7AAAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lancedragon:BAAALgADCgEJAQAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgACABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8rAAIKAAkJjxi2TwCzAQAKAAkJjxi2TwCzAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lenard:BAAALgADCgQJBAAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8fAAICAAcJAhIflgBIAQACAAcJAhIflgBIAQAAAA==.Lightguard:BAABLgAECn8WAAMCAAkJoAYmHAC0AAACAAUJJgcmHAC0AAAiAAYJLwSyDABUAAAAAA==.Lighthouse:BAABLgAECn8wAAICAAkJlxtFNQArAgACAAkJlxtFNQArAgAAAA==.Lileth:BAAALgAECggJCQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIOAAgJ9RVJWwB2AQAOAAgJ9RVJWwB2AQAAAA==.Lolhahabaha:BAAALgAECggJDQAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8fAAIfAAgJURSYBAApAQAfAAgJURSYBAApAQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwAKAPgfAA==.',
Ly='Lypally:BAABLgAECn9OAAICAAkJrRt3AwBcAgACAAkJrRt3AwBcAgAAAA==.',
['Là']='Làdedá:BAAALgAECgYJCgAAAA==.',
['Lï']='Lïllïth:BAAALgAECgkJDwAAAA==.Lïly:BAAALgADCggJEAABLgAECgkJJAADAAAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAIOAAkJziMYCAAPAwAOAAkJziMYCAAPAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8oAAMRAAgJGRaLBQBkAgARAAgJGRaLBQBkAgASAAYJOw8xAwBvAQAuAAQKfyEAAxEACAlGHtkMAMsCABEACAlGHtkMAMsCABIAAQnoGt8aAFEAAAAA.Magegrizz:BAAALgAECgcJBgAAAA==.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAImAAkJphVTCgAUAgAmAAkJphVTCgAUAgAAAA==.Mariacuras:BAABLgAECn8WAAIVAAkJ7AqDMQCRAQAVAAkJ7AqDMQCRAQAAAA==.Marle:BAABLgAECn87AAIOAAkJ1Rj0AgDxAQAOAAkJ1Rj0AgDxAQAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgUJBwAAAA==.Martis:BAAALgAFFAEJAQAAAA==.Marynne:BAABLgAECn9WAAMBAAkJVBKMLgDrAQABAAkJVBKMLgDrAQAGAAEJSwKerAAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8zAAMNAAkJvxc0BwASAgANAAkJUBc0BwASAgAMAAIJ7xm/CwCOAAAAAA==.',
Mc='Mcdo:BAAALgAFFAIJAgABLgAFFAcJFQAnANAeAA==.Mctank:BAAALgAECgEJAQAAAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgAECgUJBQAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMcAAgJhQ8nKgCAAQAcAAgJhQ8nKgCAAQAPAAUJxQwWTgCqAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8qAAQCAAcJgBreCACHAQACAAYJVhzeCACHAQAVAAYJ2w/DDAB0AAAiAAIJRg3tDABSAAAAAA==.Meliza:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.Merrikeath:BAABLgAECn8cAAIQAAkJPgjxEQDkAAAQAAkJPgjxEQDkAAAAAA==.Merriklade:BAABLgAECn8zAAMaAAkJAA8oFwCKAQAaAAkJRw4oFwCKAQAUAAgJzQozOwBZAQAAAA==.Merrikoid:BAAALgAECgUJCAAAAA==.Merrikwolf:BAAALgAECgYJDgAAAA==.',
Mi='Misamina:BAAALgAECgMJAwAAAA==.Missyjelliot:BAAALgAECggJDwAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morbidstyle:BAAALgAECgYJCgABLgAFFAYJGgAKAOAVAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgAECgQJBwABLgAECgYJCgADAAAAAA==.Morthos:BAAALgAECgUJCAAAAA==.Mousé:BAAALgAECgEJAwAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJIQAVAN4gAA==.',
My='Myora:BAEBLgAECn8bAAIRAAkJ1RG8EwAGAgARAAkJ1RG8EwAGAgABLgAECgkJKwAXACQXAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAABLgAECn8YAAMfAAkJbBFQAwB5AQAfAAkJbBFQAwB5AQAbAAcJ8QiDGgD8AAAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIiAAkJWhLcEQCoAQAiAAkJWhLcEQCoAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQAWADUeAA==.Nakasid:BAACLgAFFH8KAAIPAAMJYxEBIgCqAAAPAAMJYxEBIgCqAAAuAAQKfz4ABA8ACQl5GRsCAAwCAA8ACQl5GRsCAAwCABwABwkVCNQ5ACIBACAABAlbCntcAI0AAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Naura:BAAALgADCgMJAwAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAIOAAkJsBDpQwC8AQAOAAkJsBDpQwC8AQAAAA==.Nevaehstar:BAACLgAFFH8GAAIdAAMJexGZAQDKAAAdAAMJexGZAQDKAAAuAAQKf0EAAh0ACQkcI1sAAC8DAB0ACQkcI1sAAC8DAAAA.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJDQAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8uAAIPAAkJOxQKIADDAQAPAAkJOxQKIADDAQAAAA==.Nikolia:BAABLgAECn8UAAMaAAcJgQ2wBgCyAAAaAAUJgA+wBgCyAAAUAAUJzgaREwBtAAAAAA==.Ninetynine:BAAALgADCgMJBQAAAA==.Nini:BAABLgAECn8nAAIGAAgJvgKcXQCgAAAGAAgJvgKcXQCgAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAAMANcSAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgAECggJCAAAAA==.',
Nz='Nzuul:BAABLgAECn8VAAIOAAUJeAazGQB/AAAOAAUJeAazGQB/AAAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
On='Onram:BAAALgAECgEJAQAAAA==.',
Op='Oppaissiah:BAABLgAECn9EAAMaAAkJ6iNPAgAlAwAaAAkJlSNPAgAlAwAUAAkJ8R/7CQDDAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawJudgB5AAAkAAYJawJudgB5AAABLgAECgkJEgADAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAFFAIJAgAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAABLgAECgkJNQACANcKAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Pandamared:BAAALgADCggJCgAAAA==.Papasbich:BAABLgAECn8lAAIMAAcJawllCADLAAAMAAcJawllCADLAAABLgAFFAMJCgACAG0FAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Ph='Phantazm:BAAALgADCgEJAQAAAA==.Phenol:BAAALgADCgUJBQAAAA==.Phoxie:BAAALgAECgEJAQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgAECgEJAgAAAA==.Porkchopw:BAAALgAECgcJAgAAAA==.Porkribs:BAABLgAFFH8HAAIVAAMJ2RafDgDVAAAVAAMJ2RafDgDVAAAAAA==.',
Pr='Presap:BAABLgAECn8zAAMBAAkJBCJuBQBhAwABAAkJBCJuBQBhAwAGAAEJAACrdgBJAAABLgAECgkJGQAjAKwcAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAABLgAECn8hAAIFAAYJnBiDAgBWAQAFAAYJnBiDAgBWAQAAAA==.Pumdmuc:BAACLgAFFH8QAAIPAAQJCRxTEQBEAQAPAAQJCRxTEQBEAQAuAAQKf0oAAw8ACQnlIdoGAN8CAA8ACQnlIdoGAN8CABwABwkqBbVTAMMAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAFFAMJBAAAAA==.Quille:BAABLgAECn8fAAIKAAgJSiPzDgDZAgAKAAgJSiPzDgDZAgAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIiAAkJrRJqEQCuAQAiAAkJrRJqEQCuAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJDAAAAA==.Redrek:BAAALgADCggJKwAAAA==.Redsbank:BAAALgADCgMJBgAAAA==.Redshunter:BAAALgADCgcJEgAAAA==.Redsknight:BAAALgADCgkJDAAAAA==.Redsmonk:BAAALgADCgcJFQAAAA==.Redwinter:BAAALgAECgIJBAABLgAECggJHwAUAPcbAA==.Reikisong:BAAALgAECggJDQAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgQJBAAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAFFAEJAQAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8tAAMBAAgJbBf+AgDnAQABAAgJbBf+AgDnAQAGAAEJigk9GgAoAAAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJCgAAAA==.Rockrat:BAAALgADCgEJAQAAAA==.Rodeo:BAABLgAECn8sAAIGAAkJABCiIwCtAQAGAAkJABCiIwCtAQAAAA==.Rotgutwiskey:BAAALgAECgIJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAAALgAECggJDwAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIOAAYJeQ6eegA4AQAOAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgcJCgAAAA==.Sadnhornless:BAAALgAECgEJAwAAAA==.Saeti:BAACLgAFFH8VAAMFAAQJex7ICQARAQAFAAMJfiDICQARAQAGAAEJbxiNSQBMAAAuAAQKfz8ABQUACQlIIZYHAG8CAAUACQlAIZYHAG8CAAYABgkKHTIrAHwBAAcABAk2HlIrAAQBAAEABAkUFoqIAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sanh:BAAALgAECgEJAQAAAA==.Sapplesauce:BAABLgAECn8XAAIRAAgJ5Bc9HgCkAQARAAgJ5Bc9HgCkAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Sedael:BAAALgAECgEJAQABLgAECgYJIQAVAC0jAA==.Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8MAAMBAAMJQglQGgB8AAABAAMJQglQGgB8AAAGAAEJ4wYnUQA0AAAuAAQKf1gAAwEACQkwH/ALAAEDAAEACQkwH/ALAAEDAAYABgmbE5Y4ADEBAAAA.',
Sh='Shadý:BAABLgAECn8vAAIKAAkJ5AoTVgCiAQAKAAkJ5AoTVgCiAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJLAAQADwlAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQTAAgJLBqNCwCIAQAIAAgJ1hcKRADPAQATAAcJeBiNCwCIAQAeAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn9IAAIUAAkJohxfDgCLAgAUAAkJohxfDgCLAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAAALgAECgcJDgABLgAECgkJVgABAFQSAA==.Sidarya:BAABLgAECn8ZAAMPAAgJgRcDGgD7AQAPAAgJgRcDGgD7AQAcAAIJZgeBHQAqAAAAAA==.Sidera:BAAALgAECggJDgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8ZAAMUAAQJVhz9FQBeAQAUAAQJVhz9FQBeAQAWAAEJPAxiQgBDAAAuAAQKfx4AAxYACQmjFs4ZACUBABQABwlxFW5EADQBABYABgkoEs4ZACUBAAAA.Silveric:BAAALgADCgYJCQAAAA==.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAABLgAECn8WAAIKAAcJgA5LhAA2AQAKAAcJgA5LhAA2AQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9SAAMEAAkJQBbDBADcAQAEAAkJQBbDBADcAQAJAAgJQAiaSgAKAQAAAA==.Skyscales:BAEALgAECgcJBwABLgAECgkJUgAEAEAWAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.Slipknaught:BAAALgAECgQJAwABLgAECgkJJwAZAAAWAA==.',
Sm='Smileyriley:BAABLgAECn8bAAIGAAcJcgbfTwDOAAAGAAcJcgbfTwDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgADAAAAAA==.Snot:BAAALgADCgEJAQAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAABLgAECn8XAAIZAAUJCwRzlQBtAAAZAAUJCwRzlQBtAAAAAA==.Solarêclipse:BAAALgAECgMJAwAAAA==.Sooki:BAAALgAECgIJBAAAAA==.Sorath:BAAALgAECgMJAwAAAA==.Sorilea:BAAALgADCgkJEQAAAA==.Sorlis:BAAALgAECgcJEwAAAA==.Soulber:BAABLgAECn8bAAMQAAkJwRTjWAC7AQAQAAkJ5RPjWAC7AQAfAAIJnxxUPACgAAAAAA==.Sourdew:BAABLgAECn8eAAIYAAcJtB7ZGQDiAQAYAAcJtB7ZGQDiAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8ZAAMjAAkJrBwjBADzAgAjAAkJrBwjBADzAgAXAAEJAAA/LwAAAAAAAA==.Splashgordon:BAAALgAECgQJBAABLgAECgkJGQAjAKwcAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwADAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stefeana:BAAALgAECgYJBgAAAA==.Stelle:BAABLgAECn8XAAIgAAgJBBEYJABzAQAgAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgIJAgAAAA==.Stylos:BAABLgAECn9BAAImAAgJPBclDADwAQAmAAgJPBclDADwAQAAAA==.Stãrburst:BAABLgAECn8UAAMEAAgJZQr4ewDsAAAEAAcJswf4ewDsAAAJAAEJUASqvwAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAFFAMJBgAdAHsRAA==.Sumofwhy:BAAALgAECgMJAwAAAA==.',
Sy='Sylven:BAAALgADCgYJBgABLgAFFAMJBgAIABEOAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECggJEwAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQfAAgJNBm8EwDXAQAfAAgJVBi8EwDXAQAQAAgJBQ8oZwDAAQAbAAEJAACfGgAeAAABLgAECgkJDgADAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgADAAAAAA==.Tempestrike:BAAALgAFFAIJAwAAAA==.Terentia:BAEALgAECgUJBQABLgAECgkJKwAXACQXAA==.',
Th='Thadind:BAAALgAECgQJBAAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJHgAIAOEdAA==.Tharelly:BAABLgAECn8XAAILAAkJrxi6OwArAgALAAkJrxi6OwArAgAAAA==.Thasserian:BAAALgADCgIJAgABLgAFFAMJBgAIABEOAA==.Theholymatt:BAACLgAFFH8XAAMVAAcJqxZBFgB2AQAVAAUJAxRBFgB2AQACAAUJBRb4FwAWAQAuAAQKf0AAAwIACQkoJEcIACkDAAIACQkoJEcIACkDABUABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn+GAAITAAkJpBmbAAA5AgATAAkJpBmbAAA5AgAAAA==.Theodus:BAABLgAECn81AAILAAkJhxlIOAA3AgALAAkJhxlIOAA3AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxorHAD0AQAkAAgJfxorHAD0AQABLgAFFAcJFwAVAKsWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn9PAAMWAAkJYiSUAgAfAwAWAAkJJSSUAgAfAwAUAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8WAAMVAAUJ4hraEQClAQAVAAUJ4hraEQClAQACAAMJpwMLNwCXAAAuAAQKfz0AAhUACQn3IDgFAEADABUACQn3IDgFAEADAAAA.Tislam:BAABLgAECn8bAAIIAAkJag6zaABrAQAIAAkJag6zaABrAQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQWAAkJNR7NBACaAgAWAAkJFhrNBACaAgAaAAcJpSCYDwDuAQAUAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn9RAAIPAAkJMR0IAQCtAgAPAAkJMR0IAQCtAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIaAAkJJBMGFACvAQAaAAkJJBMGFACvAQABLgAECgQJBAADAAAAAA==.Torolf:BAAALgAECggJEAAAAA==.Torsen:BAAALgADCgUJBgAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJBAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8gAAMJAAgJ5BRyCAAsAgAJAAgJ5BRyCAAsAgAEAAEJYAwCegBLAAAuAAQKf0gAAgkACQnMIswEABQDAAkACQnMIswEABQDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8rAAQbAAkJhyKlAQAYAwAbAAkJhyKlAQAYAwAfAAEJah2JVABIAAAQAAEJmALGpgEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tu='Tumnus:BAAALgADCgMJBAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tye:BAAALgAECgIJAgAAAA==.Tyranastrasz:BAABLgAECn83AAQjAAkJ8RR/DgDmAQAjAAkJ8RR/DgDmAQAXAAEJ6gYPKQAqAAAkAAEJWQSeGAAgAAAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAIRAAkJ4QXSKABRAQARAAkJ4QXSKABRAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIOAAgJOxgFTgCcAQAOAAgJOxgFTgCcAQAAAA==.Vaerryn:BAABLgAECn8mAAQbAAgJMyOABgA8AgAbAAcJFiOABgA8AgAQAAMJcBv80gDkAAAfAAIJQyCDUQBPAAAAAA==.Vaethund:BAAALgAECgkJEwAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAANAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Valkz:BAAALgADCgEJAQAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vaneesha:BAAALgADCgMJBgAAAA==.Vanesah:BAAALgAECgEJAgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8bAAMlAAkJ5ww1KABeAQAlAAcJxQw1KABeAQAKAAgJ1wpcLQBgAAAAAA==.Vassyra:BAEBLgAECn8rAAIXAAkJJBdOBQAOAgAXAAkJJBdOBQAOAgAAAA==.',
Ve='Velara:BAAALgAECgcJDAAAAA==.Velesyn:BAABLgAECn8cAAMNAAgJUx9UBwAOAgANAAcJKCBUBwAOAgAOAAIJtxH7/QBOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.Venekor:BAAALgADCgUJBQAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAACLgAFFH8KAAIgAAMJqxMDGACpAAAgAAMJqxMDGACpAAAuAAQKfygAAyAACQlbGWgMAKcCACAACQlbGWgMAKcCABwACAnVFwYaAPUBAAAA.Volundr:BAABLgAECn9AAAIaAAkJ7xgNDgAKAgAaAAkJ7xgNDgAKAgAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECgkJGwAYAOEhAA==.',
Vy='Vynel:BAAALgAECgYJCQABLgAFFAMJBgAIABEOAA==.Vynirion:BAABLgAECn8UAAILAAcJqxJUpACPAQALAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8iAAIRAAkJPQfyAwBCAQARAAkJPQfyAwBCAQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn82AAIRAAgJISD8DQBIAgARAAgJISD8DQBIAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8bAAMPAAcJ4BKKNgAmAQAPAAcJ4BKKNgAmAQAgAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whatcow:BAAALgAFFAEJAQAAAA==.Whiteback:BAAALgADCgUJBQAAAA==.Whiterrina:BAAALgADCgkJCgAAAA==.',
Wi='Window:BAAALgAECgEJAQAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8iAAMGAAkJ9AjhMgBPAQAGAAkJ9AjhMgBPAQABAAUJEgfQiwCfAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIKAAkJywobVgBmAQAKAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn83AAMEAAkJDSMoDQDuAgAEAAkJDSMoDQDuAgAJAAcJyRiaKACqAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8aAAILAAgJPgcsoQA5AQALAAgJPgcsoQA5AQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ye='Yet:BAABLgAECn84AAMCAAkJWiVTBQBKAwACAAkJWiVTBQBKAwAVAAUJ/xuHAwCWAQAAAA==.',
Yi='Yiffweaver:BAABLgAECn80AAIhAAkJKAyBAgBkAQAhAAkJKAyBAgBkAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn80AAIiAAkJfhNXEAC/AQAiAAkJfhNXEAC/AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAABLgAECn8hAAIGAAkJ0AkPCADoAAAGAAkJ0AkPCADoAAAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIGAAkJgBBHIgC3AQAGAAkJgBBHIgC3AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.Zephnor:BAAALgAECgkJDwAAAA==.',
Zm='Zmona:BAABLgAECn8xAAICAAkJHg+aZwCgAQACAAkJHg+aZwCgAQAAAA==.',
Zo='Zorsche:BAAALgAECgQJBAAAAA==.',
Zu='Zulrok:BAABLgAECn8tAAIUAAkJbB3wEgBbAgAUAAkJbB3wEgBbAgAAAA==.',
['Åv']='Åviendha:BAAALgADCgkJEQAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAILAAcJ0hZswwBfAQALAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAABLgAECn8VAAICAAYJ6wNdDgGnAAACAAYJ6wNdDgGnAAAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8uAAILAAkJUiPnFADcAgALAAkJUiPnFADcAgAAAA==.',
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
