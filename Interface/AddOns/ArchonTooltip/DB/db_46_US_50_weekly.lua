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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Priest-Holy','Shaman-Restoration','Warrior-Arms','DeathKnight-Unholy','Priest-Shadow','Priest-Discipline','Druid-Guardian','Druid-Restoration','Monk-Mistweaver','Shaman-Elemental','Druid-Feral','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Mage-Arcane','Evoker-Devastation','Warlock-Demonology','Warrior-Protection','DemonHunter-Havoc','Evoker-Augmentation','Warrior-Fury','Warlock-Affliction','Druid-Balance','DeathKnight-Frost','Paladin-Holy','Rogue-Subtlety','Shaman-Enhancement','DeathKnight-Blood','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn84AAMBAAgJMCYLAgABAwABAAgJMCYLAgABAwACAAEJAABJggA/AAAAAA==.',
Ad='Adianitefall:BAAALgADCgkJEQAAAA==.Adorian:BAAALgAECgYJEAAAAA==.Adros:BAABLgAECn8oAAMDAAgJQRQMFQB+AQADAAgJQRQMFQB+AQAEAAEJDwR4WAEYAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAYJGgAFAKgYAA==.Adrrelle:BAACLgAFFH8aAAMFAAYJqBiyFQBUAQAFAAUJyhiyFQBUAQACAAYJaw1hDQARAQAuAAQKfyQABAIACQncHXcTAJkCAAIACAmXH3cTAJkCAAEABAnaFwMsAOsAAAUAAwmpEW64AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIEAAgJxgeTrwAkAQAEAAgJxgeTrwAkAQAAAA==.',
Ai='Ailaith:BAABLgAECn81AAIFAAkJ/R9ECwC4AgAFAAkJ/R9ECwC4AgAAAA==.',
Ak='Akariliselle:BAABLgAECn8UAAIGAAcJMBp2BgCmAQAGAAcJMBp2BgCmAQAAAA==.Akarue:BAAALgAECgQJBAAAAA==.Aknologia:BAAALgAECgUJCAAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgQJBwAAAA==.Alarielle:BAAALgADCggJDgAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAHAMIgAA==.Alydrostage:BAABLgAECn8bAAIIAAYJyQXWsQDiAAAIAAYJyQXWsQDiAAAAAA==.Alystriaz:BAABLgAECn8fAAIJAAgJUxioBwA2AgAJAAgJUxioBwA2AgAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn8yAAIKAAkJDhGyFgDQAQAKAAkJDhGyFgDQAQAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Andaya:BAACLgAFFH8GAAILAAMJQh9pHwAPAQALAAMJQh9pHwAPAQAuAAQKfyEAAgsACQmrGeknAMcBAAsACQmrGeknAMcBAAAA.Andemeli:BAAALgAECgUJBQABLgAECgYJFAAMAE0GAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAHAMIgAA==.Aninja:BAEALgADCgQJBAABLgAFFAQJDQANADEaAA==.Anivia:BAABLgAECn8WAAIIAAgJrREneQDfAQAIAAgJrREneQDfAQAAAA==.Ankoubailith:BAAALgAECgMJBAAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAABLgAECn8WAAMOAAYJsQj4NQDpAAAOAAYJsQj4NQDpAAAPAAIJ2QeWTgBKAAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8lAAMQAAgJgByyBgAwAgAQAAgJgByyBgAwAgARAAEJQRGIqwAyAAAAAA==.Arctica:BAAALgAECgUJDwAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8hAAIIAAgJkA8IXACJAQAIAAgJkA8IXACJAQAAAA==.Arjurn:BAABLgAECn84AAIIAAgJvSAiFwCWAgAIAAgJvSAiFwCWAgAAAA==.Arkro:BAAALgADCgYJBgAAAA==.Armpitbutter:BAABLgAECn84AAISAAgJMCWdAwA2AwASAAgJMCWdAwA2AwAAAA==.Artymiss:BAAALgAECgYJBwAAAA==.',
As='Ashireita:BAAALgAECgYJEAABLgAECgcJGwATACoPAA==.Astraleth:BAAALgAECgYJDQAAAA==.',
At='Atama:BAAALgAECgMJAwAAAA==.Atharius:BAAALgADCgEJAQAAAA==.',
Au='Authority:BAAALgAECgMJAwAAAA==.Autry:BAABLgAECn8nAAMUAAgJ4w7rDQB2AQAUAAgJ4w7rDQB2AQARAAcJ2QolTAAWAQAAAA==.',
Av='Avelina:BAAALgADCgcJDgAAAA==.Avocat:BAABLgAECn8XAAIFAAcJdhNESABvAQAFAAcJdhNESABvAQAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAYJGQAQAIEeAA==.Azshura:BAAALgADCgYJBgAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgAVAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8jAAIEAAgJ6w/9VQB/AQAEAAgJ6w/9VQB/AQAAAA==.Balgar:BAABLgAECn8YAAMFAAgJBSMAEQCBAgAFAAgJBSMAEQCBAgACAAUJyxm3PgBgAQAAAA==.Balghas:BAABLgAECn8kAAIEAAgJ1hzQMwBTAgAEAAgJ1hzQMwBTAgAAAA==.Bamz:BAAALgAECgcJBwABLgAFFAQJDAAKAH8KAA==.Bamzhurt:BAAALgAECgUJBQABLgAFFAQJDAAKAH8KAA==.Baumstrum:BAAALgAECgQJBwAAAA==.',
Be='Beezlbubba:BAAALgAECgQJBAAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn80AAIUAAgJkBPHCgCxAQAUAAgJkBPHCgCxAQAAAA==.',
Bi='Bint:BAAALgADCgYJBgAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8fAAIFAAgJExvzJgD0AQAFAAgJExvzJgD0AQAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgYJCgAVAAAAAA==.Boomparapara:BAABLgAECn8XAAIIAAcJnBzJQwDOAQAIAAcJnBzJQwDOAQAAAA==.Borrkbuster:BAAALgADCggJFgAAAA==.Bosta:BAAALgADCgQJBQAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgYJFgAKAEUjAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAAALgAECggJEAAAAA==.Brew:BAABLgAECn8dAAMWAAYJQSCoFQDAAQAWAAYJQSCoFQDAAQAXAAEJ0Q0LfQAzAAAAAA==.Brkat:BAAALgADCgYJBgAAAA==.Brughe:BAABLgAECn8nAAIFAAkJvwlzTQBfAQAFAAkJvwlzTQBfAQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgAAAA==.Buttacutta:BAAALgADCgkJEgAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8QAAIOAAYJqhn+BACzAQAOAAYJqhn+BACzAQAuAAQKfx0AAg4ACQm9HfcLAMMCAA4ACQm9HfcLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAABLgAECn8cAAIRAAgJ5R5KDgClAgARAAgJ5R5KDgClAgABLgADCgYJBgAVAAAAAA==.Catty:BAABLgAECn8kAAIUAAkJWhZFBgAmAgAUAAkJWhZFBgAmAgAAAA==.',
Ce='Celestyl:BAABLgAECn8mAAIYAAgJFQuPBABmAQAYAAgJFQuPBABmAQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECggJIAAZAJAaAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAAALgAECgcJEwAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAAALgAECgYJEAAAAA==.Chillybovine:BAABLgAECn8WAAIIAAYJ8QhrogD9AAAIAAYJ8QhrogD9AAAAAA==.Chromstrasza:BAABLgAECn8ZAAIZAAcJIRh3BgCdAQAZAAcJIRh3BgCdAQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Ci='Cirice:BAAALgAECgEJAQAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAcJGwAaACQbAA==.',
Co='Conjarr:BAABLgAECn8lAAIKAAkJ/hp/GAC/AQAKAAkJ/hp/GAC/AQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougarsixsix:BAAALgAECgYJEAAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8ZAAIbAAgJ3iP7AwCsAgAbAAgJ3iP7AwCsAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8wAAINAAkJyxbWKQASAgANAAkJyxbWKQASAgAAAA==.Crystalliney:BAAALgADCgYJBgAAAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8bAAIDAAgJ0xWiDACjAQADAAgJ0xWiDACjAQAAAA==.Dalind:BAAALgAECgYJEAAAAA==.Dalshiro:BAAALgAECgYJCQAAAA==.Damaclies:BAABLgAECn8mAAMaAAkJ4xKdPwCfAQAaAAcJAhKdPwCfAQAGAAUJThSdMgDtAAAAAA==.Damedolla:BAABLgAECn8fAAMHAAgJYAw2XgAcAQAHAAgJwQo2XgAcAQAcAAUJnw7EQAD3AAAAAA==.Dammerung:BAAALgAECgYJCAAAAA==.Darksyn:BAABLgAECn8VAAIGAAYJlQtcEgDYAAAGAAYJlQtcEgDYAAAAAA==.Darthbane:BAAALgAECgYJCwAAAA==.Darude:BAAALgADCgcJEAAAAA==.',
De='Deadstout:BAAALgAECgQJBAAAAA==.Deepspace:BAABLgAECn8XAAIcAAgJESbHAgDyAgAcAAgJESbHAgDyAgAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgADCgkJEgAAAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8YAAIdAAcJqBc8JACbAQAdAAcJqBc8JACbAQAAAA==.Desdia:BAAALgAECgUJBQAAAA==.',
Di='Dia:BAAALgAECgMJAwAAAA==.Diabetes:BAABLgAFFH8RAAISAAUJfRtnDACVAQASAAUJfRtnDACVAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Diend:BAABLgAECn83AAILAAkJJx9yBgABAwALAAkJJx9yBgABAwAAAA==.Dill:BAAALgADCgcJCgABLgAECggJOAABADAmAA==.Dillathis:BAAALgADCgEJAQAAAA==.Dissonanita:BAAALgAECgMJAwAAAA==.',
Dj='Djthelock:BAABLgAECn8cAAMaAAgJ4hOvWwBNAQAaAAYJdhCvWwBNAQAGAAMJGxxhGgCYAAAAAA==.',
Do='Dormoon:BAABLgAECn8YAAMeAAYJoA9GQQDtAAAeAAYJoA9GQQDtAAAbAAEJqAQSSAAeAAAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgQJCwAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8WAAMKAAYJRSNkDgA2AgAKAAYJRSNkDgA2AgAOAAMJDhCRUABlAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8lAAIUAAgJcBkpBwAKAgAUAAgJcBkpBwAKAgAAAA==.Drunkenpo:BAABLgAECn83AAIWAAkJUCCxBADGAgAWAAkJUCCxBADGAgAAAA==.Drïzl:BAEALgAECgMJAwABLgAFFAQJDQANADEaAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8WAAIHAAgJOwlmbwDxAAAHAAgJOwlmbwDxAAAAAA==.',
Dw='Dwarfoo:BAAALgAECgYJEAAAAA==.Dweñde:BAABLgAECn8eAAIaAAgJ7gadawAnAQAaAAgJ7gadawAnAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAINAAUJnQxfwgD/AAANAAUJnQxfwgD/AAAAAA==.',
Ed='Eddrick:BAABLgAECn8aAAMEAAgJ0BYVSQCiAQAEAAgJ0BYVSQCiAQADAAIJag0kPgAlAAAAAA==.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgYJCQAAAA==.',
Ei='Eilethen:BAABLgAECn8fAAIfAAgJ7hpcBADyAQAfAAgJ7hpcBADyAQAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAQJCgAfAO8QAA==.Elementoe:BAAALgADCgEJAQABLgADCgIJAgAVAAAAAA==.Elissabethh:BAAALgAECgYJEAAAAA==.Elminstar:BAAALgADCgIJAgAAAA==.',
Em='Employee:BAAALgAECgUJEQAAAA==.',
En='Engo:BAABLgAECn8wAAMKAAkJdiSFAQB2AwAKAAkJdCOFAQB2AwAPAAMJ7ROxOQC9AAAAAA==.',
Er='Eradrá:BAACLgAFFH8KAAMfAAQJ7xDtBgCMAAAaAAQJBg6vOAAdAQAfAAIJEQrtBgCMAAAuAAQKf0cAAx8ACQlsHOgAAA4DAB8ACQmsG+gAAA4DABoACAmPFcwwANYBAAAA.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAECggJLAARAHkZAA==.Ersèlla:BAABLgAECn8sAAMRAAgJeRlWGwAjAgARAAgJeRlWGwAjAgAgAAEJ2AWScgAlAAAAAA==.Erysira:BAAALgADCgkJCQAAAA==.',
Et='Ethan:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAABLgAECn8VAAMDAAgJURxuDACnAQADAAcJ2RluDACnAQAEAAYJVhpEWwByAQAAAA==.',
Ev='Evandra:BAABLgAECn8bAAILAAgJdhokFwA8AgALAAgJdhokFwA8AgAAAA==.Evanorah:BAAALgAECgYJEwAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAQJDQANADEaAA==.',
Fa='Faelithia:BAABLgAECn8VAAIKAAYJKA7hLQAUAQAKAAYJKA7hLQAUAQAAAA==.Fatalbrew:BAAALgAECgQJBwAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECggJIAAZAJAaAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Ferheim:BAAALgAECgEJAQAAAA==.Ferrovax:BAAALgADCgYJBgABLgAECgYJEQAVAAAAAA==.',
Fi='Fiddyone:BAABLgAECn8oAAMhAAkJph86AgCIAgAhAAkJ0h06AgCIAgANAAgJcB3GKgAOAgAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIiAAcJpBwHHgAmAgAiAAcJpBwHHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgQJBAAAAA==.',
Fo='Fodurzin:BAAALgAECgQJDAAAAA==.Fonta:BAAALgADCgUJBwAAAA==.Fortuna:BAAALgADCgYJBgABLgAECgYJCgAVAAAAAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8wAAIhAAgJbx56AwA9AgAhAAgJbx56AwA9AgAAAA==.Frosten:BAAALgADCgkJLQAAAA==.',
Fu='Furenio:BAABLgAECn8pAAIQAAkJfBamCQDlAQAQAAkJfBamCQDlAQAAAA==.',
Fy='Fyyre:BAAALgAECgMJBAAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8JAAIEAAQJHhi8FgBiAQAEAAQJHhi8FgBiAQAuAAQKfyoAAgQACAkqIQsZAG0CAAQACAkqIQsZAG0CAAAA.Gaff:BAAALgAECgYJDgAAAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgUJCAAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgUJCQAAAA==.Grido:BAAALgADCgkJEQAAAA==.Grimbrindral:BAABLgAECn8hAAMEAAcJ5hZDZAC5AQAEAAcJdBVDZAC5AQADAAUJghrKFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAEAOYWAA==.Gruzaxx:BAAALgADCgUJBQAAAA==.',
Gu='Gulishdaniel:BAAALgAFFAMJAwABLgAFFAYJEAAOAKoZAA==.',
Ha='Hadin:BAABLgAECn81AAMIAAkJcSFgCQADAwAIAAkJcSFgCQADAwAYAAMJqhysDwDHAAAAAA==.Hakeko:BAAALgAECgUJBgAAAA==.Halalnt:BAAALgAECgMJAwABLgAFFAIJBQAdAOkaAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn8wAAMQAAkJZBefCAD9AQAQAAkJZBefCAD9AQAUAAEJDhQuLwA+AAAAAA==.Hazenpryde:BAAALgAECgYJEgAAAA==.',
He='Hearsay:BAABLgAECn8dAAMEAAcJcAnHhwAUAQAEAAcJcAnHhwAUAQAiAAIJ6wPFZgBJAAABLgAECggJDQAVAAAAAA==.Hephaistian:BAAALgADCgkJGgAAAA==.Hespera:BAABLgAECn8hAAMRAAkJySDpGABwAgARAAgJoiHpGABwAgAgAAMJkBSMOwDKAAAAAA==.',
Hi='Hirari:BAABLgAECn8cAAMiAAYJ2iTzDwBRAgAiAAYJ2iTzDwBRAgAEAAEJFBpKEwFHAAAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8bAAIOAAYJxQTXPQDCAAAOAAYJxQTXPQDCAAAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMaAAgJURdQSQDuAQAaAAgJURdQSQDuAQAGAAEJAAB4QAAAAAAAAA==.Husbando:BAAALgADCggJCgAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAAALgAECgcJEgAAAA==.Hydrá:BAABLgAECn8ZAAIaAAgJUxicKgDxAQAaAAgJUxicKgDxAQAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwABLgAECgYJCwAVAAAAAA==.',
Ic='Iceamaris:BAABLgAECn8aAAITAAgJDQwkLQA1AQATAAgJDQwkLQA1AQAAAA==.Icetiger:BAAALgADCgIJAgAAAA==.',
Ie='Iechu:BAAALgAECggJDQAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgYJCQAVAAAAAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAACLgAFFH8OAAIRAAYJqQtBDgCWAQARAAYJqQtBDgCWAQAuAAQKfxUAAxEABgk/GwQtAKsBABEABgk/GwQtAKsBACAAAgnRBwxuACoAAAEuAAUUBgkYAAkApRcA.',
Ja='Jaod:BAAALgADCgkJEQAAAA==.',
Jd='Jdghoul:BAAALgAECggJDAAAAA==.',
Ji='Jindrac:BAAALgAECgIJAgAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJJQAHAIshAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECgcJBwAAAA==.Kaltharion:BAAALgAECgUJCQAAAA==.Kaluren:BAAALgAECgcJCwAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn8yAAQaAAkJ7RcJIQAiAgAaAAgJ7RcJIQAiAgAfAAUJZwyHFACxAAAGAAMJYwUKTACJAAAAAA==.Kantong:BAABLgAECn8gAAIXAAgJdBmVEQDnAQAXAAgJdBmVEQDnAQAAAA==.Kapp:BAAALgAECgQJBQAAAA==.Karabar:BAABLgAECn84AAMEAAgJ3CAaGABzAgAEAAgJoyAaGABzAgADAAgJSx6hBQBIAgAAAA==.Kasarra:BAABLgAECn8cAAIcAAgJeBHsFACBAQAcAAgJeBHsFACBAQAAAA==.Kazagol:BAABLgAECn84AAIHAAgJ8h+VGABBAgAHAAgJ8h+VGABBAgAAAA==.',
Kh='Khamaracy:BAAALgAECgUJDwAAAA==.Khronni:BAAALgAECgYJBwAAAA==.Khrooze:BAAALgAECgQJDAAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAAALgAECgYJEAAAAA==.Kittei:BAABLgAECn84AAIQAAgJ4RBpEwBIAQAQAAgJ4RBpEwBIAQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECgIJAgAAAA==.',
Ku='Kurick:BAAALgAECgYJCwAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8cAAIIAAgJCRmsOgDtAQAIAAgJCRmsOgDtAQABLgAFFAIJBQAdAOkaAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Latte:BAAALgAECgQJBAAAAA==.',
Le='Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn8fAAIjAAYJYxU4IAA1AQAjAAYJYxU4IAA1AQAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lightsmite:BAAALgAECgIJAgAAAA==.Lilithene:BAAALgAECgUJBQABLgAECgcJGwATACoPAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.',
Lo='Lokinah:BAABLgAECn8VAAIFAAYJ6ARLjQC8AAAFAAYJ6ARLjQC8AAAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAAALgAECgYJEwAAAA==.Lukeduke:BAABLgAFFH8MAAIbAAYJHRyiBACWAQAbAAYJHRyiBACWAQABLgAFFAYJGQAQAIEeAA==.Luketheduke:BAACLgAFFH8ZAAMQAAYJgR5LAQDaAQAQAAUJgR5LAQDaAQAUAAEJAAAIBwA3AAAuAAQKfyoAAxAACQkvJR8BAFcDABAACQkvJR8BAFcDABQABAmxFXscAAkBAAAA.Lumilia:BAAALgADCgUJBQAAAA==.Lunä:BAABLgAECn8ZAAILAAgJ1BVqIgAQAgALAAgJ1BVqIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8oAAIIAAkJWBlfIgBWAgAIAAkJWBlfIgBWAgAAAA==.Lynnee:BAAALgADCgEJAQAAAA==.',
['Lô']='Lôckrocks:BAAALgAECgcJDAAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Maewix:BAAALgAECgEJAQAAAA==.Magictomb:BAABLgAECn8tAAQTAAgJlxUsJQBoAQATAAgJlxUsJQBoAQALAAYJ6Q0qWADsAAAkAAQJ3Qf9GQCvAAABLgAFFAIJAgAVAAAAAA==.Mahdude:BAAALgADCgEJAQAAAA==.Malcontent:BAAALgAECgQJBQABLgAECgYJDgAVAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECgYJDgAVAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAAALgAECgYJCgABLgAECgYJDgAVAAAAAA==.Maliss:BAABLgAECn81AAQBAAkJhhdkDQANAgABAAkJqxZkDQANAgACAAQJtghNYwCzAAAFAAEJoxEO0AA9AAAAAA==.Mallord:BAAALgAECgYJDgAAAA==.Mandarin:BAABLgAECn8fAAIRAAgJnhkCGQA2AgARAAgJnhkCGQA2AgAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAAALgAFFAEJAQAAAA==.Marashades:BAAALgADCgQJBAABLgAECggJGQAbAN4jAA==.',
Mc='Mcbadden:BAAALgAECgYJCAAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwABLgAECgQJDAAVAAAAAA==.Mercia:BAABLgAECn8jAAIDAAgJiBY5DgCHAQADAAgJiBY5DgCHAQAAAA==.Merekoma:BAAALgAECgYJEQAAAA==.',
Mi='Milarra:BAAALgAECgcJDAAAAA==.Milhouse:BAAALgAECgQJBwAAAA==.Minalan:BAAALgADCgYJCgABLgAECgQJDAAVAAAAAA==.Mingonashoba:BAAALgAECgYJEAAAAA==.Miragosa:BAABLgAECn8gAAMJAAgJwwQ/KgAgAQAJAAgJwwQ/KgAgAQAZAAEJ8AGUIAAaAAAAAA==.Misschris:BAABLgAECn8ZAAISAAgJhwgNMwAVAQASAAgJhwgNMwAVAQAAAA==.Mizu:BAAALgADCgcJDgAAAA==.',
Mo='Moadeed:BAAALgAECgYJBwAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgEJAQAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAAALgAECgUJCQAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAAALgAECgYJEgAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nasturtium:BAAALgADCgYJDgAAAA==.Naturestone:BAAALgAFFAIJAgAAAA==.Nausican:BAABLgAECn8nAAIhAAgJ5RXQBgC1AQAhAAgJ5RXQBgC1AQAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAABLgAECn8mAAIEAAgJuRn8LgD8AQAEAAgJuRn8LgD8AQAAAA==.Necrotherys:BAABLgAECn8gAAIHAAgJlBrPIgD/AQAHAAgJlBrPIgD/AQAAAA==.Nelandra:BAAALgAECgYJEAAAAA==.',
Ni='Nicklaus:BAAALgAECgYJEgAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8NAAINAAQJMRqPKgBdAQANAAQJMRqPKgBdAQAuAAQKfy4AAw0ACAkvJXANAMYCAA0ACAkvJXANAMYCACEAAQm4GwUfAEMAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAQJDQAdAE0OAA==.Nomahuata:BAABLgAECn83AAITAAgJqhbMGADJAQATAAgJqhbMGADJAQAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgADCgYJBgAAAA==.',
Ny='Nyeli:BAAALgAECgEJAQABLgAECgYJDQAVAAAAAA==.Nyxi:BAAALgAECgUJCwAAAA==.Nyxlee:BAAALgADCgkJDwAAAA==.',
['Né']='Néo:BAAALgAECgUJCAAAAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8VAAMkAAUJKiN8DQDnAQAkAAUJKiN8DQDnAQALAAIJnSQ6YQDMAAABLgAECgkJKAAhAKYfAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgcJDQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgQJBQAAAA==.Palanas:BAAALgAFFAEJAQAAAA==.Palochka:BAAALgAECgUJBQAAAA==.Paradots:BAABLgAECn8WAAIJAAYJwBrlDQClAQAJAAYJwBrlDQClAQABLgADCgYJBgAVAAAAAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAECgcJFwAIAJwcAA==.',
Pe='Petronella:BAABLgAECn8sAAMMAAkJkAv1FgBIAQAMAAkJkAv1FgBIAQAeAAQJ+wNjgwCxAAAAAA==.Pezmage:BAAALgAECgEJAQAAAA==.',
Ph='Phatboi:BAAALgADCgIJAwAAAA==.',
Pi='Pixystix:BAAALgAECgYJEwAAAA==.',
Po='Poisonspain:BAAALgAECgMJAwAAAA==.Popsdh:BAAALgAECgUJBwABLgAECggJFQADAFEcAA==.Potscold:BAACLgAFFH8NAAIIAAYJWhiGDAC5AQAIAAYJWhiGDAC5AQAuAAQKf0EAAggACAnaJb8NANoCAAgACAnaJb8NANoCAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAIADwdAA==.',
Pr='Prion:BAABLgAECn8YAAIeAAUJexpUNAAoAQAeAAUJexpUNAAoAQAAAA==.',
Pu='Pull:BAABLgAECn8eAAIQAAgJDBxBCAAFAgAQAAgJDBxBCAAFAgAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAAALgAECgYJDQAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Raneyth:BAAALgAECgUJBQAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8ZAAIaAAgJfgOTkgDYAAAaAAgJfgOTkgDYAAAAAA==.Reliala:BAAALgADCgkJEQAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECggJEQAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAAVAAAAAA==.',
Rh='Rhobes:BAAALgADCgkJHQAAAA==.Rhondta:BAABLgAECn8bAAIaAAgJ0g56TQBzAQAaAAgJ0g56TQBzAQAAAA==.',
Ri='Rickormortis:BAAALgAECgYJCAABLgAECggJGQASAIcIAA==.Rictus:BAABLgAECn8qAAIIAAkJwiPaCAAIAwAIAAkJwiPaCAAIAwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8dAAIXAAYJ7xK2KgAVAQAXAAYJ7xK2KgAVAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAAALgAECggJDQAAAA==.Rurry:BAACLgAFFH8YAAIJAAYJpRe+BACuAQAJAAYJpRe+BACuAQAuAAQKfykABAkACQljIrECAEADAAkACQljIrECAEADABkABQm6GR4WAI8BAB0AAwlVF/RGAL8AAAAA.',
Ry='Ryumi:BAABLgAECn8lAAIHAAkJiyFEEQB3AgAHAAkJiyFEEQB3AgAAAA==.Ryur:BAAALgAECgQJDAAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAECgYJDgAVAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECggJGQASAIcIAA==.Sahwe:BAAALgAECgQJBQAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJMQAAAA==.Saphisha:BAAALgAECgYJDgAAAA==.Sasora:BAAALgAECgUJCgAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgADCgkJKwAAAA==.',
Sc='Scaledaddy:BAABLgAECn8aAAIdAAgJTA13JgBXAQAdAAgJTA13JgBXAQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAYJFwANADUaAA==.Scaryl:BAAALgAECgQJBAAAAA==.Scourgespawn:BAACLgAFFH8XAAMNAAYJNRrJEgCqAQANAAUJNRrJEgCqAQAlAAIJpwj2JwA1AAAuAAQKfycAAw0ACQmyIHkgAEICAA0ACQmyIHkgAEICACUABAmIEmAtAJ0AAAAA.',
Se='Selenë:BAAALgAECgQJBAAAAA==.Sengoku:BAAALgADCggJCgAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgADCgcJBwAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8YAAIFAAgJLRjxMQDCAQAFAAgJLRjxMQDCAQAAAA==.Sharivee:BAAALgAECggJDwAAAA==.Sharko:BAABLgAECn8ZAAQDAAgJ1RaSDwDMAQADAAcJzhWSDwDMAQAEAAIJnxI95QB7AAAiAAIJwgOQiwBPAAAAAA==.Shibui:BAABLgAECn8xAAMcAAkJ1BNkDgDbAQAcAAkJ1BNkDgDbAQAHAAcJvAYvowDNAAAAAA==.Shiggles:BAABLgAECn8VAAINAAkJWRkXIgA5AgANAAkJWRkXIgA5AgABLgAFFAIJBQAEAHUVAA==.Shinhaein:BAABLgAECn8UAAIIAAYJ2BT2hgAuAQAIAAYJ2BT2hgAuAQABLgAECggJFQANAA0RAA==.Shockazilla:BAABLgAECn82AAMiAAkJbR5YBAAZAwAiAAkJbR5YBAAZAwAEAAMJVw+z/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAFFAEJAQAAAA==.Silverhorn:BAAALgAECgYJEgAAAA==.',
Sk='Skoduh:BAABLgAECn8aAAIFAAYJjhwPRgB3AQAFAAYJjhwPRgB3AQAAAA==.Skyelene:BAABLgAECn8bAAMTAAcJKg++QwA6AQATAAYJCg++QwA6AQALAAcJsQY+VgDzAAAAAA==.',
Sl='Slaanesh:BAABLgAECn8UAAQGAAYJVBltCgBKAQAGAAYJJhZtCgBKAQAfAAMJlhsqFwDFAAAaAAIJyhBVxQBxAAAAAA==.Sluggo:BAABLgAFFH8FAAIEAAQJHxFxJwAzAQAEAAQJHxFxJwAzAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgR9EwAHAQACAAQJhgR9EwAHAQAuAAQKfyIAAwIACAkLGSEcAEcCAAIACAnYGCEcAEcCAAUABAmEDS6aAJ8AAAAA.',
Sm='Smeagosses:BAAALgADCgcJDAAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgUJBgAAAA==.Solinaara:BAAALgADCgEJAQAAAA==.Soraka:BAABLgAFFH8IAAIPAAMJxAbQIADIAAAPAAMJxAbQIADIAAAAAA==.',
Sp='Spiralist:BAABLgAECn8aAAQgAAgJJhrMJwA1AQAgAAYJcRjMJwA1AQARAAcJvRVBUAAHAQAUAAIJkAxcKQBaAAAAAA==.Spiralmist:BAAALgADCgUJBQAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgcJBwABLgAECgYJEAAVAAAAAA==.Stonedalways:BAAALgAECgUJDAAAAA==.',
Su='Sunfuri:BAABLgAECn82AAIeAAgJmgq3KwBVAQAeAAgJmgq3KwBVAQAAAA==.Sunjan:BAAALgAECgMJAwAAAA==.Sus:BAACLgAFFH8cAAIcAAYJuB0kAQDUAQAcAAYJuB0kAQDUAQAuAAQKfyUAAhwACQmXI5cDAEcDABwACQmXI5cDAEcDAAAA.Susanoo:BAAALgAECgYJEgAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAABLgAECn8aAAIHAAYJOwMppACAAAAHAAYJOwMppACAAAAAAA==.Takeko:BAAALgADCgcJDgABLgAECgUJBgAVAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJEQAAAA==.Taranad:BAAALgAECgcJDAAAAA==.Tarathor:BAAALgAECgYJEAAAAA==.Tasha:BAAALgAECgEJAwABLgAECgUJGAAeAHsaAA==.Tauroctony:BAABLgAECn8eAAIQAAgJKiGhBACiAgAQAAgJKiGhBACiAgAAAA==.',
Te='Tea:BAAALgAECgUJBQABLgAECgkJMgAKAA4RAA==.Teknofarious:BAAALgAECgEJAgAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECgkJNQABAIYXAA==.Thesafe:BAAALgAECgIJAgAAAA==.Thialaa:BAAALgAECgEJAwABLgAECgkJNQAFAP0fAA==.Thialia:BAAALgAECgYJCwABLgAECgkJNQAFAP0fAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn84AAIPAAgJ6yRcAgBfAwAPAAgJ6yRcAgBfAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAQJDQANADEaAA==.',
To='Tobiblindpaw:BAAALgAECgUJCQAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECggJOAASADAlAA==.Torrey:BAABLgAECn8YAAIiAAgJICVuAwA8AwAiAAgJICVuAwA8AwAAAA==.',
Tr='Trema:BAAALgAECgEJAgAAAA==.Trix:BAABLgAECn8vAAILAAgJHw3gPABYAQALAAgJHw3gPABYAQAAAA==.',
Tu='Tulsi:BAABLgAECn8vAAImAAkJXCK+AAAMAwAmAAkJXCK+AAAMAwAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8WAAIEAAYJ2xVPfgAmAQAEAAYJ2xVPfgAmAQAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Valanoth:BAABLgAECn8jAAIHAAgJwiAvEgBwAgAHAAgJwiAvEgBwAgAAAA==.Valdr:BAABLgAECn8bAAMdAAgJcRELIgB4AQAdAAgJcRELIgB4AQAZAAQJowzXKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAHAMIgAA==.Vas:BAAALgADCgYJFwAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgADCgUJBQABLgAECgYJDQAVAAAAAA==.Vevicenth:BAAALgAECgcJBwAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8aAAIIAAUJcx5lCgDMAQAIAAUJcx5lCgDMAQAuAAQKfxsAAwgACQlNIb4hAOwCAAgACQlNIb4hAOwCABgAAgl2FLQTAIoAAAAA.',
Wh='Whakan:BAAALgAECgEJAQABLgAECgYJEwAVAAAAAA==.',
Wo='Wolfos:BAABLgAECn8VAAIQAAgJliOcAgDLAgAQAAgJliOcAgDLAgAAAA==.',
Wt='Wtfox:BAEALgAECgYJDwABLgAECggJIQATAJUWAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAAALgAECgYJCQAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgQJCgABLgAECgUJBgAVAAAAAA==.Xalatos:BAAALgAECgEJAQAAAA==.Xalfein:BAAALgADCgkJGwAAAA==.',
Xi='Xinu:BAAALgADCgYJBgABLgAECgkJNwAFAIcbAA==.',
Ya='Yanakana:BAAALgAECgUJBQAAAA==.',
Yd='Ydalise:BAAALgAECgEJAQAAAA==.Ydrassil:BAAALgAECgYJDgABLgAECggJFQADAFEcAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJBwAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8iAAMFAAgJsxVnNAC4AQAFAAgJsxVnNAC4AQACAAMJqwf0KABHAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAABLgAECn8VAAIgAAcJzAagNgDgAAAgAAcJzAagNgDgAAAAAA==.Zeusinator:BAABLgAECn8gAAIFAAcJsxcCOwCeAQAFAAcJsxcCOwCeAQAAAA==.',
Zi='Zinu:BAABLgAECn83AAIFAAkJhxsiFQBgAgAFAAkJhxsiFQBgAgAAAA==.Zivalisse:BAAALgAECgQJBAAAAA==.',
Zu='Zulfionn:BAABLgAECn8ZAAIFAAgJZwhQVQBIAQAFAAgJZwhQVQBIAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8bAAIiAAgJCxvWFQARAgAiAAgJCxvWFQARAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgIJAgAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8gAAQZAAgJkBp8FAChAQAZAAYJ5hp8FAChAQAJAAYJohYkDwCPAQAdAAQJ1heQRQDHAAAAAA==.',
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
