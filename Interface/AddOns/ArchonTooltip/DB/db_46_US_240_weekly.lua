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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Unknown-Unknown','Monk-Mistweaver','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Druid-Balance','Mage-Frost','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Monk-Windwalker','Monk-Brewmaster','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Druid-Feral','Druid-Guardian','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-06-28',data={Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8iAAMCAAkJHx+FBwC5AgACAAkJHx+FBwC5AgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhpAIQA9AgAEAAgJyhpAIQA9AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn9AAAIFAAkJAh5dCgDmAgAFAAkJAh5dCgDmAgAAAA==.Amoralibash:BAABLgAECn8lAAQGAAgJfBO+WACTAQAGAAcJJRW+WACTAQAHAAMJ4g3kKgBvAAAIAAIJZwiNQgApAAAAAA==.Amorianstus:BAAALgAECgQJBAAAAA==.',
An='Anguskhan:BAAALgAECgYJDwAAAA==.Anhafel:BAABLgAECn8jAAIDAAYJmRaMfAAnAQADAAYJmRaMfAAnAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAAALgAECgkJEAAAAA==.',
Ap='Apocalipze:BAAALgADCggJJAAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECgkJCAAAAA==.Ardinn:BAAALgAECgUJBwAAAA==.Ares:BAAALgAECgEJAQABLgAFFAUJGQAJAP8aAA==.Arileous:BAABLgAECn8jAAIBAAYJuA1qTwAKAQABAAYJuA1qTwAKAQAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Artamis:BAAALgAECgEJAQAAAA==.Arthan:BAAALgADCgUJBQAAAA==.Artheen:BAAALgAECgcJBwAAAA==.',
As='Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAKAJsPAA==.Aspp:BAABLgAECn8kAAILAAkJ4hQINAAuAgALAAkJ4hQINAAuAgAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ay='Ayeamanoob:BAAALgADCgEJAgABLgAECgUJCAAMAAAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Be='Bearwitme:BAAALgADCgEJAQAAAA==.',
Bh='Bhalen:BAAALgADCgYJBgAAAA==.',
Bi='Bigmagic:BAAALgAECgEJBgAAAA==.Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgcJDAAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBQAAAA==.Britnysteers:BAAALgADCgkJDwAAAA==.Brungar:BAAALgAECgkJAQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8fAAINAAcJAxt3HgAmAgANAAcJAxt3HgAmAgAAAA==.Bucksdk:BAABLgAECn8aAAMOAAgJKBKWJgAfAQAOAAcJYhSWJgAfAQALAAIJQgOdXgFEAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECggJGgAOACgSAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECgkJSAAPAP8eAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgADCgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn9IAAMPAAkJ/x67AAB/AgAPAAkJ/x67AAB/AgAQAAUJEQa6QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAMAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECggJJQAGAHwTAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ9IKwC2AQAFAAkJYQ9IKwC2AQABLgABCgcJCQAMAAAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH8/AAMLAAkJjCSQAAB0AgALAAgJjCSQAAB0AgAOAAIJgRugOQBQAAAuAAQKfzgABAsACQmEJecAAN0DAAsACQmEJecAAN0DAA4ABQnaJKgQAAACABEABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIGAAkJRh7cIABgAgAGAAkJRh7cIABgAgABLgAECgkJMQAKAKwlAA==.Deitha:BAAALgAECgUJCgAAAA==.Demonbane:BAABLgAECn8wAAMCAAkJfxwiCwB0AgACAAkJfxwiCwB0AgADAAcJXAoAkQD+AAAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMSAAgJ2g8RXQDPAAASAAUJaQYRXQDPAAATAAYJJRHpmgCdAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8ZAAIUAAcJIxj3DQDvAQAUAAcJIxj3DQDvAQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJEwAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAMAAAAAA==.',
Dy='Dyrillin:BAAALgADCgUJCgAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgkJDwAAAA==.Ellgar:BAAALgAECgQJBAABLgAECgYJFgAVAHQWAA==.',
Em='Emerigosa:BAAALgAECgQJBAAAAA==.',
En='Endymion:BAABLgAECn8cAAIFAAgJAhUOKADLAQAFAAgJAhUOKADLAQAAAA==.',
Et='Eternity:BAACLgAFFH8ZAAIJAAUJ/xoYNwA/AQAJAAUJ/xoYNwA/AQAuAAQKfy8AAgkACQkqIisMAOACAAkACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAATAFESAA==.Facetheflame:BAABLgAECn8ZAAIWAAcJABUudgCNAQAWAAcJABUudgCNAQABLgAECgkJFAATAFESAA==.Facethegem:BAABLgAECn8UAAMTAAkJURLeWQBQAQATAAYJ6hHeWQBQAQASAAYJGRKpSwAGAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAATAFESAA==.Facethezoom:BAABLgAECn8oAAIDAAkJrxzEEwCkAgADAAkJrxzEEwCkAgABLgAECgkJFAATAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAMAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8KAAIDAAQJGhAMaAC8AAADAAQJGhAMaAC8AAAuAAQKfx0AAwMACQkdGU0uAA4CAAMABwmVIE0uAA4CAAIACQmXA0MqAHMBAAEuAAUUCQkyABcAPCAA.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQUAAkJNwrUFgBiAQAUAAkJNwrUFgBiAQAYAAIJAg5SHQBjAAAZAAIJ4AsKhABVAAAAAA==.Fizwithagun:BAAALgAECgEJAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.Foxdaloc:BAAALgAECgcJBwAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIWAAgJvAbrrQAlAQAWAAgJvAbrrQAlAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRZqIwDYAQABAAkJVRZqIwDYAQAaAAEJTwksVgArAAAAAA==.',
Ga='Galairn:BAAALgAECgYJCwAAAA==.Gallin:BAAALgADCggJDgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Ganicus:BAAALgAECgUJBwAAAA==.Gargoyle:BAAALgADCgMJAwAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxSGIwDXAQABAAkJDxSGIwDXAQAAAA==.Gasaiyuno:BAABLgAECn8oAAMbAAgJFQ6SPQAKAQAbAAcJOgySPQAKAQANAAgJ8QerXQD/AAAAAA==.',
Ge='Geves:BAABLgAECn8VAAIXAAYJyBNyLgAqAQAXAAYJyBNyLgAqAQAAAA==.',
Gr='Grimmjob:BAAALgAECgEJAgAAAA==.Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgAECgEJAQAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAUJFAANADwXAA==.',
He='Hedgehog:BAAALgAECgcJCwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8bAAIKAAkJPRNCkgBOAQAKAAkJPRNCkgBOAQAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECggJDAAAAA==.Holyyoshi:BAABLgAECn8WAAIKAAgJCRGiVgDeAQAKAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8cAAIGAAkJhB18FQCkAgAGAAkJhB18FQCkAgAAAA==.',
Ja='Jab:BAACLgAFFH8OAAIOAAUJKwW4KACxAAAOAAUJKwW4KACxAAAuAAQKfyoAAg4ACAmwDzkkADEBAA4ACAmwDzkkADEBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMOAAkJ2hV4HABoAQAOAAgJPxh4HABoAQALAAcJkgjvuAAHAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwAOANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn80AAIVAAkJXiT4AgBAAwAVAAkJXiT4AgBAAwAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8wAAIcAAkJYhrtDQBaAgAcAAkJYhrtDQBaAgAAAA==.',
Jo='Joker:BAABLgAECn8dAAIJAAcJ4Ai9ngAEAQAJAAcJ4Ai9ngAEAQAAAA==.Jomama:BAABLgAECn8jAAIKAAkJKg7vZACmAQAKAAkJKg7vZACmAQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh/uFABIAgABAAkJNh/uFABIAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCgkJCQAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kegs:BAAALgAECgEJAQABLgAECgkJMQAKAKwlAA==.Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECgkJMAAcAGIaAA==.Kes:BAAALgAECgUJCgAAAA==.',
Kk='Kk:BAAALgAECgIJAgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAMAAAAAA==.',
Kr='Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJCgAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAMAAAAAA==.Leafygaga:BAABLgAECn8YAAIVAAgJDwb3BQDHAAAVAAgJDwb3BQDHAAAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECggJDQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgAECgMJAwABLgAECgkJIwAKACoOAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marie:BAAALgADCgcJBgAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJCAAAAA==.Meliôdas:BAAALgAECgEJCQAAAA==.Mendelson:BAAALgADCgEJAgABLgAECgUJCAAMAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAMAAAAAA==.Moo:BAAALgAECgYJBgAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAABLgAECn8cAAISAAcJ2AONcACZAAASAAcJ2AONcACZAAAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgkJCQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwABLgAECgkJGwAQAJILAA==.Mysteia:BAABLgAECn8nAAINAAkJpRxPEQCWAgANAAkJpRxPEQCWAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8XAAIdAAgJqBGaEgCNAQAdAAgJqBGaEgCNAQAAAA==.',
['Mø']='Mørdréd:BAAALgAECgEJAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAABLgAECn8VAAIeAAcJ0gzRFAAXAQAeAAcJ0gzRFAAXAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAUJGQAJAP8aAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMKAAYJRxWyngBBAQAKAAYJehSyngBBAQAfAAQJ0wcOMgCFAAABLgAFFAQJCQAZAAQGAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAQJCQAZAAQGAA==.',
Ni='Nihilist:BAABLgAECn8dAAIOAAkJwB2yEAAAAgAOAAkJwB2yEAAAAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAACLgAFFH8IAAITAAMJAhgSEwC/AAATAAMJAhgSEwC/AAAuAAQKf1UAAhMACQmKHwUBAKYCABMACQmKHwUBAKYCAAAA.',
No='Noblessyou:BAAALgADCgcJCAABLgAECgUJCAAMAAAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.Nurgle:BAAALgAECgMJBAAAAA==.',
Ob='Obamanationn:BAAALgAECgQJBAAAAA==.Obeejoowan:BAAALgAECgUJBgAAAA==.Obeewand:BAAALgAECgYJDAAAAA==.Obijuan:BAABLgAECn8mAAIJAAgJywZMfABHAQAJAAgJywZMfABHAQAAAA==.',
Ol='Oll:BAAALgADCgEJAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.Ondrex:BAAALgAECgMJAwAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn88AAMBAAgJEBXaAQC1AQABAAgJEBXaAQC1AQAgAAQJYgsGRwCuAAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIcAAgJ+SFuBwAOAwAcAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pa='Pallypocket:BAAALgADCgYJDwAAAA==.',
Pi='Pine:BAABLgAECn8YAAIFAAkJ7wuHMQCRAQAFAAkJ7wuHMQCRAQAAAA==.',
Pl='Plateguy:BAAALgAECgUJCQAAAA==.',
Po='Poxx:BAABLgAFFH8LAAIWAAQJ7R4eRQBdAQAWAAQJ7R4eRQBdAQABLgAFFAkJMgAXADwgAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJCgAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.Raymondnodle:BAAALgAECgEJAQAAAA==.',
Rh='Rhayvival:BAABLgAFFH8UAAQNAAUJPBfyHwBvAQANAAUJPBfyHwBvAQAbAAIJzRJ+MACCAAAcAAIJAQhXUABhAAAAAA==.Rhayvoke:BAABLgAECn8XAAQZAAcJyxc8HQDdAQAZAAcJkxc8HQDdAQAUAAMJ2gt1OgCWAAAYAAEJGRltOgBHAAABLgAFFAUJFAANADwXAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8KAAMbAAYJFReEEwAhAQAbAAUJoBqEEwAhAQANAAIJ/gkLUgBgAAABLgAFFAkJPwALAIwkAA==.Rossini:BAAALgADCgkJDwAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Rushs:BAAALgAECgQJBwABLgAECgUJCAAMAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8wAAIQAAkJyBo9FAAsAgAQAAkJyBo9FAAsAgAAAA==.Rynron:BAAALgAECgkJDgAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEwAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8jAAMPAAgJWhxYDwB6AgAPAAgJWhxYDwB6AgAQAAEJ9AUhlgAkAAAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgkJGwAQAJILAA==.',
Se='Sempiternal:BAACLgAFFH8gAAIFAAYJ7g/QFgBwAQAFAAYJ7g/QFgBwAQAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIKAAkJzxziNgAmAgAKAAkJzxziNgAmAgAAAA==.Shaunanigans:BAABLgAECn8dAAITAAkJphCBMgDpAQATAAkJphCBMgDpAQAAAA==.Shaunsdh:BAAALgAECgQJBAABLgAECgkJHQATAKYQAA==.Shaunwick:BAAALgAECgUJBAABLgAECgkJHQATAKYQAA==.Shego:BAACLgAFFH8HAAIRAAMJxiQtDgAoAQARAAMJxiQtDgAoAQAuAAQKfyMABBEACQn8IHAFAF8CAAsABwk6ILgxAHECABEABwkrI3AFAF8CAA4AAgkdItFLAGAAAAEuAAUUBAkGAAYAMw8A.Sheltered:BAABLgAECn8xAAIKAAkJrCVWBQBKAwAKAAkJrCVWBQBKAwAAAA==.',
Si='Sinadora:BAAALgAECgUJCAAAAA==.Sinakra:BAABLgAECn8iAAIKAAkJmw/QagCZAQAKAAkJmw/QagCZAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8yAAIXAAkJPCCMAADwAgAXAAkJPCCMAADwAgAuAAQKfygAAhcACQniJQACAJcDABcACQniJQACAJcDAAAA.',
Sp='Spirits:BAAALgAECgQJBAABLgAFFAUJFQAFAI0bAA==.Spritz:BAABLgAECn8aAAIJAAgJRA6sZAB7AQAJAAgJRA6sZAB7AQAAAA==.',
St='Stampede:BAABLgAECn8WAAIBAAYJQwMqfwB5AAABAAYJQwMqfwB5AAAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCAAAAA==.Straya:BAABLgAECn8hAAMTAAkJDhXEJAAyAgATAAkJDhXEJAAyAgASAAEJPg1XrQAqAAAAAA==.',
Su='Subito:BAAALgADCgkJDwAAAA==.',
Ta='Taburiel:BAAALgADCgcJBwAAAA==.Taedwar:BAAALgADCgYJBgAAAA==.Tahirrah:BAABLgAECn8eAAIJAAkJ7RUZOgD2AQAJAAkJ7RUZOgD2AQAAAA==.Talindra:BAABLgAECn8cAAIOAAkJRQaNLAD3AAAOAAkJRQaNLAD3AAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9nAAMEAAkJJBOYJQAgAgAEAAkJJBOYJQAgAgAhAAkJLBWhAQA+AQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJCAAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8VAAIFAAUJjRtUEgCfAQAFAAUJjRtUEgCfAQAuAAQKfzMAAwUACQnqHIsLANQCAAUACQnqHIsLANQCAAoABQkOC1v8ALwAAAAA.',
Tm='Tmnt:BAABLgAECn8oAAINAAkJbgv8UAArAQANAAkJbgv8UAArAQAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQTAAkJ1x3+bwAMAQATAAQJdBf+bwAMAQASAAcJvg/7TQD+AAAdAAUJPgkXLQCQAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAABLgAECn8UAAMRAAcJTRISEwBJAQARAAcJCxISEwBJAQAOAAQJKxMwNgC+AAAAAA==.',
Ts='Tsilihin:BAAALgAECgYJCAAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgANAA0eAA==.Tsurenity:BAACLgAFFH8GAAINAAIJDR6uDgCyAAANAAIJDR6uDgCyAAAuAAQKfxkAAg0ACAm+IjEEACwDAA0ACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgAECgEJAQAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAABLgAECn8XAAQhAAUJnghQNwB+AAAhAAQJWAdQNwB+AAAiAAMJ5QdPXABWAAAEAAMJbgOuwgBDAAABLgAFFAIJBwANAK8GAA==.',
Uk='Uki:BAAALgADCgQJBAAAAA==.',
Ur='Urbanfries:BAABLgAFFH8LAAMEAAYJZAg1JAA4AQAEAAYJZAg1JAA4AQAVAAMJcQGZSABSAAABLgAFFAUJFwATAIAfAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJUAANABggAA==.Varr:BAABLgAECn8UAAMCAAYJdh+0FwDGAQACAAYJdh+0FwDGAQAjAAIJIh4rHgCqAAAAAA==.Vayeda:BAABLgAECn8kAAIWAAkJ7iJLFADgAgAWAAkJ7iJLFADgAgAAAA==.',
Ve='Venderic:BAAALgAECgMJAwAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAZAAQGAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Xe='Xetz:BAABLgAECn8fAAMQAAkJ9gb+OgAmAQAQAAkJ9gb+OgAmAQAkAAEJawGKiQAkAAAAAA==.Xezar:BAACLgAFFH84AAQkAAgJuxo7BQAPAgAPAAgJJBcLCwBuAgAkAAYJYR47BQAPAgAQAAQJAAnHDADeAAAuAAQKfycABBAACQk5GzEPAJECABAACQk5GzEPAJECACQABwlrHpoWACcCAA8AAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn82AAMWAAkJ5QvIegCDAQAWAAkJ5QvIegCDAQAlAAQJpwNoFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAACLgAFFH8GAAIPAAMJTgjKNgCvAAAPAAMJTgjKNgCvAAAuAAQKfycAAg8ACAkiFhQdAOUBAA8ACAkiFhQdAOUBAAAA.',
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
