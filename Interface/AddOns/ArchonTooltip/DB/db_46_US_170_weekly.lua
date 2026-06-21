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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Balance','Druid-Guardian','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Holy','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Druid-Restoration','Warlock-Affliction','DeathKnight-Blood','Monk-Brewmaster','Priest-Discipline','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Shaman-Enhancement','Hunter-Marksmanship',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=46,date='2026-06-20',data={Ac='Achilles:BAAALgADCgEJAQAAAA==.',
Ad='Aderan:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Adoraluna:BAAALgAECgEJAQAAAA==.Adunei:BAAALgAECgIJAgAAAA==.',
Ae='Aeginalla:BAAALgADCgcJEgABLgAECgYJCAABAAAAAA==.Aela:BAAALgADCgEJAQABLgAECgkJMwACAAYhAA==.Aesalon:BAABLgAECn80AAQDAAkJ1CMHBADHAgADAAkJ1CMHBADHAgAEAAIJrRTjeQA+AAAFAAIJGBMHcwA0AAABLgAECgkJHgAGAOEdAA==.',
Ah='Ahsokatano:BAABLgAECn8zAAMCAAkJBiFwBwA5AwACAAkJBiFwBwA5AwAHAAEJ8gwMswAnAAAAAA==.',
Ai='Aimspet:BAABLgAECn8VAAICAAYJ+xCDXwA+AQACAAYJ+xCDXwA+AQAAAA==.Aircanada:BAAALgAECgIJBAAAAA==.',
Ak='Akela:BAABLgAECn8oAAIIAAkJIQ1rTQC6AQAIAAkJIQ1rTQC6AQAAAA==.',
Al='Algorithm:BAAALgAECgMJAwAAAA==.Alissu:BAAALgADCgIJAgAAAA==.Alvonaar:BAAALgADCgUJBwAAAA==.',
Am='Ames:BAAALgAECgcJEgAAAA==.Amonet:BAABLgAECn8UAAIJAAUJtAeLBwCbAAAJAAUJtAeLBwCbAAAAAA==.',
An='Anaelcheese:BAABLgAECn8aAAQKAAcJ2BQOIwBfAQAKAAcJ2BQOIwBfAQALAAEJkg0sLgAnAAAMAAEJywAN9wATAAAAAA==.Anamis:BAABLgAECn8uAAINAAkJmBRzIQC3AQANAAkJmBRzIQC3AQAAAA==.Andrina:BAAALgADCgYJAgAAAA==.Angeldemon:BAAALgADCgYJCAAAAA==.Angras:BAABLgAECn88AAIOAAkJOBdWLwBCAgAOAAkJOBdWLwBCAgAAAA==.Angryorc:BAAALgAECgQJBQAAAA==.Anja:BAAALgAECgcJBwAAAA==.Anolana:BAABLgAECn8+AAMPAAkJZiL6BADoAgAPAAkJZiL6BADoAgAQAAEJixEOJwA3AAAAAA==.Anrom:BAAALgAECgEJAQAAAA==.Anyday:BAAALgADCgcJBwAAAA==.',
Ap='Aphalock:BAABLgAECn9CAAIRAAkJlRcmAAD9AQARAAkJlRcmAAD9AQAAAA==.',
Ar='Aragoth:BAAALgAECgEJAQAAAA==.Ariûs:BAABLgAECn8YAAISAAgJQhJsLQCcAQASAAgJQhJsLQCcAQAAAA==.Arlin:BAABLgAECn8aAAITAAUJ/CJ8AADeAQATAAUJ/CJ8AADeAQAAAA==.Arlorian:BAABLgAECn85AAIQAAkJLhWJBQAeAgAQAAkJLhWJBQAeAgAAAA==.Arorra:BAAALgAECgYJBgAAAA==.Arrex:BAAALgAECgYJCAAAAA==.Arrowsmites:BAABLgAECn8yAAIIAAkJhRx6HQB0AgAIAAkJhRx6HQB0AgAAAA==.',
Au='Aubani:BAABLgAECn8xAAMTAAkJFCBlCQD1AgATAAkJFCBlCQD1AgAUAAUJIxIG2wDkAAAAAA==.',
Ax='Axelot:BAAALgAECgQJAwAAAA==.',
Ay='Ayperos:BAABLgAECn9NAAMVAAkJzRsmAABJAgAVAAkJzRsmAABJAgASAAYJPxAVUgBhAQAAAA==.Ayvaria:BAEALgAECgYJEwABLgAECgkJKwAWACQXAA==.',
Az='Azorus:BAAALgADCgEJAQAAAA==.',
Ba='Baboyago:BAAALgAECggJEQAAAA==.Badgerbrew:BAAALgADCgkJCQAAAA==.Bahemith:BAAALgAECgEJAQAAAA==.Baked:BAAALgAECgQJBAABLgAECgkJIQAUAMcGAA==.Bakedpally:BAABLgAECn8hAAIUAAkJxwZPoQA1AQAUAAkJxwZPoQA1AQAAAA==.Bandomar:BAABLgAECn8mAAIEAAgJywvRNQA/AQAEAAgJywvRNQA/AQAAAA==.Baniemo:BAAALgAECgIJBAAAAA==.Banigor:BAAALgAECgYJEAAAAA==.Basak:BAAALgAECgYJCwABLgAFFAUJFgABAAAAAQ==.',
Be='Beammescotty:BAAALgADCgQJBAAAAA==.Bearnuts:BAAALgADCgEJAQAAAA==.Beck:BAABLgAECn81AAIUAAkJliEtEgDXAgAUAAkJliEtEgDXAgAAAA==.Beefflaps:BAAALgADCgEJAQAAAA==.Beggars:BAAALgAECgYJDQAAAA==.Belithsong:BAAALgAECgkJBwAAAA==.Bereth:BAABLgAECn8XAAIIAAUJZBmdiAAtAQAIAAUJZBmdiAAtAQAAAA==.Berreydingle:BAAALgAECgUJEAAAAA==.',
Bi='Bigkitty:BAABLgAECn8qAAISAAkJnhlLGgAbAgASAAkJnhlLGgAbAgABLgAECgkJNgAIAKoiAA==.Bikinibrenda:BAAALgAECgEJAQAAAA==.Birchum:BAAALgADCgcJBwAAAA==.Biz:BAAALgADCgYJBwABLgAECggJFwAXAOMhAA==.',
Bl='Blackanvil:BAABLgAECn8aAAISAAgJ7BDqAQDzAAASAAgJ7BDqAQDzAAAAAA==.Blackautumn:BAAALgADCgcJDgABLgAECggJHwASAPcbAA==.Blackhuuf:BAAALgADCgUJBQAAAA==.Blainn:BAAALgAECgcJBwAAAA==.Blindfred:BAAALgAECggJDQAAAA==.Blitzedbust:BAAALgADCggJDQAAAA==.Bloodredsky:BAABLgAECn8hAAMYAAkJhBKPKgDYAQAYAAkJhBKPKgDYAQAXAAIJ5g2ulQA6AAAAAA==.Bloodsmage:BAAALgAECgMJAwAAAA==.Bloodymagi:BAABLgAECn8qAAIJAAkJQgfIgwBwAQAJAAkJQgfIgwBwAQAAAA==.Bluesummer:BAABLgAECn8fAAQSAAgJ9xsMJQDOAQASAAcJrR4MJQDOAQAZAAYJxBrAGQCCAQAVAAEJCAzpQQA1AAAAAA==.',
Bo='Bolts:BAAALgAECgEJAwAAAA==.Boomin:BAABLgAECn8wAAMFAAkJuhoBCgBIAgAFAAkJuhoBCgBIAgAEAAQJdQbTbQBtAAAAAA==.Borat:BAAALgAECgUJCgABLgAECgkJMQAUANokAA==.',
Br='Brendameeks:BAAALgAECgcJEAAAAA==.Brewnashot:BAAALgADCggJCgAAAA==.Brewrain:BAAALgADCgEJAQAAAA==.Broadzinatl:BAABLgAECn8XAAIXAAgJ4yH+CQCjAgAXAAgJ4yH+CQCjAgAAAA==.Brom:BAAALgAECgYJBwAAAA==.Brïn:BAAALgAECggJDwAAAA==.Bròly:BAAALgADCgYJBgAAAA==.',
Bu='Bulwark:BAAALgADCgYJBgAAAA==.Bushwookië:BAAALgAECgIJAgAAAA==.',
['Bã']='Bãthory:BAABLgAECn8XAAIaAAkJIxS3DgCKAQAaAAkJIxS3DgCKAQAAAA==.',
['Bø']='Bøss:BAAALgADCgkJEQAAAA==.',
Ca='Calquo:BAAALgAECgMJAwABLgAECgcJNQAPAHchAA==.Calvert:BAAALgAECgUJBgAAAA==.Captnhammer:BAAALgAECgIJBAAAAA==.Carebearr:BAAALgADCgcJBwAAAA==.Carnelian:BAAALgAECgUJEgAAAA==.Castration:BAABLgAECn8YAAIbAAYJ3AmLTgDVAAAbAAYJ3AmLTgDVAAAAAA==.',
Ce='Ceylan:BAABLgAECn8xAAMJAAkJgxlsMABXAgAJAAkJgxlsMABXAgAcAAEJVQMVIQAqAAAAAA==.',
Ch='Chadillac:BAAALgAECgMJAwAAAA==.Chaleb:BAAALgAECgUJCgAAAA==.Charavane:BAAALgAECgQJBAAAAA==.Charlz:BAABLgAECn8jAAMbAAkJhBZ3HADhAQAbAAkJhBZ3HADhAQANAAQJChHLVQDfAAAAAA==.Charsifood:BAAALgAECgcJDwAAAA==.Chass:BAAALgADCgQJBAAAAA==.Cheatdr:BAABLgAECn8tAAIdAAkJLA/8NQDCAQAdAAkJLA/8NQDCAQAAAA==.Cheatpriest:BAABLgAECn89AAINAAkJmxlnGgD3AQANAAkJmxlnGgD3AQAAAA==.Chepis:BAAALgAECgUJBQAAAA==.Chesthyr:BAAALgAECgEJAQAAAA==.Chesto:BAABLgAECn89AAQeAAkJ7hx8BABVAgAeAAkJZBp8BABVAgARAAcJ4xplCgCeAQAGAAcJwRT2awCKAQAAAA==.Chimerax:BAAALgAECgIJAgAAAA==.Chimken:BAAALgAECgcJCAABLgAECgkJKQAVADUeAA==.Chokea:BAAALgAECgkJDwAAAA==.Chrome:BAAALgAECgEJAQAAAA==.Chuwhee:BAAALgADCgYJBgAAAA==.',
Ci='Cindrethresh:BAAALgAECgUJBQAAAA==.',
Co='Cognition:BAACLgAFFH8HAAIIAAIJ5h5sCQCxAAAIAAIJ5h5sCQCxAAAuAAQKf2IAAggACQkcJl4BAIMDAAgACQkcJl4BAIMDAAAA.Coldvengance:BAABLgAECn89AAISAAkJAQpnNgBuAQASAAkJAQpnNgBuAQAAAA==.Corpser:BAAALgADCgUJBQAAAA==.',
Cr='Cranki:BAAALgAECgUJBgABLgAECgIJBAABAAAAAA==.Cranknstein:BAAALgAECgIJAgABLgAECgIJBAABAAAAAA==.Crazycalla:BAAALgAFFAEJAgAAAA==.Crosbyy:BAAALgAECgUJCgAAAA==.Crànk:BAAALgAECgIJAwABLgAECgIJBAABAAAAAA==.',
Cy='Cymindel:BAABLgAECn84AAIfAAkJCxriDAA+AgAfAAkJCxriDAA+AgAAAA==.',
Da='Dad:BAAALgADCgQJBAAAAA==.Daelein:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Daithi:BAAALgAECgcJEwAAAA==.Dakotà:BAABLgAECn8qAAIIAAgJJRpMLwAfAgAIAAgJJRpMLwAfAgAAAA==.Darc:BAAALgAECgQJBgAAAA==.Darkkubo:BAAALgAECgEJAQAAAA==.Darklite:BAAALgADCgYJEgAAAA==.Darkmonk:BAAALgADCgUJBQAAAA==.Dassadin:BAAALgAECgQJBQAAAA==.Davinci:BAAALgADCgEJAQAAAA==.Day:BAABLgAECn8lAAIIAAkJHhkUKwAxAgAIAAkJHhkUKwAxAgAAAA==.Dayztocome:BAAALgADCgEJAQAAAA==.',
De='Decaydence:BAABLgAECn8WAAIOAAgJewmwAwDkAAAOAAgJewmwAwDkAAAAAA==.Dejno:BAABLgAECn8YAAISAAcJMiDjLACfAQASAAcJMiDjLACfAQAAAA==.Deleted:BAAALgAECgEJAQABLgAECgkJKgAOAOgkAA==.Demonicly:BAABLgAECn8UAAILAAcJuxPjDgBiAQALAAcJuxPjDgBiAQAAAA==.Demonred:BAAALgADCgYJBgAAAA==.Demönslayer:BAAALgAECgcJAwAAAA==.Derowski:BAAALgAECgQJBQAAAA==.Deroz:BAAALgADCgUJBQAAAA==.Dethra:BAAALgAECgMJAwAAAA==.Dezign:BAACLgAFFH8XAAIJAAcJcRjnJQDiAQAJAAcJcRjnJQDiAQAuAAQKfygAAgkACQl2IOooAM8CAAkACQl2IOooAM8CAAAA.Dezígn:BAABLgAFFH8IAAIGAAQJAhK4VAAdAQAGAAQJAhK4VAAdAQABLgAFFAcJFwAJAHEYAA==.',
Di='Diabolical:BAAALgAECgEJAQAAAA==.Discordegirl:BAABLgAECn8WAAMgAAYJQQxuUQC9AAAgAAUJvA5uUQC9AAAXAAEJVQIjwAAYAAAAAA==.Divinitÿ:BAAALgADCgIJAgABLgAECgkJLAAGAL8jAA==.',
Do='Dolgorukov:BAABLgAECn8vAAIIAAkJXhNORQDSAQAIAAkJXhNORQDSAQAAAA==.Dologony:BAABLgAECn8jAAIdAAkJmg4uQACRAQAdAAkJmg4uQACRAQAAAA==.',
Dr='Dracigor:BAAALgAECgQJBQAAAA==.Draconair:BAAALgADCgYJCAAAAA==.Dragonsbaine:BAAALgADCgMJAwAAAA==.Dragonz:BAAALgAECgUJEQAAAA==.Drakhan:BAAALgADCgIJAgAAAA==.Dre:BAAALgAECgMJCAAAAA==.Dreåm:BAAALgADCgQJBAABLgAECgkJLAAGAL8jAA==.Drikken:BAABLgAECn9FAAQMAAkJSByNLAAWAgAMAAkJ3BqNLAAWAgALAAUJ2xvgFAAHAQAKAAUJgBZDMAAGAQAAAA==.Drmaker:BAAALgAECgMJAwAAAA==.Drougs:BAABLgAECn8uAAIKAAkJVxgdGADCAQAKAAkJVxgdGADCAQAAAA==.Druiddeleted:BAAALgAECgEJAQABLgAECgkJKgAOAOgkAA==.',
Du='Dubbshot:BAAALgAECgEJAQAAAA==.Dumara:BAAALgADCgIJAgAAAA==.Durasan:BAABLgAECn8lAAMaAAcJ9gy7GQAFAQAaAAUJMg67GQAFAQAOAAcJWwdhygDwAAAAAA==.Duressa:BAAALgAECgcJBwAAAA==.',
Dy='Dymund:BAAALgAECgIJBAAAAA==.',
['Dà']='Dàrkside:BAAALgAECgYJBgAAAA==.',
['Dö']='Dötdötdead:BAABLgAECn8pAAMRAAgJIhX0CQCmAQARAAgJIhX0CQCmAQAGAAIJZwsvDQFbAAAAAA==.',
Ea='Earthie:BAAALgADCgEJAQAAAA==.Earthstorm:BAAALgADCgIJAgAAAA==.Eastwubz:BAAALgADCgIJAgAAAA==.',
Ed='Edge:BAAALgAECgMJBQAAAA==.',
Ef='Effin:BAAALgADCgUJBQAAAA==.Effindin:BAAALgAECgUJBwAAAA==.Effinfu:BAABLgAECn8lAAIgAAkJpRCVHwCqAQAgAAkJpRCVHwCqAQAAAA==.',
Ei='Eitent:BAABLgAECn8wAAMTAAkJux3FDQCqAgATAAkJux3FDQCqAgAUAAcJuhIRdgCOAQABLgAFFAMJBwAhAGITAA==.Eitentormu:BAAALgAECggJCAABLgAFFAMJBwAhAGITAA==.',
El='Ele:BAAALgADCgcJCAABLgAECgcJHQATALEfAA==.Ellesthara:BAAALgAECgcJEwAAAA==.Ellysiaa:BAABLgAECn8WAAIDAAYJLQWfMgCVAAADAAYJLQWfMgCVAAAAAA==.Elrïc:BAAALgAECgUJBgAAAA==.Elwynlana:BAAALgADCgYJBwAAAA==.Elysa:BAAALgADCgEJAQAAAA==.',
Em='Emberstorm:BAAALgAECgQJBQAAAA==.Emmakyn:BAABLgAECn8zAAMEAAkJrxV7GQAAAgAEAAkJrxV7GQAAAgAdAAcJMA0wWAAwAQAAAA==.',
En='Enezath:BAAALgADCgIJAgAAAA==.Entrerie:BAAALgADCgcJFgAAAA==.Enyxea:BAABLgAECn8XAAICAAgJFReXKgARAgACAAgJFReXKgARAgAAAA==.',
Ep='Ephemera:BAAALgAECgYJEQAAAA==.Epsolon:BAAALgAECgIJAgAAAA==.',
Er='Erikuh:BAAALgADCgEJAQAAAA==.Erodin:BAAALgAECgEJAgAAAA==.',
Es='Esmeray:BAEBLgAECn8eAAIhAAkJIhbvAABnAQAhAAkJIhbvAABnAQABLgAECgkJKwAWACQXAA==.Estala:BAAALgADCgUJBQAAAA==.',
Ey='Eyedontknow:BAABLgAECn8kAAIiAAkJVh8LBADHAgAiAAkJVh8LBADHAgAAAA==.Eyewana:BAABLgAECn8kAAIKAAkJchKaHQCPAQAKAAkJchKaHQCPAQAAAA==.',
Ez='Ezzka:BAABLgAECn8lAAIOAAkJmxxqIACHAgAOAAkJmxxqIACHAgAAAA==.',
Fa='Faelan:BAAALgADCgIJAQAAAA==.Fakesaint:BAAALgAECgYJDgAAAA==.Fangalor:BAAALgAECgEJBAAAAA==.Farnsworth:BAABLgAECn8eAAQGAAkJ4R0KHwBqAgAGAAgJ+x0KHwBqAgARAAMJGBxAIQCkAAAeAAEJNBPrOQBBAAAAAA==.Farzix:BAABLgAECn8qAAIHAAkJKQn2PABCAQAHAAkJKQn2PABCAQAAAA==.Façade:BAABLgAECn8mAAIOAAkJDxMWYACpAQAOAAkJDxMWYACpAQAAAA==.',
Fe='Feelgood:BAAALgAECgYJCgAAAA==.Fefifiona:BAACLgAFFH8FAAIhAAIJOA2iQAB3AAAhAAIJOA2iQAB3AAAuAAQKfxkAAiEACQkqF2oQAGoCACEACQkqF2oQAGoCAAAA.Fefifredrich:BAAALgAECgMJAwABLgAFFAIJBQAhADgNAA==.Fefifuredric:BAAALgAECgQJBQABLgAFFAIJBQAhADgNAA==.Felvira:BAABLgAECn8dAAMMAAgJPgTM1ACLAAAMAAYJbQPM1ACLAAAKAAUJWwRAWgBZAAAAAA==.',
Fi='Finnw:BAABLgAECn8dAAITAAcJsR/nEACPAgATAAcJsR/nEACPAgAAAA==.Firelite:BAABLgAECn8lAAIHAAgJCQ/7OwBFAQAHAAgJCQ/7OwBFAQAAAA==.',
Fl='Flairlock:BAABLgAECn8/AAMeAAkJZyGxAgCfAgAeAAkJZyGxAgCfAgARAAIJBhW2PAA5AAAAAA==.Flee:BAABLgAECn8iAAIPAAkJqRoHDwA7AgAPAAkJqRoHDwA7AgAAAA==.',
Fo='Fookster:BAABLgAECn8ZAAIJAAkJyhPhQAAaAgAJAAkJyhPhQAAaAgAAAA==.Forsetee:BAABLgAFFH8GAAIgAAIJTReURACPAAAgAAIJTReURACPAAAAAA==.',
Fr='Frowdawn:BAABLgAECn87AAIQAAkJUxCwBwDcAQAQAAkJUxCwBwDcAQAAAA==.',
Fy='Fyf:BAAALgAECgYJBgABLgAECgIJBAABAAAAAA==.',
['Fí']='Físter:BAAALgAECgYJDwABLgAECgcJGgAOACoaAA==.',
Ga='Ga:BAAALgAECgIJAgAAAA==.Galadris:BAAALgADCgkJDwAAAA==.Garythenpc:BAABLgAECn8aAAIZAAUJDhRAAQDJAAAZAAUJDhRAAQDJAAAAAA==.Gaztoria:BAAALgADCggJCAABLgAECgkJMAAOANYiAA==.',
Ge='Genavieve:BAAALgADCgQJBAAAAA==.Gendra:BAAALgAECgEJAQAAAA==.',
Gh='Ghøst:BAAALgADCgYJCQAAAA==.',
Gi='Gilas:BAAALgADCgYJCgAAAA==.',
Gl='Glacialkitty:BAABLgAECn8vAAIdAAkJ4gvkRgB0AQAdAAkJ4gvkRgB0AQAAAA==.',
Go='Googoobler:BAABLgAECn8iAAIKAAgJ7AenLwAJAQAKAAgJ7AenLwAJAQAAAA==.Goudaluck:BAAALgADCgUJBwABLgAECgkJNgAIAKoiAA==.Goudanight:BAAALgAECgMJBQABLgAECgkJNgAIAKoiAA==.Goudavibes:BAAALgAECgEJAQABLgAECgkJNgAIAKoiAA==.',
Gr='Greenmagus:BAAALgAECgQJBAAAAA==.Grenadon:BAABLgAECn8XAAIFAAUJiQQIBABdAAAFAAUJiQQIBABdAAAAAA==.Gridimbor:BAAALgAECgEJAQAAAA==.Grimlilith:BAABLgAECn8bAAQeAAgJ/wSbEQATAQAeAAgJ9gSbEQATAQAGAAMJBAMBMQE5AAARAAEJAAAogQALAAAAAA==.Grimmhoof:BAAALgAECgIJAgAAAA==.Grundy:BAAALgAECgUJCAAAAA==.',
Gu='Gulem:BAAALgADCgYJBgAAAA==.Gumbi:BAAALgADCgIJAgAAAA==.',
Ha='Hadorya:BAABLgAECn9AAAIbAAkJOx0PDQCCAgAbAAkJOx0PDQCCAgAAAA==.Hakitua:BAABLgAECn8mAAILAAkJ2w1pDgBqAQALAAkJ2w1pDgBqAQAAAA==.Hangi:BAAALgADCgkJCQAAAA==.Happymeel:BAAALgAECgEJAQAAAA==.Harleyqûinn:BAAALgAECgcJDgAAAA==.Hatshepsut:BAAALgAECgEJAQAAAA==.Hazard:BAABLgAECn9AAAISAAkJ1A/3KAC2AQASAAkJ1A/3KAC2AQAAAA==.',
He='Healonwheels:BAAALgADCgMJAwAAAA==.Heimdall:BAABLgAECn8pAAQZAAkJ3iXGAABpAwAZAAkJ3iXGAABpAwASAAcJ7hyNHgD6AQAVAAMJvxAcTQCbAAABLgAECgkJLAAGAL8jAA==.Heis:BAABLgAECn8aAAISAAUJiBiGAQAXAQASAAUJiBiGAQAXAQAAAA==.Hellboii:BAAALgAECggJEwAAAA==.Heyitsrat:BAABLgAECn8xAAIUAAkJABcwQwD9AQAUAAkJABcwQwD9AQAAAA==.',
Hi='Hiko:BAABLgAECn8YAAMgAAgJzw14KgBiAQAgAAgJzw14KgBiAQAXAAEJggNBugAfAAAAAA==.',
Ho='Holo:BAACLgAFFH8SAAMCAAYJJgqFAgC9AQACAAYJJgqFAgC9AQAHAAUJFB/nHQAuAQAuAAQKfyEAAwcACQlzIWYDAG0DAAcACQlzIWYDAG0DAAIABwnXDgJCAHkBAAAA.Holos:BAAALgAECgEJAQABLgAFFAYJEgACACYKAA==.Holyangus:BAAALgAECgUJDAAAAA==.Holyfawn:BAAALgADCgEJAQAAAA==.Holyyknight:BAAALgAECgcJEwAAAA==.',
Hu='Hugecrit:BAAALgADCgkJDwAAAA==.Hulahoof:BAAALgADCgQJBAAAAA==.',
Ib='Ibbert:BAAALgADCggJFQAAAA==.',
Ic='Icculus:BAABLgAECn8lAAIIAAgJJxkqOQD5AQAIAAgJJxkqOQD5AQAAAA==.',
Il='Illuyanka:BAAALgAECgIJAgAAAA==.',
Im='Imaresmashy:BAAALgAECgIJAgABLgAECgkJJAABAAAAAA==.Impasse:BAAALgAECgkJCAAAAA==.',
In='Indaskyz:BAAALgADCgEJAQAAAA==.',
Io='Iolz:BAAALgAECgYJCgAAAA==.',
Ir='Ironfist:BAABLgAECn8+AAIgAAkJaSTgAQBKAwAgAAkJaSTgAQBKAwAAAA==.',
It='Itankworlds:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.',
Iw='Iwanaplay:BAAALgAECgMJAwAAAA==.',
Ja='Jacolynn:BAABLgAECn8YAAIYAAcJ7BHsKwBXAQAYAAcJ7BHsKwBXAQAAAA==.Jaenei:BAAALgAECgcJDwAAAA==.',
Je='Jelly:BAAALgADCgIJAgAAAA==.',
Ji='Jinrok:BAAALgAECgUJBgAAAA==.',
Jo='Joansnow:BAAALgAECgcJBwABLgAECgkJIQAYAIQSAA==.Joatmoa:BAACLgAFFH8GAAIDAAMJNRTjDQDbAAADAAMJNRTjDQDbAAAuAAQKfxQAAgMACQmIHP0PALcBAAMACQmIHP0PALcBAAAA.Joeexotics:BAAALgADCgkJDAAAAA==.Jordanleah:BAAALgAECgQJBAAAAA==.',
Ju='July:BAAALgAECgcJEAAAAA==.Julytonidas:BAAALgAECgcJBwAAAA==.Jurac:BAAALgADCgcJGwAAAA==.',
Ka='Kaelnis:BAAALgAECggJEgAAAA==.Kaimargonar:BAABLgAECn8bAAIRAAgJ+RKnCwCFAQARAAgJ+RKnCwCFAQAAAA==.Kaitoi:BAABLgAECn8jAAMDAAkJ7BzOBACtAgADAAkJ7BzOBACtAgAFAAUJKwiwTAB4AAAAAA==.Kalinth:BAAALgADCgIJAgAAAA==.Kallah:BAACLgAFFH8eAAITAAcJwhweCAA/AgATAAcJwhweCAA/AgAuAAQKfzcAAhMACQnsI44BAGsDABMACQnsI44BAGsDAAAA.Kalthos:BAABLgAECn9BAAQjAAkJHBkSCQBZAgAjAAgJjxkSCQBZAgAWAAkJnBGJBwDCAQAkAAEJMRmoBABFAAAAAA==.Kamakizeg:BAACLgAFFH8FAAIUAAIJIQ1WkwCNAAAUAAIJIQ1WkwCNAAAuAAQKfy8AAhQACQl7FA5RANUBABQACQl7FA5RANUBAAAA.Kamayla:BAAALgADCgYJBgAAAA==.Karnus:BAAALgADCgUJBQAAAA==.Kaspen:BAAALgADCgMJAwAAAA==.Kateria:BAABLgAECn8nAAIJAAkJKR2lIQCXAgAJAAkJKR2lIQCXAgAAAA==.',
Ke='Kestrelle:BAAALgAECgcJEwABLgAECgkJUwAdAAkSAA==.Keyzeus:BAABLgAECn8lAAMWAAgJCxibBgDjAQAWAAgJCxibBgDjAQAkAAEJ5xv7hgBOAAAAAA==.',
Kh='Khas:BAAALgADCgkJHAAAAA==.Khui:BAACLgAFFH8bAAIYAAYJSyUGCgBoAgAYAAYJSyUGCgBoAgAuAAQKfyUAAxgACAkWJcACAFcDABgACAkWJcACAFcDABcAAwkwGLVSAL4AAAAA.',
Ki='Kiarorin:BAAALgAECgEJAQAAAA==.Killerdeath:BAAALgAECgQJBwAAAA==.Kipziep:BAAALgAECgIJAgAAAA==.',
Kn='Knìghtmàrè:BAACLgAFFH8XAAMOAAcJ6Be3JQDWAQAOAAYJ6Be3JQDWAQAfAAEJAAB9VgAAAAAuAAQKfygAAg4ACQn9INMSAAsDAA4ACQn9INMSAAsDAAAA.Kníghtfíst:BAABLgAECn8rAAIYAAkJ/RclFgBpAgAYAAkJ/RclFgBpAgABLgAFFAcJFwAOAOgXAA==.',
Ko='Koltharaz:BAAALgAECgEJAQAAAA==.Korheo:BAAALgADCgUJBQAAAA==.Korloff:BAAALgAECgcJDQABLgAECgcJHAABAAAAAQ==.Kozan:BAAALgAECgcJHAAAAQ==.',
Kr='Krankthas:BAAALgAECgIJAgABLgAECgIJBAABAAAAAA==.Krazylock:BAAALgAECgIJAgAAAA==.Krazysniper:BAABLgAECn8oAAMIAAgJCRy1MAAZAgAIAAcJEB+1MAAZAgAlAAEJ4wmKYgA3AAAAAA==.Kreepa:BAAALgADCgIJAgAAAA==.Krokk:BAABLgAECn8UAAIHAAcJ9QdfVQDlAAAHAAcJ9QdfVQDlAAAAAA==.Kruulock:BAAALgADCgcJBwAAAA==.',
Ku='Kungfister:BAAALgAECgEJAQAAAA==.Kur:BAAALgAFFAEJAQABLgAFFAUJFgABAAAAAQ==.',
La='Laatt:BAABLgAECn8aAAMUAAgJFh66KgB5AgAUAAgJFh66KgB5AgATAAYJOBhdOwBbAQAAAA==.Lacosanostra:BAAALgAECgYJCwAAAA==.Laeiny:BAAALgADCgYJBgAAAA==.Lateralus:BAAALgAECgUJBgABLgAECggJGgAUABYeAA==.Latharel:BAAALgAECgEJAQAAAA==.Lawluss:BAABLgAECn8nAAIIAAcJ5hm3TwCzAQAIAAcJ5hm3TwCzAQAAAA==.Layethelor:BAAALgAECgEJBAAAAA==.',
Le='Legacyshot:BAAALgAECgkJJAAAAQ==.Leigola:BAAALgADCgUJCQAAAA==.Lela:BAAALgAECgYJBgAAAA==.Lezsul:BAAALgAECgIJAgAAAA==.',
Li='Lickthecrit:BAAALgAECggJEgAAAA==.Lidrelle:BAABLgAECn8fAAIUAAcJAhIglgBIAQAUAAcJAhIglgBIAQAAAA==.Lightguard:BAAALgAECgYJDwAAAA==.Lighthouse:BAABLgAECn8uAAIUAAkJlxtHNQArAgAUAAkJlxtHNQArAgAAAA==.Lileth:BAAALgAECgUJBQAAAA==.Lilpaws:BAAALgAECgYJBgAAAA==.Lizy:BAAALgADCgUJBQAAAA==.',
Lo='Locust:BAAALgAECgMJAwAAAA==.Lokkar:BAAALgADCgQJBAAAAA==.Lolalazer:BAABLgAECn8WAAIMAAgJ9RVKWwB2AQAMAAgJ9RVKWwB2AQAAAA==.Lolhahabaha:BAAALgAECggJDAAAAA==.Loopie:BAAALgADCgYJCgAAAA==.Lovesomev:BAAALgADCgMJAwAAAA==.',
Lu='Luckÿ:BAABLgAECn8XAAIfAAcJlxVwIwA4AQAfAAcJlxVwIwA4AQAAAA==.Lunabelle:BAAALgADCgEJAQAAAA==.Lunchbox:BAAALgAECgkJAQAAAA==.Lustfull:BAAALgAECgEJAgABLgAECgkJHwAIAPgfAA==.',
Ly='Lypally:BAABLgAECn9JAAIUAAkJHxm9AAA/AgAUAAkJHxm9AAA/AgAAAA==.',
['Lï']='Lïllïth:BAAALgAECgEJAQAAAA==.',
['Ló']='Lóla:BAABLgAECn8wAAIMAAkJziMZCAAPAwAMAAkJziMZCAAPAwAAAA==.',
['Lô']='Lônè:BAAALgAECgUJBwAAAA==.',
Ma='Maani:BAAALgAECgEJAQAAAA==.Madeah:BAACLgAFFH8oAAMPAAgJGRaVBQBkAgAPAAgJGRaVBQBkAgAQAAYJOw8xAwBvAQAuAAQKfyEAAw8ACAlGHtkMAMsCAA8ACAlGHtkMAMsCABAAAQnoGt8aAFEAAAAA.Mahimahi:BAAALgAECggJCAAAAA==.Malýs:BAAALgAECgEJAQAAAA==.Mardain:BAABLgAECn8fAAImAAkJphVTCgAUAgAmAAkJphVTCgAUAgAAAA==.Mariacuras:BAABLgAECn8WAAITAAkJ7AqDMQCRAQATAAkJ7AqDMQCRAQAAAA==.Marle:BAABLgAECn87AAIMAAkJ1hiBAAAOAgAMAAkJ1hiBAAAOAgAAAA==.Marlete:BAAALgADCgYJBQAAAA==.Marshoon:BAAALgAECgUJBwAAAA==.Martis:BAAALgAECgYJBwAAAA==.Marynne:BAABLgAECn9TAAMdAAkJCRKOLgDrAQAdAAkJCRKOLgDrAQAEAAEJSwKWrAAMAAAAAA==.Matthis:BAAALgAECgUJBwAAAA==.Mazuko:BAABLgAECn8zAAMLAAkJvxczBwASAgALAAkJUBczBwASAgAKAAIJ7xlZAgCPAAAAAA==.',
Mc='Mcdo:BAAALgAFFAIJAgABLgAFFAYJFAAnALAhAA==.',
Me='Medadh:BAAALgADCgUJBQAAAA==.Meepe:BAAALgADCgcJDAAAAA==.Meilnesar:BAAALgAECgIJAgAAAA==.Melaerissa:BAABLgAECn8wAAMbAAgJhQ8mKgCAAQAbAAgJhQ8mKgCAAQANAAUJxQwQTgCqAAAAAA==.Melbrooks:BAAALgADCgcJDQAAAA==.Melivant:BAABLgAECn8fAAMUAAYJLxu/AwABAQAUAAYJLxu/AwABAQATAAUJJQ/ZVwDXAAAAAA==.Merrikeath:BAABLgAECn8ZAAIOAAkJ2ge2dgB2AQAOAAkJ2ge2dgB2AQAAAA==.Merriklade:BAABLgAECn8zAAMZAAkJAA8qFwCKAQAZAAkJRw4qFwCKAQASAAgJzQoyOwBZAQAAAA==.',
Mi='Missyjelliot:BAAALgAECggJDwAAAA==.',
Mo='Monster:BAAALgADCgEJAQAAAA==.Moof:BAAALgADCgEJAQAAAA==.Morbidstyle:BAAALgAECgQJBQAAAA==.Morchuk:BAAALgADCgMJAwAAAA==.Morigith:BAAALgAECgQJBAABLgAECgUJBgABAAAAAA==.Morthos:BAAALgAECgMJBgAAAA==.',
Mw='Mw:BAAALgADCgIJAgABLgAECgcJHQATALEfAA==.',
My='Myora:BAEBLgAECn8bAAIPAAkJ1RG8EwAGAgAPAAkJ1RG8EwAGAgABLgAECgkJKwAWACQXAA==.Mythundirus:BAAALgADCgMJAwAAAA==.',
['Mà']='Màrli:BAAALgAECgcJDwAAAA==.',
['Mâ']='Mâgs:BAABLgAECn8gAAIiAAkJWhLcEQCoAQAiAAkJWhLcEQCoAQAAAA==.',
Na='Nabbed:BAAALgAECgcJCAABLgAECgkJKQAVADUeAA==.Nakasid:BAACLgAFFH8KAAINAAMJYxECIgCqAAANAAMJYxECIgCqAAAuAAQKfzUABA0ACQnWF2oRAFYCAA0ACQnWF2oRAFYCABsABwkVCNQ5ACIBACEABAlbCnpcAI0AAAAA.Nalaya:BAAALgAECgEJAQAAAA==.Nashoba:BAAALgADCgQJBAAAAA==.Natooka:BAAALgAECggJDgAAAA==.Navane:BAAALgAECgUJBwAAAA==.',
Ne='Necromaniac:BAAALgAECgEJAQAAAA==.Neenja:BAAALgADCgYJBgAAAA==.Nefurtatta:BAAALgADCgEJAQAAAA==.Nertlogi:BAAALgADCgIJAgAAAA==.Nesrÿn:BAAALgADCgIJAgAAAA==.Nestina:BAAALgADCgMJBAAAAA==.Netherkeeper:BAABLgAECn8rAAIMAAkJsBDmQwC8AQAMAAkJsBDmQwC8AQAAAA==.Nevaehstar:BAABLgAECn8+AAIcAAkJeSJbAAAvAwAcAAkJeSJbAAAvAwAAAA==.Neverëst:BAAALgAECgEJAQAAAA==.',
Ni='Nibuto:BAAALgAECgQJCwAAAA==.Nightvision:BAAALgADCgMJAgAAAA==.Nijun:BAEBLgAECn8uAAINAAkJOxQHIADDAQANAAkJOxQHIADDAQAAAA==.Nikolia:BAAALgAECgUJCAAAAA==.Ninetynine:BAAALgADCgMJBQAAAA==.Nini:BAABLgAECn8nAAIEAAgJvgKXXQCgAAAEAAgJvgKXXQCgAAAAAA==.Ninx:BAAALgAECgQJBAAAAA==.Nirazal:BAAALgADCgQJBQAAAA==.',
No='Noivana:BAAALgAFFAMJAwABLgAFFAUJEAAKANcSAA==.Nokru:BAAALgADCgMJBQAAAA==.Norgannia:BAAALgADCgkJDwAAAA==.Notprepared:BAAALgADCgEJAQAAAA==.Noys:BAAALgADCgcJDAAAAA==.',
Nz='Nzuul:BAAALgAECgQJCQAAAA==.',
Ol='Oldbenkenobi:BAAALgAECgQJCAAAAA==.Ollichi:BAAALgADCgQJBAAAAA==.Ollifuzzle:BAAALgAECgEJAwAAAA==.',
Om='Ominous:BAAALgAECgMJAwAAAA==.',
Op='Oppaissiah:BAABLgAECn9EAAMZAAkJ6iNPAgAlAwAZAAkJlSNPAgAlAwASAAkJ8R/5CQDDAgAAAA==.',
Or='Oraclespyro:BAABLgAECn8XAAIkAAYJawJudgB5AAAkAAYJawJudgB5AAABLgAECgkJDwABAAAAAA==.Orlakx:BAAALgADCggJFAAAAA==.Orman:BAAALgAECgEJAQAAAA==.',
Os='Osoroshi:BAAALgAECgQJBAAAAA==.',
Ov='Ovrind:BAAALgADCgEJAQAAAA==.',
Oz='Ozài:BAAALgADCgcJCgAAAA==.',
Pa='Padmê:BAAALgAECgcJDAAAAA==.Pandamared:BAAALgADCggJCgAAAA==.Papasbich:BAABLgAECn8eAAIKAAcJOggOAgCiAAAKAAcJOggOAgCiAAABLgAECgkJUgAUAGQWAA==.Patronous:BAAALgADCgUJBgAAAA==.',
Pe='Percthirty:BAAALgAECgEJAgAAAA==.Permafrost:BAAALgADCggJCgAAAA==.Perscila:BAAALgADCgUJBQAAAA==.',
Ph='Phantazm:BAAALgADCgEJAQAAAA==.',
Pi='Piggy:BAAALgAECgQJBgAAAA==.',
Pl='Planet:BAAALgADCgEJAQAAAA==.',
Po='Porkchoplust:BAAALgAECgEJAQAAAA==.Porkchopw:BAAALgAECgcJAgAAAA==.Porkribs:BAAALgAFFAIJAgAAAA==.',
Pr='Presap:BAABLgAECn8zAAMdAAkJBCJuBQBiAwAdAAkJBCJuBQBiAwAEAAEJAACrdgBJAAABLgAECgkJGAAjAKwcAA==.Promethius:BAAALgADCgQJBAAAAA==.Proscris:BAAALgADCgUJBQAAAA==.Prïsm:BAAALgADCgYJBgAAAA==.',
Pt='Ptmuchuk:BAAALgADCgYJBgAAAA==.',
Pu='Puca:BAABLgAECn8aAAIDAAUJVBjSAAD/AAADAAUJVBjSAAD/AAAAAA==.Pumdmuc:BAACLgAFFH8NAAINAAQJCRxVEQBEAQANAAQJCRxVEQBEAQAuAAQKf0QAAw0ACQnlIdoGAN8CAA0ACQnlIdoGAN8CABsABwkqBbJTAMMAAAAA.Purrie:BAAALgADCgIJAgAAAA==.',
['Pâ']='Pâlly:BAAALgAECgcJEAAAAA==.',
Qu='Quikglaives:BAAALgAFFAMJBAAAAA==.Quille:BAABLgAECn8eAAIIAAgJSiP1DgDZAgAIAAgJSiP1DgDZAgAAAA==.',
Ra='Rahhem:BAABLgAECn8eAAIiAAkJrRJqEQCuAQAiAAkJrRJqEQCuAQAAAA==.Rallo:BAAALgAECgEJAQAAAA==.Rayspaly:BAAALgAECgMJBAAAAA==.',
Re='Recbra:BAAALgAECgIJAgAAAA==.Reddelish:BAAALgADCgYJDAAAAA==.Redrek:BAAALgADCggJHAAAAA==.Redsbank:BAAALgADCgMJAwAAAA==.Redshunter:BAAALgADCgcJDAAAAA==.Redsknight:BAAALgADCgkJCQAAAA==.Redsmonk:BAAALgADCgcJFQAAAA==.Redwinter:BAAALgAECgIJBAABLgAECggJHwASAPcbAA==.Reikisong:BAAALgAECgMJBAAAAA==.Remmie:BAAALgAECgYJDAAAAA==.Retrolbution:BAAALgADCgkJEQAAAA==.Reylia:BAAALgAECgQJBAAAAA==.Reznik:BAAALgAECgEJAQAAAA==.',
Rh='Rhagurion:BAAALgAFFAEJAQAAAA==.Rhaokir:BAAALgADCgIJAgAAAA==.',
Ri='Riqua:BAABLgAECn8lAAIdAAgJJhSiLwDlAQAdAAgJJhSiLwDlAQAAAA==.',
Ro='Rockmonsta:BAAALgAECgUJCAAAAA==.Rodeo:BAABLgAECn8sAAIEAAkJABCdIwCtAQAEAAkJABCdIwCtAQAAAA==.Rotgutwiskey:BAAALgAECgIJAgAAAA==.Roxies:BAAALgAFFAEJAQAAAA==.Royan:BAAALgAECgcJDQAAAA==.',
Rp='Rpg:BAAALgAECgcJDgAAAA==.',
Ru='Rumie:BAABLgAECn8bAAIMAAYJeQ6eegA4AQAMAAYJeQ6eegA4AQAAAA==.Runty:BAAALgADCgMJAwAAAA==.',
Sa='Sacket:BAAALgAECgcJCgAAAA==.Sadnhornless:BAAALgAECgEJAwAAAA==.Saeti:BAACLgAFFH8TAAMDAAQJzxzICQARAQADAAMJRB7ICQARAQAEAAEJbxiRSQBMAAAuAAQKfz4ABQMACQlIIZYHAG8CAAMACQlAIZYHAG8CAAQABgmdGzArAHwBAAUABAk2HlIrAAQBAB0ABAkUFoiIAKYAAAAA.Sandril:BAAALgAECgcJDAAAAA==.Sapplesauce:BAABLgAECn8XAAIPAAgJ5Bc8HgCkAQAPAAgJ5Bc8HgCkAQAAAA==.',
Sc='Scryer:BAAALgAECgEJAQAAAA==.',
Se='Serenìty:BAAALgAECggJDQAAAA==.Seresin:BAACLgAFFH8IAAMdAAMJRgdsUQB9AAAdAAMJRgdsUQB9AAAEAAEJ4wYrUQA0AAAuAAQKf1UAAx0ACQkgH/ALAAEDAB0ACQkgH/ALAAEDAAQABgmbE5I4ADEBAAAA.',
Sh='Shadý:BAABLgAECn8vAAIIAAkJ5AoUVgCiAQAIAAkJ5AoUVgCiAQAAAA==.Shamanoodles:BAAALgAECgEJAQABLgAECgkJKgAOAOgkAA==.Shinbin:BAAALgAECgEJAgAAAA==.Shonna:BAABLgAECn8oAAQRAAgJLBqNCwCIAQAGAAgJ1hcIRADPAQARAAcJeBiNCwCIAQAeAAIJERlTLQBEAAAAAA==.Shortwarrior:BAABLgAECn9AAAISAAkJohxfDgCMAgASAAkJohxfDgCMAgAAAA==.Shrimpimp:BAAALgAECgQJBAAAAA==.',
Si='Sianu:BAAALgAECgcJBwABLgAECgkJUwAdAAkSAA==.Sidarya:BAABLgAECn8WAAMNAAgJZRcBGgD7AQANAAgJZRcBGgD7AQAbAAIJZgeJBwAuAAAAAA==.Sidera:BAAALgAECggJDgAAAA==.Siduna:BAAALgADCgEJAQAAAA==.Silent:BAACLgAFFH8SAAMSAAQJVhwIFgBeAQASAAQJVhwIFgBeAQAVAAEJPAxjQgBDAAAuAAQKfx4AAxUACQmjFs4ZACUBABIABwlxFW1EADQBABUABgkoEs4ZACUBAAAA.Silverserket:BAAALgAECgIJBAAAAA==.Silverserqet:BAABLgAECn8UAAIIAAcJswpNhAA2AQAIAAcJswpNhAA2AQAAAA==.',
Sk='Skinnybutt:BAAALgADCgkJEQAAAA==.Skippinskipp:BAAALgAECgcJCwAAAA==.Skymaggedon:BAEBLgAECn9QAAMCAAkJVBP/AACxAQACAAkJVBP/AACxAQAHAAgJQAiZSgAKAQAAAA==.',
Sl='Slappadrago:BAAALgAECgkJEwAAAA==.Slipknaught:BAAALgAECgQJAwABLgAECgkJIQAYAIQSAA==.',
Sm='Smileyriley:BAABLgAECn8aAAIEAAcJzQXXTwDOAAAEAAcJzQXXTwDOAAAAAA==.',
Sn='Sneakylinks:BAAALgAECgMJBQABLgAECgcJDgABAAAAAA==.Snotlocker:BAAALgAECgEJAQAAAA==.',
So='Sodexorod:BAAALgADCgYJBwAAAA==.Sofiophya:BAABLgAECn8XAAIYAAUJCwRulQBtAAAYAAUJCwRulQBtAAAAAA==.Sooki:BAAALgAECgIJAwAAAA==.Sorilea:BAAALgADCgcJCAAAAA==.Sorlis:BAAALgAECgcJEwAAAA==.Soulber:BAABLgAECn8XAAMOAAgJ1BThWAC7AQAOAAgJ2RPhWAC7AQAfAAIJnxxTPACgAAAAAA==.Sourdew:BAABLgAECn8eAAIXAAcJtB7YGQDiAQAXAAcJtB7YGQDiAQAAAA==.',
Sp='Sparkey:BAAALgAECgIJAgAAAA==.Spiritair:BAABLgAECn8YAAMjAAkJrBwjBADzAgAjAAkJrBwjBADzAgAWAAEJAABALwAAAAAAAA==.Spunklestain:BAAALgADCggJDQABLgAECgkJEwABAAAAAA==.Spyke:BAAALgADCgEJAQAAAA==.Spykids:BAAALgAECgQJBAAAAA==.',
Sr='Srix:BAAALgAECgEJAQAAAA==.',
St='Starrdust:BAEALgAECgUJCwAAAA==.Stelle:BAABLgAECn8XAAIhAAgJBBEYJABzAQAhAAgJBBEYJABzAQAAAA==.Sternhoof:BAAALgAECgIJAgAAAA==.Stylos:BAABLgAECn9BAAImAAgJPBclDADwAQAmAAgJPBclDADwAQAAAA==.Stãrburst:BAABLgAECn8UAAMCAAgJZQrwewDsAAACAAcJswfwewDsAAAHAAEJUASovwAeAAAAAA==.',
Su='Subrinea:BAAALgAECgUJBQABLgAECgkJPgAcAHkiAA==.',
Sy='Sylven:BAAALgADCgYJBgABLgAECgkJLAAGAL8jAA==.',
Ta='Taissa:BAAALgADCggJCgAAAA==.Taopaípai:BAAALgADCgMJBgAAAA==.Tas:BAAALgAECgQJBAAAAA==.Tatertotz:BAAALgAECgcJEgAAAA==.',
Te='Technine:BAAALgADCgMJAwAAAA==.Techno:BAAALgAECgcJAQAAAA==.Tegbless:BAAALgAECgkJDgAAAA==.Tegchill:BAABLgAECn8dAAQfAAgJNBm8EwDXAQAfAAgJVBi8EwDXAQAOAAgJBQ8oZwDAAQAaAAEJAACfGgAeAAABLgAECgkJDgABAAAAAA==.Tegmage:BAAALgAECgUJBQABLgAECgkJDgABAAAAAA==.Terentia:BAEALgAECgUJBQABLgAECgkJKwAWACQXAA==.',
Th='Thadind:BAAALgAECgQJBAAAAA==.Thalodrim:BAAALgAECgEJAQABLgAECgkJHgAGAOEdAA==.Tharelly:BAABLgAECn8XAAIJAAkJrxi8OwArAgAJAAkJrxi8OwArAgAAAA==.Thasserian:BAAALgADCgIJAgABLgAECgkJLAAGAL8jAA==.Theholymatt:BAACLgAFFH8VAAMTAAYJihZJFgB2AQATAAUJAxRJFgB2AQAUAAQJzRmqBwDAAAAuAAQKfz0AAxQACQkoJEYIACkDABQACQkoJEYIACkDABMABwnnJEEPAJsCAAAA.Thendari:BAABLgAECn90AAIRAAkJ2hgfAAAeAgARAAkJ2hgfAAAeAgAAAA==.Theodus:BAABLgAECn81AAIJAAkJhxlLOAA3AgAJAAkJhxlLOAA3AgAAAA==.Therayen:BAAALgADCgQJBAAAAA==.Theràpy:BAAALgAECgQJBQAAAA==.Thesmaugmatt:BAABLgAECn8UAAIkAAgJfxosHAD0AQAkAAgJfxosHAD0AQABLgAFFAYJFQATAIoWAA==.Thorrune:BAAALgAECgQJBAAAAA==.Threnor:BAABLgAECn9AAAMVAAkJgSQbAADxAgAVAAkJ/SMbAADxAgASAAcJZCP1IABLAgAAAA==.Thunderblade:BAAALgADCgIJAgAAAA==.',
Ti='Tialdari:BAAALgADCgYJBgAAAA==.Tiferis:BAACLgAFFH8SAAITAAUJwBrmEQClAQATAAUJwBrmEQClAQAuAAQKfz0AAhMACQn3IDkFAEADABMACQn3IDkFAEADAAAA.Tislam:BAABLgAECn8XAAIGAAgJ3A2zaABrAQAGAAgJ3A2zaABrAQAAAA==.Tizzeia:BAAALgADCgMJBQAAAA==.',
To='Toaster:BAABLgAECn8pAAQVAAkJNR7NBACaAgAVAAkJFhrNBACaAgAZAAcJpSCaDwDuAQASAAYJtx9dMgDiAQAAAA==.Tobes:BAAALgADCgEJAQAAAA==.Tobiquer:BAABLgAECn9IAAINAAkJ9xs1AACDAgANAAkJ9xs1AACDAgAAAA==.Toebackkey:BAAALgAECgEJAQAAAA==.Tojarmar:BAABLgAECn8XAAIZAAkJJBMJFACvAQAZAAkJJBMJFACvAQABLgAECgQJBAABAAAAAA==.Torolf:BAAALgAECgMJAwAAAA==.',
Tr='Trauglodyte:BAAALgAECgYJBgAAAA==.Traydra:BAAALgAECgMJBAAAAA==.Triven:BAAALgAECgIJAgAAAA==.Troglodyte:BAACLgAFFH8gAAMHAAgJ5BR0CAAsAgAHAAgJ5BR0CAAsAgACAAEJYAz8eQBLAAAuAAQKf0gAAgcACQnMIswEABQDAAcACQnMIswEABQDAAAA.',
Ts='Tsonokwabain:BAABLgAECn8mAAQaAAkJhyKlAQAYAwAaAAkJhyKlAQAYAwAfAAEJah2LVABIAAAOAAEJmALApgEYAAAAAA==.Tsunami:BAAALgADCgYJCAAAAA==.',
Tw='Twistdog:BAAALgAECgEJAwAAAA==.',
Ty='Tyranastrasz:BAABLgAECn80AAMjAAkJIxKADgDmAQAjAAkJIxKADgDmAQAWAAEJ6gYPKQAqAAAAAA==.Tyye:BAAALgAECgEJAQAAAA==.',
['Tâ']='Tâjik:BAABLgAECn8kAAIPAAkJ4QXRKABRAQAPAAkJ4QXRKABRAQAAAA==.',
Ud='Udderlytasty:BAAALgAECgEJAQAAAA==.',
Un='Unc:BAAALgAECgcJCAAAAA==.',
Va='Vade:BAAALgAFFAEJAwAAAA==.Vaelith:BAAALgAECggJDAAAAA==.Vaelyra:BAABLgAECn8uAAIMAAgJOxgJTgCcAQAMAAgJOxgJTgCcAQAAAA==.Vaerryn:BAABLgAECn8mAAQaAAgJMyN/BgA8AgAaAAcJFiN/BgA8AgAOAAMJcBvx0gDkAAAfAAIJQyCCUQBPAAAAAA==.Vaethund:BAAALgAECggJEQAAAA==.Vailenya:BAAALgADCgEJAQABLgAECggJHAALAFMfAA==.Valgavoth:BAAALgAECggJEwAAAA==.Vandrin:BAAALgADCgQJBgAAAA==.Vapir:BAAALgAECgMJAwAAAA==.Variala:BAABLgAECn8XAAMlAAgJig00KABeAQAlAAcJxQw0KABeAQAIAAcJPQsn1ACjAAAAAA==.Vassyra:BAEBLgAECn8rAAIWAAkJJBdOBQAOAgAWAAkJJBdOBQAOAgAAAA==.',
Ve='Velara:BAAALgAECgcJCAAAAA==.Velesyn:BAABLgAECn8cAAMLAAgJUx9TBwAOAgALAAcJKCBTBwAOAgAMAAIJtxH4/QBOAAAAAA==.Vellayna:BAAALgADCgYJBgAAAA==.Venekor:BAAALgADCgUJBQAAAA==.',
Vi='Vilga:BAAALgADCgkJCQAAAA==.Viral:BAAALgAECgYJDwAAAA==.Viriex:BAAALgADCgEJAQAAAA==.Visone:BAAALgADCgEJAQAAAA==.Vitoria:BAAALgAECgEJAQAAAA==.',
Vo='Vocivus:BAAALgAECggJEwAAAA==.Voidlighter:BAACLgAFFH8HAAIhAAMJYhMMMgDGAAAhAAMJYhMMMgDGAAAuAAQKfygAAyEACQlbGWgMAKcCACEACQlbGWgMAKcCABsACAnVFwYaAPUBAAAA.Volundr:BAABLgAECn9AAAIZAAkJ7xgQDgAKAgAZAAkJ7xgQDgAKAgAAAA==.Vonvaughan:BAAALgADCgcJCwABLgAECggJFwAXAOMhAA==.',
Vy='Vynel:BAAALgAECgUJBwABLgAECgkJLAAGAL8jAA==.Vynirion:BAABLgAECn8UAAIJAAcJqxJUpACPAQAJAAcJqxJUpACPAQAAAA==.Vynisa:BAAALgAECgMJAwAAAA==.',
Wa='Waiseheil:BAAALgADCggJCQAAAA==.Warcreaper:BAABLgAECn8cAAIPAAkJFgYtJABzAQAPAAkJFgYtJABzAQAAAA==.Wardellmo:BAAALgAECgEJAQAAAA==.Wargtar:BAABLgAECn81AAIPAAcJdyH5DQBIAgAPAAcJdyH5DQBIAgAAAA==.Warlockbob:BAAALgAECgYJCwAAAA==.',
We='Weabe:BAABLgAECn8YAAMNAAcJFhGFNgAmAQANAAcJ9w+FNgAmAQAhAAIJpRHjSgBqAAAAAA==.Weebes:BAAALgAECggJDwAAAA==.',
Wh='Whatcow:BAAALgAECgEJAQAAAA==.Whiterrina:BAAALgADCgkJCgAAAA==.',
Wi='Window:BAAALgAECgEJAQAAAA==.',
Wo='Woobee:BAAALgADCgEJAQAAAA==.',
Wy='Wyrdhoof:BAABLgAECn8iAAMEAAkJ9AjdMgBPAQAEAAkJ9AjdMgBPAQAdAAUJEgfPiwCfAAAAAA==.',
['Wù']='Wùsthof:BAABLgAECn8eAAIIAAkJywobVgBmAQAIAAkJywobVgBmAQAAAA==.',
Xa='Xandrios:BAAALgADCgMJAwAAAA==.Xaron:BAAALgADCgMJAwAAAA==.',
Xi='Xiae:BAABLgAECn83AAMCAAkJFCMoDQDuAgACAAkJFCMoDQDuAgAHAAcJyRibKACqAQAAAA==.',
Xk='Xkwizet:BAABLgAECn8aAAIJAAgJPgcooQA5AQAJAAgJPgcooQA5AQAAAA==.',
Xo='Xorrin:BAAALgAECgYJDgAAAA==.',
Xy='Xylpho:BAAALgAECgEJAQAAAA==.',
Ye='Yet:BAABLgAECn8xAAIUAAkJ2iRSBQBKAwAUAAkJ2iRSBQBKAwAAAA==.',
Yi='Yiffweaver:BAABLgAECn80AAIgAAkJKAx3AACZAQAgAAkJKAx3AACZAQAAAA==.',
Yo='Yokoriazen:BAABLgAECn80AAIiAAkJfhNXEAC/AQAiAAkJfhNXEAC/AQAAAA==.',
Yu='Yurtnaut:BAAALgAECgYJDgAAAA==.',
Yv='Yvesass:BAABLgAECn8ZAAIEAAkJ5AYGAwCHAAAEAAkJ5AYGAwCHAAAAAA==.',
Za='Zarhianna:BAABLgAECn8jAAIEAAkJgBBCIgC3AQAEAAkJgBBCIgC3AQAAAA==.',
Ze='Zeo:BAAALgAECgEJAQAAAA==.Zephnor:BAAALgAECgEJAQAAAA==.',
Zm='Zmona:BAABLgAECn8xAAIUAAkJHg+cZwCgAQAUAAkJHg+cZwCgAQAAAA==.',
Zo='Zorsche:BAAALgADCgcJEQAAAA==.',
Zu='Zulrok:BAABLgAECn8tAAISAAkJbB3vEgBbAgASAAkJbB3vEgBbAgAAAA==.',
['Åv']='Åviendha:BAAALgADCgcJCAAAAA==.',
['Ðr']='Ðre:BAABLgAECn8VAAIJAAcJ0hZswwBfAQAJAAcJ0hZswwBfAQAAAA==.',
['Ût']='Ûther:BAABLgAECn8VAAIUAAYJ6wNXDgGnAAAUAAYJ6wNXDgGnAAAAAA==.',
['Ül']='Ültimecia:BAABLgAECn8uAAIJAAkJUiPrFADcAgAJAAkJUiPrFADcAgAAAA==.',
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
