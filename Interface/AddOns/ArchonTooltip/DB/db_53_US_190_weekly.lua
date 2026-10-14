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

local lookup = {'Mage-Arcane','Priest-Holy','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','Priest-Discipline','Warrior-Arms','Druid-Balance','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Priest-Shadow','Shaman-Enhancement','Shaman-Elemental','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Hunter-Marksmanship','Paladin-Protection','Druid-Guardian','Druid-Feral','DeathKnight-Frost','DemonHunter-Devourer','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Warlock-Destruction','Hunter-Survival','DemonHunter-Havoc','Rogue-Subtlety','Druid-Restoration','Mage-Frost','Evoker-Preservation','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aarazi:BAABNQAECn8mAAIBAAgK9B/DRAD6AgABAAgK9B/DRAD6AgAAAA==.',
Ab='Abbinormal:BAAANQADCgYIFwAAAA==.Abolish:BAAANQAECgEIAgAAAA==.',
Ad='Adïrael:BAAANQABCggIDgAAAA==.',
Ae='Aeriss:BAAANQADCgYIDAAAAA==.Aethena:BAAANQADCgUIBQABNQAECgYIFgACALkNAA==.Aezili:BAAANQAECgEIAQAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAABNQAECn8cAAIDAAcK6R63WwCBAgADAAcK6R63WwCBAgAAAA==.',
Ah='Ahaego:BAAANQAECgUIEAAAAA==.Ahnari:BAAANQAECgEIAQAAAA==.',
Ak='Akkadien:BAABNQAECn8UAAMEAAgK8xykNgCHAgAEAAgK8xykNgCHAgADAAQKVgQBYQF8AAAAAA==.Akumunter:BAABNQAECn8jAAIFAAkK7hqBKgDtAgAFAAkK7hqBKgDtAgAAAA==.',
Al='Alacardias:BAABNQAECn8iAAIDAAgKiR1UQwDHAgADAAgKiR1UQwDHAgAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Alleril:BAAANQAECggIEQAAAA==.Allthesnacks:BAAANQADCgUIBQAAAA==.Aloe:BAAANQADCgYIBgAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAACNQAFFH8IAAICAAIK1yI8IgDIAAACAAIK1yI8IgDIAAA1AAQKfxgAAwIACAoiJMIgAOoCAAIACAoQJMIgAOoCAAYABArUGKcQAB0BAAAA.',
An='Anassand:BAAANQAECggIDAABNQAECggIFwAHAOAVAA==.Anatomic:BAAANQADCgIIAgABNQAECgYIFgACALkNAA==.Andimorph:BAABNQAECn8dAAIIAAgKfBmmMABZAgAIAAgKfBmmMABZAgAAAA==.Angeleria:BAAANQAECgEIAQAAAA==.',
Ap='Apazz:BAABNQAECn8mAAIFAAgKABYnbAA4AgAFAAgKABYnbAA4AgAAAA==.',
Aq='Aqualight:BAAANQAECgYICgABNQAECgkJJgAJAFYhAA==.Aquashade:BAAANQAECgUIBgABNQAECgkJJgAJAFYhAA==.Aquaterra:BAABNQAECn8mAAIJAAkKViFwDQBUAwAJAAkKViFwDQBUAwAAAA==.Aquina:BAAANQAECgYIDwABNQAECgkJJgAJAFYhAA==.',
Ar='Arakadia:BAABNQAECn8wAAMKAAgK7BJKUQDKAQAKAAgKORFKUQDKAQALAAIKixRkpACIAAAAAA==.Arcaina:BAAANQAECgMIAwAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAABNQAECn8ZAAMMAAgK7RkKGAD5AQAMAAcKbRkKGAD5AQANAAcKNBCaLgCeAQAAAA==.',
As='Aseanna:BAAANQAECgQIDQAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
At='Athira:BAAANQAECgEIAQAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgkJKAANAAEmAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgAOAAAAAA==.',
Av='Avarous:BAABNQAECn8cAAMCAAcKFRVvcwC9AQACAAcKFRVvcwC9AQAPAAEKAACliAAgAAAAAA==.Avataroffury:BAAANQAECgQIBAABNQAECggIFwAHAOAVAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAACNQAFFH8MAAIDAAMKQyCHEQAvAQADAAMKQyCHEQAvAQA1AAQKfxYAAgMACQrEIvt4ADYCAAMACQrEIvt4ADYCAAAA.',
Az='Azaireos:BAAANQADCgYIDQAAAA==.Azulpunkt:BAABNQAECn8YAAIQAAkKKhdtEQBQAgAQAAkKKhdtEQBQAgAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAABNQAECn8XAAMJAAgKfx33NwB9AgAJAAgKfx33NwB9AgARAAUKjg+JsQArAQAAAA==.Barbedwire:BAAANQAECggIAwAAAA==.',
Be='Bearmao:BAABNQAECn8oAAIFAAkKxxp9KAD0AgAFAAkKxxp9KAD0AgAAAA==.Beknight:BAABNQAECn8iAAILAAkKsh3WGQDdAgALAAkKsh3WGQDdAgAAAA==.Belfas:BAAANQAECgQICAAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgUICQAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAAANQAECggIDwAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAABNQAECn8lAAILAAgKRh0ILgBaAgALAAgKRh0ILgBaAgAAAA==.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgcIDAAAAA==.Bruute:BAABNQAECn8xAAIHAAkK8SFhFQBjAwAHAAkK8SFhFQBjAwAAAA==.',
Bu='Budplatinum:BAAANQAECgUICwAAAA==.',
['Bâ']='Bâït:BAAANQAECggIBwAAAA==.',
['Bå']='Båcon:BAAANQADCgcIBwAAAA==.',
Ca='Cairo:BAABNQAECn8mAAMSAAgK8yKVCwB+AgAHAAgKcx39UgCOAgASAAcKFiOVCwB+AgAAAA==.Calai:BAAANQADCggICAAAAA==.Capitalchaos:BAABNQAECn8wAAMTAAcK6BhoCwAKAgATAAcK6BhoCwAKAgAHAAEKDgarUQEwAAABNQAECgkJKwABAE4TAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECn8rAAIBAAkKThNppAA3AgABAAkKThNppAA3AgAAAA==.',
Ce='Cell:BAABNQAECn8sAAIUAAkKYyFlAgBdAwAUAAkKYyFlAgBdAwAAAA==.Ceviche:BAAANQAECgcICgAAAA==.Ceàrrdòrn:BAABNQAECn8VAAIDAAYK/hSWxQCKAQADAAYK/hSWxQCKAQAAAA==.',
Ch='Chibí:BAAANQADCggIFgABNQAECgcIDQAOAAAAAA==.Chillzmatic:BAAANQAECgIIBwAAAA==.Chudbucket:BAABNQAECn8YAAMFAAcKfRlmiwDwAQAFAAYKaBxmiwDwAQAVAAMKJQ4lZgCOAAAAAA==.',
Ci='Cirillø:BAAANQAECgEIAQABNQAECgkJLAAWAJklAA==.',
Cl='Clovergold:BAACNQAFFH8GAAIDAAMKIwffGwDDAAADAAMKIwffGwDDAAA1AAQKfyEAAgMACQroGsRNAKgCAAMACQroGsRNAKgCAAAA.Clyde:BAABNQAECn8aAAMXAAgKMAwgJQBoAQAXAAgKMAwgJQBoAQAYAAMKMgQPNQBoAAAAAA==.',
Co='Corbis:BAABNQAECn8WAAMKAAcKSQ1SfwAbAQAKAAYKIw5SfwAbAQAZAAUK/AY6dADIAAAAAA==.',
Cr='Crevarus:BAAANQAECgEIAQAAAA==.Crimsonjeybi:BAAANQAECgcJCAAAAA==.Crunchwich:BAAANQAECgQICQAAAA==.Cryos:BAAANQAECgIIAQAAAA==.',
Cu='Cutename:BAAANQAECgQIBAAAAA==.',
Cy='Cynamyn:BAAANQAECgUICQAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgYIDQAAAA==.Daevarys:BAAANQAECgEIAQAAAA==.Dakhran:BAAANQADCgIJBAAAAA==.Dakkä:BAAANQADCgYIBwABNQADCggIHgAOAAAAAA==.Dan:BAABNQAECn8YAAIZAAkKThfVHACgAgAZAAkKThfVHACgAgAAAA==.Danthrax:BAAANQAECgcIDAAAAA==.Darkdemon:BAABNQAECn8aAAIaAAYK9gf7RQAdAQAaAAYK9gf7RQAdAQAAAA==.Darlord:BAAANQAECgMIBAAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgkJKAANAAEmAA==.Deandrya:BAAANQAECggIBQAAAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQAECgQICQAAAA==.Demônlock:BAAANQAECgQICQAAAA==.Desideria:BAABNQAECn8ZAAMbAAcKwA7XCwCnAQAbAAcKwA7XCwCnAQAcAAIK0geCKAFlAAAAAA==.Despondence:BAABNQAECn8rAAIaAAkKiSEABwBhAwAaAAkKiSEABwBhAwAAAA==.Desynn:BAAANQAECgYJEAAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQAECgQICQAAAA==.Djtaki:BAABNQAECn8wAAIdAAkKzhrpFwC5AgAdAAkKzhrpFwC5AgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAYIFwAYAD4jAA==.Doncarlos:BAACNQAFFH8FAAIFAAIKJARkKgCIAAAFAAIKJARkKgCIAAA1AAQKfzEAAgUACQp1IB8UAE0DAAUACQp1IB8UAE0DAAAA.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQAECgEIAgAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFH8WAAMeAAcKURQnAwDkAAAcAAUKhBrVDQCcAQAeAAMKOhAnAwDkAAA1AAQKfyQAAxwACQqwIfUwAMECABwACAqhIfUwAMECAB4ABAomGi0tABcBAAAA.',
Dr='Drdevoted:BAAANQADCgIIAgAAAA==.Drippie:BAAANQADCgYICgAAAA==.Dròòid:BAAANQADCgQJBAABNQAECggIJQALAEYdAA==.',
Du='Dubdred:BAAANQAECgIIAwAAAA==.Duhon:BAAANQAECgEIAwAAAA==.Dumptruck:BAAANQAECggIEgAAAA==.',
Dw='Dwín:BAABNQAECn8ZAAIFAAgKZAYQsgCbAQAFAAgKZAYQsgCbAQAAAA==.',
['Dê']='Dêals:BAABNQAECn8bAAIEAAgK/RfgRgBIAgAEAAgK/RfgRgBIAgAAAA==.',
Ed='Edgelordxx:BAAANQAECgEIAQAAAA==.',
El='Elasper:BAAANQAECgEIAQAAAA==.Eliselyia:BAAANQADCgYIHQAAAA==.Ellierose:BAABNQAECn8UAAICAAgKRwg/iQB2AQACAAgKRwg/iQB2AQAAAA==.',
Em='Emelianas:BAAANQAECgQIBAABNQAECggIMAAKAOwSAA==.Ems:BAAANQAECgEIAQAAAA==.',
En='Enjin:BAABNQAECn8vAAMFAAgKNiIMIgANAwAFAAgKFiIMIgANAwAfAAMK/RxoDgC7AAAAAA==.Enragedbeef:BAAANQAECgUIBwABNQAECgkJNAACAMAQAA==.Entheogen:BAAANQAECgYIEwAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgQICAAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Es='Essay:BAAANQAECggIEQAAAA==.',
Et='Ethereall:BAABNQAECn8XAAMaAAkKxRhOHABwAgAaAAkKxRhOHABwAgAgAAMKOQHPjwA3AAAAAA==.',
Eu='Eudora:BAAANQADCggICAABNQAECgkJKAANAAEmAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgYIBwAAAA==.Evilice:BAABNQAECn8oAAIDAAgKQRAKqADLAQADAAgKQRAKqADLAQAAAA==.Evoka:BAAANQAECgYICAAAAA==.',
Fa='Faavibear:BAAANQAECggIAQAAAA==.Fallendevout:BAAANQAECgQICwAAAA==.Fallentroll:BAABNQAECn8dAAMKAAkKmhnFPAAqAgAKAAkKKBnFPAAqAgALAAMK7RziigDRAAAAAA==.Fatdoinkers:BAAANQAECggIEAABNQAECggIEgAOAAAAAA==.Fatman:BAAANQADCgcICAABNQADCgIIAwAOAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCggIDgAAAA==.Fayye:BAAANQAECgUIDAAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgQIDwAOAAAAAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAAANQAECgQIDwAAAA==.Fishstick:BAAANQADCggIGAAAAA==.',
Fl='Floatpass:BAABNQAECn8uAAIBAAkKDCHYHwBaAwABAAkKDCHYHwBaAwAAAA==.',
Fo='Foot:BAAANQAECgEIAQAAAA==.',
Fr='Frizz:BAAANQADCgcJAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAABNQAECn8UAAIEAAkKXxxuIQDmAgAEAAkKXxxuIQDmAgAAAA==.Fuzzytotems:BAAANQAECgcIDgAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAECggIJQALAEYdAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECn8fAAQcAAgKChHXeQDyAQAcAAgKChHXeQDyAQAeAAIKdQ8kWgBxAAAbAAIKOA1TJABcAAAAAA==.Galorfax:BAABNQAECn8cAAIXAAcKLiE4DQCOAgAXAAcKLiE4DQCOAgAAAA==.Galushi:BAAANQADCgYIDQAAAA==.Garm:BAABNQAECn8oAAIFAAkK8h/tEQBYAwAFAAkK8h/tEQBYAwABNQAECgkJMQAHAPEhAA==.',
Ge='Gelinea:BAAANQAECgEIAQAAAA==.Genovese:BAAANQADCgYJDAABNQAECgcIFgAKAEkNAA==.Gernar:BAAANQADCgUIBQAAAA==.',
Gi='Gilgaroth:BAABNQAECn8gAAMdAAgK4hh2JgBVAgAdAAgKRBV2JgBVAgAhAAgKfBSPFwAgAgAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAYIFwAYAD4jAA==.',
Go='Gobo:BAAANQAECggIEgAAAA==.',
Gr='Graysonn:BAAANQADCggIGQAAAA==.Greafox:BAABNQAECn8cAAMJAAkKAiTmBQCWAwAJAAkKAiTmBQCWAwARAAUKHxRMrAA3AQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAAANQAECgYIBgABNQAFFAYIFwAYAD4jAA==.Gundrakk:BAABNQAECn8WAAIiAAYKpRbvMACPAQAiAAYKpRbvMACPAQAAAA==.Gunnr:BAAANQAECgQICgABNQAECgcIDQAOAAAAAA==.Gunthorian:BAAANQAECgMJBAAAAA==.',
Ha='Hame:BAAANQAECgEIAQAAAA==.Handsomemonk:BAAANQADCgMIBAABNQAECggIEgAOAAAAAA==.Hansi:BAAANQAECgEIAgAAAA==.',
He='Heart:BAAANQAECgUIBAABNQAECggIFQADAI8cAA==.Heid:BAAANQADCgYIDQAAAA==.Helldozer:BAAANQAECgEIAQAAAA==.',
Hi='Higanbana:BAACNQAFFH8bAAIaAAYKtyBRAwAlAgAaAAYKtyBRAwAlAgA1AAQKfy8AAhoACQr+I9kFAHIDABoACQr+I9kFAHIDAAAA.Himawari:BAABNQAECn8eAAIDAAgKDyAdQgDLAgADAAgKDyAdQgDLAgABNQAFFAYIGwAaALcgAA==.Himejoshi:BAACNQAFFH8XAAIYAAYKPiNNAABxAgAYAAYKPiNNAABxAgA1AAQKfzMAAhgACQrMJiIBAMwDABgACQrMJiIBAMwDAAAA.Hippocampus:BAABNQAECn8UAAIJAAYKIR0lXQD0AQAJAAYKIR0lXQD0AQAAAA==.Hirys:BAABNQAECn8XAAIhAAgKKxMbGwD7AQAhAAgKKxMbGwD7AQAAAA==.',
Ho='Holybeks:BAAANQAECgEIBAABNQAECgkJIgALALIdAA==.Holydaddy:BAAANQAECgQIBgAAAA==.Holysmite:BAAANQAECgQIBAABNQAECgcICQAOAAAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECggIEgAOAAAAAA==.Hotshotzz:BAAANQAECgMIAwABNQAECggIIwADAF0fAA==.',
Hu='Huntfosho:BAAANQAECgMIAwAAAA==.Huntsmedown:BAAANQADCgYIBgAAAA==.',
['Há']='Háldrin:BAACNQAFFH8IAAIVAAMKiRz4EwD7AAAVAAMKiRz4EwD7AAA1AAQKfykAAxUACQotI5ALAB4DABUACQpsIpALAB4DAAUAAQo0Jic+AVwAAAAA.',
['Hö']='Hölybeary:BAAANQAECgcIDQAAAA==.',
Ia='Iamprepared:BAAANQAECgEIAQAAAA==.',
Ic='Icybacon:BAAANQAECgQIBQAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAAANQAECgUIDAAAAA==.',
Im='Imbue:BAABNQAECn8fAAIUAAgKsh5sBgCwAgAUAAgKsh5sBgCwAgAAAA==.Imbuer:BAAANQAECgQICAAAAA==.',
In='Innil:BAABNQAECn8YAAICAAkKcyUrAgDIAwACAAkKcyUrAgDIAwAAAA==.',
It='Itzapazz:BAAANQADCggICAAAAA==.',
Je='Jessix:BAAANQAECggIDQAAAA==.Jezebel:BAABNQAECn8dAAMcAAkK2hXcTABqAgAcAAkK3BPcTABqAgAeAAEKoRdrawBIAAAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJBAAAAA==.',
Jo='Jomadead:BAAANQAECgYIDAABNQAECgkJFgAJAIEUAA==.Jomas:BAABNQAECn8WAAIJAAkKgRTYVAAQAgAJAAkKgRTYVAAQAgAAAA==.Jovaar:BAAANQADCgYIBgAAAA==.',
Ju='Judera:BAABNQAECn8lAAIDAAkKKxZCZABqAgADAAkKKxZCZABqAgAAAA==.Juditis:BAAANQAECgEIAQAAAA==.',
Ka='Kagura:BAAANQABCgcICwAAAA==.Kaing:BAAANQAECgUIEQAAAA==.Kaladen:BAABNQAECn8WAAQiAAkKWSEFBwBQAwAiAAkKWSEFBwBQAwAIAAEKlhI9qwA8AAAXAAEKvxfZWgA7AAAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECggIFwAAAQ==.Kaoticnature:BAAANQADCgYIDQAAAA==.Karolg:BAAANQAECgYIDgAAAA==.Katostrafic:BAABNQAECn8iAAMGAAgKeBQnCQDHAQAGAAcKcBUnCQDHAQACAAcKbQwohQCDAQAAAA==.Katrynna:BAAANQADCgYIEwAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAACNQAFFH8FAAIUAAIKJBITBQB0AAAUAAIKJBITBQB0AAA1AAQKfy4AAxQACQqmID4DADUDABQACQqmID4DADUDABoABwrVDTk2AI0BAAAA.',
Ki='Kiaradarkpaw:BAAANQAECgEIAwAAAA==.Killidan:BAABNQAECn8iAAIaAAkKqRucEwDJAgAaAAkKqRucEwDJAgAAAA==.Kirklees:BAAANQAECgMIBAAAAA==.Kitsuchan:BAABNQAECn8VAAMBAAkKOR8oSQDwAgABAAgK9R4oSQDwAgAjAAIKQyJxJADHAAABNQAECggIGgAgAC8kAA==.',
Ko='Kodama:BAABNQAECn8dAAIRAAcKewnlkAB2AQARAAcKewnlkAB2AQAAAA==.Koi:BAAANQADCgcIEgABNQAECggIIwAUACEeAA==.Kookiemon:BAAANQAECgYIBgAAAA==.Kookiesplz:BAAANQADCggICAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Krekdas:BAAANQADCgUIBQAAAA==.Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQAECggIIgAGAHgUAA==.',
Ky='Kyanna:BAAANQAECgQICQAAAA==.',
La='Lader:BAABNQAFFH8GAAIDAAYKHwCDMQBGAAADAAYKHwCDMQBGAAAAAA==.Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAABNQAECn8UAAIaAAgKshUwJQAZAgAaAAgKshUwJQAZAgAAAA==.Laxinmedium:BAAANQADCgYIDQAAAA==.',
Le='Leenei:BAAANQAECgMIBAAAAA==.Lenlaar:BAAANQAECgQICQAAAA==.Levande:BAABNQAECn8YAAICAAkKzxAlUAAwAgACAAkKzxAlUAAwAgAAAA==.',
Li='Lifeblume:BAAANQADCggIFQAAAA==.Lildevil:BAAANQADCgQIBAAAAA==.Lilithandria:BAAANQAECgcIDwAAAA==.Linamar:BAAANQAECgQIBAAAAA==.Litenpr:BAAANQAECgEIAgAAAA==.',
Lo='Loaq:BAABNQAECn8sAAMCAAkK9RTeRQBSAgACAAkK9RTeRQBSAgAGAAMK4gg6HACBAAAAAA==.Lockzrockz:BAAANQAECgEIAgAAAA==.Longbottom:BAAANQAECgYICQABNQAECggIEgAOAAAAAA==.Loot:BAAANQAECggICAAAAA==.Lorbert:BAAANQAECgMIAwABNQAECgkJIgAHAKAUAA==.Lostalot:BAABNQAECn8gAAIFAAgKHxRWXQBbAgAFAAgKHxRWXQBbAgAAAA==.',
Lu='Luxæterna:BAABNQAECn8uAAIDAAkKaRvDSwCuAgADAAkKaRvDSwCuAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECggIIwAMAOYgAA==.',
Ma='Malice:BAABNQAECn8VAAMbAAgKghUTCgDYAQAbAAgKghUTCgDYAQAeAAIKZAVwaABPAAAAAA==.Mandwandos:BAAANQAECgcIEwAAAA==.Maraliss:BAAANQAECgQIDAAAAA==.',
Me='Melaunis:BAAANQADCgYIDwAAAA==.Meowzer:BAAANQAECgQIEQABNQAECgkJNAACAMAQAA==.Meteora:BAACNQAFFH8IAAISAAMKMRLKBADEAAASAAMKMRLKBADEAAA1AAQKfxwAAhIACQoeG1QMAG0CABIACQoeG1QMAG0CAAAA.',
Mi='Mideel:BAAANQAECgQICQAAAA==.Migolbearcow:BAABNQAECn8qAAIXAAgKRxr6DgBvAgAXAAgKRxr6DgBvAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwAOAAAAAA==.Missrae:BAAANQADCggIEgAAAA==.',
Mk='Mk:BAEANQADCgIIAgABNQAECggIJQANAOIdAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAgAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Moondizzle:BAAANQAECgIIAwAAAA==.Mooniè:BAAANQAECgQIDQAAAA==.Moosenuts:BAAANQAECgcIEAAAAA==.Moriavus:BAABNQAECn8mAAIbAAgKxRuqBACMAgAbAAgKxRuqBACMAgAAAA==.Morocha:BAABNQAECn8YAAIMAAYKjw2SKAArAQAMAAYKjw2SKAArAQAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.',
Mu='Muragore:BAAANQAECgIIBwAAAA==.',
My='Mychropien:BAABNQAECn8YAAIKAAgKVCCFIgC6AgAKAAgKVCCFIgC6AgAAAA==.Myylus:BAAANQADCgYIFAAAAA==.',
['Mö']='Mökes:BAABNQAECn8tAAIeAAkKwiIAAQCbAwAeAAkKwiIAAQCbAwAAAA==.',
Na='Nadroj:BAAANQADCgUIFQAAAA==.Nancydru:BAAANQAECgUIBgAAAA==.Naosu:BAAANQADCgEJAQAAAA==.Nax:BAAANQAECgQIDAAAAA==.Nazzersaurus:BAABNQAECn8aAAIiAAcKYxl+JQDzAQAiAAcKYxl+JQDzAQAAAA==.',
Ne='Nec:BAAANQAECgEIAgAAAA==.Necrøtic:BAABNQAECn8eAAMjAAgK3A8tDQDcAQAjAAgKpw8tDQDcAQABAAQKqgaOigGqAAAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQAECgQIBAAAAA==.Nevermiss:BAABNQAECn8iAAIMAAcKVBqeFgAPAgAMAAcKVBqeFgAPAgAAAA==.',
Ni='Nightjewel:BAAANQADCgYIDQAAAA==.',
No='Noggs:BAAANQAECgEIAQAAAA==.Notmewasyou:BAABNQAECn8YAAIIAAYK2wIDhgC1AAAIAAYK2wIDhgC1AAAAAA==.',
Nu='Nuali:BAABNQAECn8aAAMDAAgKXBmlYgBuAgADAAgKXBmlYgBuAgAWAAQK8BMlPwD7AAAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggJDQAAAA==.',
On='Onlyspins:BAAANQAECgYICAAAAA==.',
Or='Orý:BAABNQAECn8wAAIRAAkKfht4KwDOAgARAAkKfht4KwDOAgAAAA==.',
Os='Oslatem:BAAANQAECgEIAQAAAA==.',
Ox='Oxosorrel:BAAANQAECgEIBgAAAA==.',
Oz='Ozzmodious:BAAANQADCgUIEAAAAA==.',
Pa='Paladan:BAABNQAECn8jAAIWAAkKDiBGBwAtAwAWAAkKDiBGBwAtAwAAAA==.Palagi:BAABNQAECn8VAAMYAAYKiwcULwCTAAAYAAUKwwMULwCTAAAiAAEKugTkewAjAAAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAABNQAECn8WAAIEAAgKwhuPMQCdAgAEAAgKwhuPMQCdAgAAAA==.Pallyfosho:BAAANQAECgIIAgAAAA==.Pallymcbeall:BAAANQAECgIIAgAAAA==.Paprikaman:BAAANQAECgQICQAAAA==.Parallax:BAAANQAECgEIAQAAAA==.Pariahrain:BAAANQAECgYIEwABNQAECgkJJAABAM4PAA==.Parishealton:BAABNQAECn8cAAMiAAkKox/JCQAnAwAiAAkKox/JCQAnAwAIAAMKvQGapABMAAAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Pe='Penjamin:BAAANQAECgMIAwABNQAECggIEgAOAAAAAA==.Perprotrus:BAAANQAECgEIAQABNQAECggIJQALAEYdAA==.',
Po='Poulsbo:BAAANQADCgcIBgAAAA==.Pozole:BAAANQAECgcIDwAAAA==.',
Pr='Prominence:BAABNQAECn8WAAIfAAYKzh9IBwAHAgAfAAYKzh9IBwAHAgAAAA==.Promisques:BAAANQAECgEIBAAAAA==.Prozak:BAABNQAECn8iAAIJAAgKqRQvYQDnAQAJAAgKqRQvYQDnAQAAAA==.',
Pw='Pwomf:BAAANQAECgYICAAAAA==.',
Py='Pyneapple:BAAANQADCgQIBAABNQAECgkJNAACAMAQAA==.Pyrolily:BAAANQAECgUICwAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYICwAAAA==.Raght:BAAANQADCgEIAQAAAA==.Raha:BAAANQAECgEIAQAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECn8bAAMMAAgKWBVyGADyAQAMAAgKWBVyGADyAQANAAcKdhSeMACOAQAAAA==.Rastakan:BAAANQAECgUICAABNQAECgkJMQAHAPEhAA==.Razal:BAAANQADCggIDQAAAA==.',
Re='Reesespiecez:BAAANQAECgcJDAAAAA==.Rellidana:BAAANQAECgQICAAAAA==.Remove:BAAANQAECgUIBQAAAA==.Reprieve:BAAANQAECgYIBgAAAA==.Retradormi:BAAANQAECgEIAQAAAA==.Rexi:BAABNQAECn8hAAIPAAkKCg4zJwDuAQAPAAkKCg4zJwDuAQAAAA==.',
Ri='Rickcando:BAAANQAECgUIEQAAAA==.Ricshard:BAABNQAECn8bAAMeAAYKVRXlQAC+AAAcAAQKjxYs2gAQAQAeAAMKfRPlQAC+AAAAAA==.Ridjeckgron:BAAANQAECgEIAQAAAA==.',
Rm='Rmft:BAAANQADCgYIFQABNQAECgcIHgAHACgaAA==.',
Ro='Roomnboard:BAAANQAECgMIBQAAAA==.Rotter:BAAANQADCgMIAwAAAA==.Roughluver:BAAANQAECgIIAgABNQAECgkJNAACAMAQAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgQICQAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rylia:BAAANQAECgEIAQAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAAANQAECgEIAwAAAA==.',
['Rà']='Ràein:BAABNQAECn8gAAIeAAUKqg6WIgBcAQAeAAUKqg6WIgBcAQAAAA==.',
['Ró']='Ród:BAABNQAECn8jAAIDAAgKXR9rbQBSAgADAAgKXR9rbQBSAgAAAA==.',
['Rø']='Røth:BAAANQADCgYIDAAAAA==.',
Sa='Saalira:BAAANQADCgcIEAAAAA==.Sabellice:BAABNQAECn8dAAIDAAcKWQWZ9AAuAQADAAcKWQWZ9AAuAQAAAA==.Sakonna:BAABNQAECn8fAAIPAAkKQRUkIAA1AgAPAAkKQRUkIAA1AgAAAA==.Salinoria:BAAANQAECgQIDAABNQAECggIGgADAFwZAA==.Sandymaw:BAAANQADCgQIBAABNQAECgkJNAACAMAQAA==.Sarlius:BAABNQAECn8vAAIFAAkKDSbWAgDZAwAFAAkKDSbWAgDZAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAABNQAECn8VAAIDAAgKjxxgXgB6AgADAAgKjxxgXgB6AgAAAA==.Savin:BAAANQAECgIIBAAAAA==.',
Sc='Scavenger:BAAANQAECgUIDQAAAA==.Scorchin:BAAANQAECggIAwAAAA==.Scrumptiøus:BAAANQAECgIIAwABNQAECggIIgAGAHgUAA==.',
Se='Selkamonk:BAABNQAECn8jAAIMAAgK5iDDCgDXAgAMAAgK5iDDCgDXAgAAAA==.Seniorbold:BAABNQAECn8YAAIDAAkKbBqHQQDNAgADAAkKbBqHQQDNAgAAAA==.Sentrina:BAACNQAFFH8FAAIkAAIKQg7aFACDAAAkAAIKQg7aFACDAAA1AAQKfy0AAiQACQpCHQENANQCACQACQpCHQENANQCAAAA.Seraph:BAAANQAECgEIBAAAAA==.Seshy:BAABNQAECn80AAMCAAkKwBCRTAA8AgACAAkKwBCRTAA8AgAPAAgK3hjQHwA5AgAAAA==.Seshymutedme:BAAANQAECggIEwABNQAECgkJNAACAMAQAA==.Sethan:BAAANQAECgEIAQAAAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgUIDAAOAAAAAA==.Shannoon:BAAANQAECgUIDgAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECn8oAAQNAAkKASbeAADnAwANAAkKASbeAADnAwAMAAYK0hymGgDSAQAlAAIKCSO2IgC/AAAAAA==.Shiverr:BAABNQAECn8dAAIjAAcK1QbkGAAtAQAjAAcK1QbkGAAtAQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECggIFwAHAOAVAA==.',
Si='Siatraz:BAAANQAECgEIAgABNQAECgQIDwAOAAAAAA==.Siegatrox:BAAANQAECgIIAgAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQAECgEIBAAAAA==.Skott:BAAANQADCggIKwAAAA==.Skïnnyßetch:BAAANQADCgcIBwAAAA==.',
Sl='Sleepadin:BAAANQAECgcIDgAAAA==.Sleepyr:BAAANQAECgYIEAAAAA==.',
Sm='Smokeymage:BAAANQADCgcIBwAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECgcIDQAOAAAAAA==.Snowstorm:BAAANQAECgEIAgAAAA==.',
So='Soakra:BAABNQAECn8fAAIJAAkKLhUERABOAgAJAAkKLhUERABOAgAAAA==.Solignis:BAACNQAFFH8bAAMTAAYKZyUUAAChAgATAAYKZyUUAAChAgAHAAQK6R6/EwCJAQA1AAQKfzgAAxMACQoEJwUAAB4EABMACQoEJwUAAB4EAAcACQp/JrwHALQDAAAA.Solxeen:BAAANQADCggICAAAAA==.Soniviolence:BAABNQAECn8mAAIHAAkKeSAEGwBKAwAHAAkKeSAEGwBKAwAAAA==.Soohots:BAABNQAECn8VAAMiAAkKERxHFACkAgAiAAgKSxxHFACkAgAIAAMKSxByjACfAAAAAA==.Sourskittlz:BAAANQADCgQIBAAAAA==.',
Sp='Sparklehappy:BAABNQAECn8UAAMVAAYKrxm4OQB8AQAVAAUKihm4OQB8AQAFAAEKQRphQQFUAAAAAA==.Splìff:BAAANQADCgYIBgAAAA==.Sppazz:BAAANQADCgcIBwAAAA==.',
St='Stausa:BAAANQADCgcIBwAAAA==.Steeljustice:BAAANQAECggICAAAAA==.Stormcreek:BAABNQAECn8UAAMJAAYKDhjMmABFAQAJAAUKWhXMmABFAQARAAEKAACnQwEqAAAAAA==.Storri:BAABNQAECn8zAAMCAAkKEhl6KwC4AgACAAkKEhl6KwC4AgAPAAUKwgYmUwC9AAAAAA==.Styló:BAAANQAECgEIAgAAAA==.',
Su='Sufferinhero:BAAANQAECgEIAQABNQAFFAIIBQAUACQSAA==.Suzuya:BAAANQADCggIFAAAAA==.',
Sw='Swiftly:BAAANQAECgUIBgAAAA==.Swiftmage:BAACNQAFFH8bAAMjAAYKIyI1AABjAgAjAAYKIyI1AABjAgABAAUKvR15GQCpAQA1AAQKfzoAAyMACQrcJg8AAAgEACMACQrcJg8AAAgEAAEACQoqJUoYAHMDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Sygh:BAAANQAECgEIAgABNQAECggIFQADAI8cAA==.Syndragonkin:BAABNQAECn8gAAIFAAcKzhjeeQAYAgAFAAcKzhjeeQAYAgAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgYIEAAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFH8cAAIVAAcKQh+PAgB5AgAVAAcKQh+PAgB5AgA1AAQKfyoAAhUACQoEI0cHAFoDABUACQoEI0cHAFoDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQADCgcIEQAAAA==.Taze:BAAANQAECgUJBwABNQAECggIJQALAEYdAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAABNQAECn8ZAAIFAAgKnwraiAD1AQAFAAgKnwraiAD1AQAAAA==.Tetshajeh:BAACNQAFFH8FAAIHAAIKFRE6LgCOAAAHAAIKFRE6LgCOAAA1AAQKfzkAAwcACQr0IC4YAFcDAAcACQr0IC4YAFcDABIAAwrQGFUrANkAAAAA.Teyliana:BAAANQAECgQICQAAAA==.',
Th='Thillarick:BAABNQAECn8eAAIHAAcKKBoldwAtAgAHAAcKKBoldwAtAgAAAA==.Thromanor:BAAANQAECgUIBQAAAA==.Thwip:BAABNQAECn8oAAMFAAgK6yHhKwDpAgAFAAgK6yHhKwDpAgAVAAcKTg7zPQBdAQAAAA==.',
Ti='Tikwid:BAABNQAECn8eAAIBAAcK3QXyHgFUAQABAAcK3QXyHgFUAQAAAA==.Tiranmyashol:BAABNQAECn8iAAIHAAkKoBSnZwBVAgAHAAkKoBSnZwBVAgAAAA==.',
To='Tomoya:BAABNQAECn8UAAMEAAgKuhgbRwBHAgAEAAgKuhgbRwBHAgAWAAEKAAAFdAAnAAAAAA==.Too:BAAANQAECgIIAgAAAA==.Toothdk:BAAANQAECgQICAAAAA==.Tormmentor:BAAANQAECgIIBgAAAA==.',
Tr='Treebreak:BAAANQAECgQIDwAAAA==.',
Ty='Tyrandrea:BAAANQAECgEIAQAAAA==.',
Ud='Udari:BAAANQAECgcICAAAAA==.Udarii:BAAANQAECgMIBQAAAA==.',
Um='Umàdbrah:BAABNQAECn8bAAIFAAYK3SKjYQBQAgAFAAYK3SKjYQBQAgAAAA==.',
Un='Unbelievable:BAAANQAECgcIEQAAAA==.Unprovoked:BAABNQAECn8iAAIBAAkKwh5vVgDTAgABAAkKwh5vVgDTAgAAAA==.',
Va='Valamor:BAABNQAECn8bAAMWAAYKdBHDNQA1AQAWAAYKdBHDNQA1AQAEAAUK4AeKywDgAAAAAA==.Varenea:BAAANQADCgYIBgAAAA==.Varia:BAAANQAECgEIBAABNQAECggIFwAHAOAVAA==.',
Ve='Veefib:BAABNQAECn8lAAIRAAgK9xrxPwBzAgARAAgK9xrxPwBzAgAAAA==.Velvettwitch:BAABNQAECn8iAAIeAAcKQxEwEgDiAQAeAAcKQxEwEgDiAQAAAA==.Vendler:BAAANQAECgcIEgAAAA==.Verahla:BAAANQADCgYIFwAAAA==.Vermis:BAABNQAECn8eAAIZAAcK5hBxSQCPAQAZAAcK5hBxSQCPAQAAAA==.Veryaverage:BAAANQAECgYICwAAAA==.Vexation:BAAANQAECgEIAgAAAA==.',
Vi='Vicarious:BAABNQAECn8UAAIJAAcKsB1UPQBnAgAJAAcKsB1UPQBnAgAAAA==.Vidreaux:BAABNQAECn8pAAMBAAgKDQ1b7gCqAQABAAcKhQ1b7gCqAQAjAAEKuAofQwA8AAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.Vivid:BAAANQAECgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQAECgQIBAAAAA==.Volke:BAAANQAECgUIBQAAAA==.Votingromney:BAAANQAECgcICwABNQAECgkJKAANAAEmAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECn8nAAIFAAgKOhunWgBiAgAFAAgKOhunWgBiAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECgcICQAAAA==.',
Wa='Waldorf:BAAANQAECgMIAwAAAA==.Wallegator:BAAANQADCgIIBAABNQAECgYIGQAiAOggAA==.Walleroot:BAAANQAECgUIBQABNQAECgYIGQAiAOggAA==.Waptoed:BAAANQAECgEIAQAAAA==.',
We='Weinersoup:BAAANQAECgMIBQAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQAECgQIBQAAAA==.',
Wo='Wolfpup:BAAANQAECggIDQABNQAECgkJJQADACsWAA==.Wolfíe:BAAANQADCgUIBQAAAA==.Worstelf:BAABNQAECn8fAAMCAAgKPBoXPwBrAgACAAgKPBoXPwBrAgAPAAYKgiKkIQAmAgAAAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgYIDQAAAA==.',
Yf='Yfelshammy:BAABNQAECn8nAAIJAAgKphYgSwAzAgAJAAgKphYgSwAzAgAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAFFAIICAACANciAA==.Yvonnél:BAAANQADCggIIgAAAA==.',
Za='Zaknafein:BAAANQAECgUIBQAAAA==.Zanebusby:BAABNQAECn8iAAIeAAkKuRpjAwAOAwAeAAkKuRpjAwAOAwAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgcIDgABNQAECgkJKAANAAEmAA==.Zartash:BAAANQAECgUIDQAAAA==.Zatharis:BAAANQAECgQIDAAAAA==.',
Ze='Zelik:BAAANQAECgEIAwABNQAECgkJLwAFAA0mAA==.Zenezin:BAAANQAECgMIBAABNQAECggIFwAHAOAVAA==.Zerax:BAAANQAECgMIAwAAAA==.Zevellian:BAAANQAECgEIAQABNQAECggIFAAEAPMcAA==.',
Zm='Zmona:BAABNQAECn8XAAIHAAgK4BXsgwAOAgAHAAgK4BXsgwAOAgAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECggIFQADAI8cAA==.',
['Ðr']='Ðragonshaft:BAABNQAECn8qAAIFAAgKCxYkawA6AgAFAAgKCxYkawA6AgAAAA==.Ðreadlokz:BAAANQAECgEIAQAAAA==.',
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
