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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Unknown-Unknown','Monk-Mistweaver','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Druid-Balance','Mage-Frost','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Druid-Feral','Druid-Guardian','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-06-21',data={Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8iAAMCAAkJHx+GBwC5AgACAAkJHx+GBwC5AgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhpCIQA9AgAEAAgJyhpCIQA9AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn9AAAIFAAkJAh5dCgDmAgAFAAkJAh5dCgDmAgAAAA==.Amoralibash:BAABLgAECn8lAAQGAAgJfBO/WACTAQAGAAcJJRW/WACTAQAHAAMJ4g3jKgBvAAAIAAIJZwiMQgApAAAAAA==.Amorianstus:BAAALgAECgQJBAAAAA==.',
An='Anguskhan:BAAALgAECgYJDgAAAA==.Anhafel:BAABLgAECn8jAAIDAAYJmRaNfAAnAQADAAYJmRaNfAAnAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAAALgAECgkJDwAAAA==.',
Ap='Apocalipze:BAAALgADCgYJIgAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECgkJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAUJGQAJAP8aAA==.Arileous:BAABLgAECn8fAAIBAAYJuA1nTwAKAQABAAYJuA1nTwAKAQAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Artamis:BAAALgAECgEJAQAAAA==.Arthan:BAAALgADCgUJBQAAAA==.Artheen:BAAALgAECgcJBwAAAA==.',
As='Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAKAJsPAA==.Aspp:BAABLgAECn8kAAILAAkJ4hQJNAAuAgALAAkJ4hQJNAAuAgAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ay='Ayeamanoob:BAAALgADCgEJAgABLgAECgUJCAAMAAAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Be='Bearwitme:BAAALgADCgEJAQAAAA==.',
Bh='Bhalen:BAAALgADCgUJBQAAAA==.',
Bi='Bigmagic:BAAALgAECgEJBQAAAA==.Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgcJDAAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBQAAAA==.Britnysteers:BAAALgADCgkJDwAAAA==.Brungar:BAAALgAECgkJAQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8fAAINAAcJAxt4HgAmAgANAAcJAxt4HgAmAgAAAA==.Bucksdk:BAABLgAECn8aAAMOAAgJKBKVJgAfAQAOAAcJYhSVJgAfAQALAAIJQgOYXgFEAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECggJGgAOACgSAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECgkJQQAPAPwdAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgADCgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn9BAAMPAAkJ/B24BgASAwAPAAkJ/B24BgASAwAQAAUJEQa6QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAMAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECggJJQAGAHwTAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ9HKwC2AQAFAAkJYQ9HKwC2AQABLgABCgcJCQAMAAAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH85AAMLAAkJRyOQAAB0AgALAAgJRyOQAAB0AgAOAAIJgRueOQBQAAAuAAQKfzYABAsACQmEJecAAN0DAAsACQmEJecAAN0DAA4ABQnaJKgQAAACABEABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIGAAkJRh7aIABgAgAGAAkJRh7aIABgAgABLgAECgkJMQAKAKwlAA==.Deitha:BAAALgAECgUJCAAAAA==.Demonbane:BAABLgAECn8wAAMCAAkJfxwjCwB0AgACAAkJfxwjCwB0AgADAAcJXAr9kAD+AAAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMSAAgJ2g8RXQDPAAASAAUJaQYRXQDPAAATAAYJJRHmmgCdAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8ZAAIUAAcJIxj3DQDvAQAUAAcJIxj3DQDvAQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJEwAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAMAAAAAA==.',
Dy='Dyrillin:BAAALgADCgUJCgAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgkJDwAAAA==.Ellgar:BAAALgAECgQJBAABLgAECgYJFgAVAHQWAA==.',
En='Endymion:BAABLgAECn8cAAIFAAgJAhUNKADLAQAFAAgJAhUNKADLAQAAAA==.',
Et='Eternity:BAACLgAFFH8ZAAIJAAUJ/xoZNwA/AQAJAAUJ/xoZNwA/AQAuAAQKfy8AAgkACQkqIisMAOACAAkACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAATAFESAA==.Facetheflame:BAABLgAECn8ZAAIWAAcJABUsdgCNAQAWAAcJABUsdgCNAQABLgAECgkJFAATAFESAA==.Facethegem:BAABLgAECn8UAAMTAAkJURLeWQBQAQATAAYJ6hHeWQBQAQASAAYJGRKmSwAGAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAATAFESAA==.Facethezoom:BAABLgAECn8oAAIDAAkJrxzGEwCkAgADAAkJrxzGEwCkAgABLgAECgkJFAATAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAMAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8KAAIDAAQJGhAPaAC8AAADAAQJGhAPaAC8AAAuAAQKfx0AAwMACQkdGU8uAA4CAAMABwmVIE8uAA4CAAIACQmXA0MqAHMBAAEuAAUUCAkmABcAwh4A.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQUAAkJNwrUFgBiAQAUAAkJNwrUFgBiAQAYAAIJAg5SHQBjAAAZAAIJ4AsHhABVAAAAAA==.Fizwithagun:BAAALgAECgEJAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.Foxdaloc:BAAALgAECgEJAQAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIWAAgJvAblrQAlAQAWAAgJvAblrQAlAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRZoIwDYAQABAAkJVRZoIwDYAQAaAAEJTwkoVgArAAAAAA==.',
Ga='Galairn:BAAALgAECgYJCwAAAA==.Gallin:BAAALgADCggJDgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Ganicus:BAAALgAECgUJBwAAAA==.Gargoyle:BAAALgADCgMJAwAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxSEIwDXAQABAAkJDxSEIwDXAQAAAA==.Gasaiyuno:BAABLgAECn8oAAMbAAgJFQ6TPQAKAQAbAAcJOgyTPQAKAQANAAgJ8QesXQD/AAAAAA==.',
Ge='Geves:BAABLgAECn8VAAIXAAYJyBNyLgAqAQAXAAYJyBNyLgAqAQAAAA==.',
Gr='Grimmjob:BAAALgAECgEJAgAAAA==.Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgAECgEJAQAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAUJFAANADwXAA==.',
He='Hedgehog:BAAALgAECgcJCwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8bAAIKAAkJPRNEkgBOAQAKAAkJPRNEkgBOAQAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECggJDAAAAA==.Holyyoshi:BAABLgAECn8WAAIKAAgJCRGiVgDeAQAKAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8cAAIGAAkJhB18FQCkAgAGAAkJhB18FQCkAgAAAA==.',
Ja='Jab:BAACLgAFFH8NAAIOAAUJKwW3KACxAAAOAAUJKwW3KACxAAAuAAQKfyoAAg4ACAmwDzgkADEBAA4ACAmwDzgkADEBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMOAAkJ2hV4HABoAQAOAAgJPxh4HABoAQALAAcJkgjouAAHAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwAOANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn80AAIVAAkJXiT4AgBAAwAVAAkJXiT4AgBAAwAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8wAAIcAAkJYhrsDQBaAgAcAAkJYhrsDQBaAgAAAA==.',
Jo='Joker:BAABLgAECn8cAAIJAAcJSgi9ngAEAQAJAAcJSgi9ngAEAQAAAA==.Jomama:BAABLgAECn8jAAIKAAkJKg7uZACmAQAKAAkJKg7uZACmAQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh/sFABIAgABAAkJNh/sFABIAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCgkJCQAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kegs:BAAALgAECgEJAQABLgAECgkJMQAKAKwlAA==.Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECgkJMAAcAGIaAA==.Kes:BAAALgAECgUJCgAAAA==.',
Kk='Kk:BAAALgAECgEJAQAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAMAAAAAA==.',
Kr='Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJBwAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAMAAAAAA==.Leafygaga:BAAALgAECgcJEQAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECggJDQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgAECgMJAwABLgAECgkJIwAKACoOAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marie:BAAALgADCgcJBgAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJCAAAAA==.Meliôdas:BAAALgAECgEJCQAAAA==.Mendelson:BAAALgADCgEJAgABLgAECgUJCAAMAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAMAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAABLgAECn8aAAISAAYJ8gOIcACZAAASAAYJ8gOIcACZAAAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgkJCQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwABLgAECgkJGwAQAJILAA==.Mysteia:BAABLgAECn8lAAINAAkJfBxQEQCWAgANAAkJfBxQEQCWAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8XAAIdAAgJqBGbEgCNAQAdAAgJqBGbEgCNAQAAAA==.',
['Mø']='Mørdréd:BAAALgAECgEJAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAABLgAECn8VAAIeAAcJ0gzRFAAXAQAeAAcJ0gzRFAAXAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAUJGQAJAP8aAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMKAAYJRxWyngBBAQAKAAYJehSyngBBAQAfAAQJ0wcOMgCFAAABLgAFFAQJCQAZAAQGAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAQJCQAZAAQGAA==.',
Ni='Nihilist:BAABLgAECn8cAAIOAAkJwB2yEAAAAgAOAAkJwB2yEAAAAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAACLgAFFH8IAAITAAMJAhhCBwDHAAATAAMJAhhCBwDHAAAuAAQKf00AAhMACQmKH0ATALICABMACQmKH0ATALICAAAA.',
No='Noblessyou:BAAALgADCgcJCAABLgAECgUJCAAMAAAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.Nurgle:BAAALgAECgMJAwAAAA==.',
Ob='Obamanationn:BAAALgAECgQJBAAAAA==.Obeejoowan:BAAALgAECgIJAgAAAA==.Obeewand:BAAALgAECgUJBgAAAA==.Obijuan:BAABLgAECn8lAAIJAAgJywZKfABHAQAJAAgJywZKfABHAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn80AAMBAAgJ3hLlKwClAQABAAgJ3hLlKwClAQAgAAQJYgsFRwCuAAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIcAAgJ+SFuBwAOAwAcAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pa='Pallypocket:BAAALgADCgYJDwAAAA==.',
Pi='Pine:BAABLgAECn8YAAIFAAkJ7wuHMQCRAQAFAAkJ7wuHMQCRAQAAAA==.',
Pl='Plateguy:BAAALgAECgUJBwAAAA==.',
Po='Poxx:BAABLgAFFH8LAAIWAAQJ7R4cRQBdAQAWAAQJ7R4cRQBdAQABLgAFFAgJJgAXAMIeAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJCgAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.Raymondnodle:BAAALgAECgEJAQAAAA==.',
Rh='Rhayvival:BAABLgAFFH8UAAQNAAUJPBftHwBvAQANAAUJPBftHwBvAQAbAAIJzRJ8MACCAAAcAAIJAQhdUABhAAAAAA==.Rhayvoke:BAABLgAECn8XAAQZAAcJyxc8HQDdAQAZAAcJkxc8HQDdAQAUAAMJ2gt1OgCWAAAYAAEJGRltOgBHAAABLgAFFAUJFAANADwXAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8JAAMbAAYJLBaDEwAhAQAbAAUJoBqDEwAhAQANAAIJ2wgHUgBgAAABLgAFFAkJOQALAEcjAA==.Rossini:BAAALgADCgkJDwAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Rushs:BAAALgAECgQJBwABLgAECgUJCAAMAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8wAAIQAAkJyBo9FAAsAgAQAAkJyBo9FAAsAgAAAA==.Rynron:BAAALgAECgkJDgAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEwAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8jAAMPAAgJWRxZDwB6AgAPAAgJWRxZDwB6AgAQAAEJ9AUclgAkAAAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgkJGwAQAJILAA==.',
Se='Sempiternal:BAACLgAFFH8gAAIFAAYJ7g/PFgBwAQAFAAYJ7g/PFgBwAQAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIKAAkJzxzkNgAmAgAKAAkJzxzkNgAmAgAAAA==.Shaunanigans:BAABLgAECn8dAAITAAkJphB/MgDpAQATAAkJphB/MgDpAQAAAA==.Shaunsdh:BAAALgAECgQJBAABLgAECgkJHQATAKYQAA==.Shaunwick:BAAALgAECgUJBAABLgAECgkJHQATAKYQAA==.Shego:BAACLgAFFH8HAAIRAAMJxiQtDgAoAQARAAMJxiQtDgAoAQAuAAQKfyMABBEACQn8IHAFAF8CAAsABwk6ILgxAHECABEABwkrI3AFAF8CAA4AAgkdItFLAGAAAAEuAAUUBAkGAAYAMw8A.Sheltered:BAABLgAECn8xAAIKAAkJrCVVBQBKAwAKAAkJrCVVBQBKAwAAAA==.',
Si='Sinadora:BAAALgAECgUJCAAAAA==.Sinakra:BAABLgAECn8iAAIKAAkJmw/QagCZAQAKAAkJmw/QagCZAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8mAAIXAAgJwh4rBQBtAgAXAAgJwh4rBQBtAgAuAAQKfygAAhcACQniJQACAJcDABcACQniJQACAJcDAAAA.',
Sp='Spirits:BAAALgAECgMJAwABLgAFFAUJEgAFAI0bAA==.Spritz:BAABLgAECn8XAAIJAAgJKQyvZAB7AQAJAAgJKQyvZAB7AQAAAA==.',
St='Stampede:BAABLgAECn8WAAIBAAYJQwMpfwB5AAABAAYJQwMpfwB5AAAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCAAAAA==.Straya:BAABLgAECn8hAAMTAAkJDhXCJAAyAgATAAkJDhXCJAAyAgASAAEJPg1SrQAqAAAAAA==.',
Su='Subito:BAAALgADCgkJDwAAAA==.',
Ta='Taburiel:BAAALgADCgcJBwAAAA==.Taedwar:BAAALgADCgYJBgAAAA==.Tahirrah:BAABLgAECn8eAAIJAAkJ7RUbOgD2AQAJAAkJ7RUbOgD2AQAAAA==.Talindra:BAABLgAECn8cAAIOAAkJRQaJLAD3AAAOAAkJRQaJLAD3AAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9iAAMEAAkJJBOaJQAgAgAEAAkJJBOaJQAgAgAhAAkJvBOZAABJAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJCAAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8SAAIFAAUJjRtVEgCfAQAFAAUJjRtVEgCfAQAuAAQKfzMAAwUACQnqHIsLANQCAAUACQnqHIsLANQCAAoABQkOC1j8ALwAAAAA.',
Tm='Tmnt:BAABLgAECn8mAAINAAkJbgv+UAArAQANAAkJbgv+UAArAQAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQTAAkJ1x37bwAMAQATAAQJdBf7bwAMAQASAAcJvg/4TQD+AAAdAAUJPgkYLQCQAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAABLgAECn8UAAMRAAcJTRISEwBJAQARAAcJCxISEwBJAQAOAAQJKxMtNgC+AAAAAA==.',
Ts='Tsilihin:BAAALgAECgYJCAAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgANAA0eAA==.Tsurenity:BAACLgAFFH8GAAINAAIJDR6uDgCyAAANAAIJDR6uDgCyAAAuAAQKfxkAAg0ACAm+IjEEACwDAA0ACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAABLgAECn8XAAQhAAUJnghQNwB+AAAhAAQJWAdQNwB+AAAiAAMJ5QdPXABWAAAEAAMJbgOvwgBDAAABLgAFFAIJBwANAK8GAA==.',
Uk='Uki:BAAALgADCgQJBAAAAA==.',
Ur='Urbanfries:BAABLgAFFH8LAAMEAAYJZAg2JAA4AQAEAAYJZAg2JAA4AQAVAAMJcQGZSABSAAABLgAFFAUJFwATAIAfAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJSAANANcfAA==.Varr:BAAALgAECgYJEgAAAA==.Vayeda:BAABLgAECn8kAAIWAAkJ7iJNFADgAgAWAAkJ7iJNFADgAgAAAA==.',
Ve='Venderic:BAAALgAECgMJAwAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAZAAQGAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Xe='Xetz:BAABLgAECn8fAAMQAAkJ9gb8OgAmAQAQAAkJ9gb8OgAmAQAjAAEJawGKiQAkAAAAAA==.Xezar:BAACLgAFFH84AAQjAAgJuho7BQAPAgAPAAgJJBcOCwBuAgAjAAYJYR47BQAPAgAQAAQJAAnHDADeAAAuAAQKfycABBAACQk5GzEPAJECABAACQk5GzEPAJECACMABwlrHpoWACcCAA8AAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn82AAMWAAkJ5QvIegCDAQAWAAkJ5QvIegCDAQAkAAQJpwNoFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAACLgAFFH8GAAIPAAMJTgjMNgCvAAAPAAMJTgjMNgCvAAAuAAQKfycAAg8ACAkiFhIdAOUBAA8ACAkiFhIdAOUBAAAA.',
Za='Zarigar:BAAALgADCgkJDwAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zedan:BAAALgAECgUJBQAAAA==.Zeroh:BAAALgAECgYJDQAAAA==.',
Zi='Zigzagger:BAAALgAECgQJBgAAAA==.',
Zn='Zna:BAAALgAECgUJCwAAAA==.',
Zu='Zuka:BAAALgADCgEJAQAAAA==.',
['Øø']='Øø:BAAALgAECgYJEAAAAA==.',
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
