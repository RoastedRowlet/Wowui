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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Monk-Mistweaver','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Druid-Balance','Mage-Frost','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Monk-Windwalker','Rogue-Subtlety','Monk-Brewmaster','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Druid-Feral','Druid-Guardian','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abzu:BAAALgAECgEJAgAAAA==.',
Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Alkuron:BAAALgAECgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8iAAMCAAkJHx+FBwC5AgACAAkJHx+FBwC5AgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhpAIQA9AgAEAAgJyhpAIQA9AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn9AAAIFAAkJAh5dCgDmAgAFAAkJAh5dCgDmAgAAAA==.Amoralibash:BAABLgAECn8nAAQGAAgJzRS+WACTAQAGAAgJzRS+WACTAQAHAAMJ4g3kKgBvAAAIAAIJZwiNQgApAAAAAA==.Amorianstus:BAAALgAECgQJBAAAAA==.',
An='Anguskhan:BAAALgAECgYJDwAAAA==.Anhafel:BAABLgAECn8lAAIDAAYJmRaMfAAnAQADAAYJmRaMfAAnAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAABLgAECn8WAAIJAAkJkSAcAwDeAgAJAAkJkSAcAwDeAgAAAA==.',
Ap='Apocalipze:BAAALgADCggJJAAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Archdruid:BAAALgAFFAEJAQAAAA==.Arcsisu:BAAALgAECgkJCAAAAA==.Ares:BAAALgAECgEJAQABLgAFFAcJJAAKABIUAA==.Arileous:BAABLgAECn8sAAIBAAYJQw7ODwDVAAABAAYJQw7ODwDVAAAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arrdyn:BAAALgAECgUJBwAAAA==.Artamis:BAAALgAECgEJAQAAAA==.Arthan:BAAALgADCgUJBQAAAA==.Artheen:BAAALgAECgcJBwAAAA==.',
As='Askorom:BAAALgADCgEJAQAAAA==.Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAJAJsPAA==.Aspp:BAABLgAECn8lAAILAAkJ4hQINAAuAgALAAkJ4hQINAAuAgAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.Austin:BAAALgAECgUJCgAAAA==.',
Ay='Ayeamanoob:BAAALgADCgEJAgABLgAECgYJCgAMAAAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.Bar:BAAALgAFFAMJAwAAAA==.Bault:BAAALgAECgYJBgABLgAFFAMJAwAMAAAAAA==.',
Be='Bearwitme:BAAALgADCgEJAQAAAA==.',
Bh='Bhalen:BAAALgADCgYJBgAAAA==.',
Bi='Bigmagic:BAAALgAECgEJBgAAAA==.Bigmoose:BAAALgAECgEJAQAAAA==.Bijou:BAAALgAECgEJAQAAAA==.Billzdaddy:BAAALgADCgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgcJDAAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBQAAAA==.Britnysteers:BAAALgADCgkJEAAAAA==.Brojin:BAAALgAECgEJAwAAAA==.Brungar:BAAALgAECgkJBAAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8fAAINAAcJAxt3HgAmAgANAAcJAxt3HgAmAgAAAA==.Bucksdk:BAABLgAECn8aAAMOAAgJKBKWJgAfAQAOAAcJYhSWJgAfAQALAAIJQgOdXgFEAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECggJGgAOACgSAA==.Bugsquasher:BAAALgADCgEJAQAAAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgAECgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalor:BAAALgAECgUJBgABLgAECgkJUAAPAOwfAA==.Cyrandalord:BAABLgAECn8WAAMPAAYJvBocBgCtAQAPAAYJvBocBgCtAQAQAAYJLgR/XgCdAAABLgAECgkJUAAPAOwfAA==.Cyrandalorr:BAABLgAECn9QAAMPAAkJ7B9+AQDfAgAPAAkJ7B9+AQDfAgAQAAUJEQa6QwDeAAAAAA==.Cyrandalör:BAAALgADCgUJBQABLgAECgkJUAAPAOwfAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAMAAAAAA==.Dardianil:BAAALgAECgYJBgABLgAECggJJwAGAM0UAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dasfrog:BAAALgADCgEJAQAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ9IKwC2AQAFAAkJYQ9IKwC2AQABLgABCgcJCQAMAAAAAA==.Dawnrise:BAAALgAECgMJAwAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH9fAAQRAAkJciYxAABEAwARAAkJzCIxAABEAwALAAgJfCWQAAB0AgAOAAIJgRugOQBQAAAuAAQKf0QABAsACQntJgYAAKwDAAsACQntJgYAAKwDAA4ABwkzJS0GAE8BABEABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIGAAkJRh7cIABgAgAGAAkJRh7cIABgAgABLgAECgkJMQAJAKwlAA==.Deitha:BAAALgAECgUJCgAAAA==.Demonbane:BAABLgAECn8wAAMCAAkJfxwiCwB0AgACAAkJfxwiCwB0AgADAAcJXAoAkQD+AAAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMSAAgJ2g8RXQDPAAASAAUJaQYRXQDPAAATAAYJJRHpmgCdAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8aAAIUAAgJWRf3DQDvAQAUAAgJWRf3DQDvAQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJEwAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAMAAAAAA==.',
Dy='Dyrillin:BAAALgAECgYJCAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
Ea='Earl:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgkJEQAAAA==.Ellgar:BAAALgAECgUJBgABLgAECgkJGAAVAGQYAA==.',
Em='Emerigosa:BAAALgAECgQJBAAAAA==.',
En='Endymion:BAABLgAECn8cAAIFAAgJAhUOKADLAQAFAAgJAhUOKADLAQAAAA==.',
Er='Erazar:BAAALgADCgIJAgABLgAECgkJUAAPAOwfAA==.',
Et='Eternity:BAACLgAFFH8kAAIKAAcJEhTBGwBDAQAKAAcJEhTBGwBDAQAuAAQKfy8AAgoACQkqIisMAOACAAoACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAATAFESAA==.Facetheflame:BAABLgAECn8ZAAIWAAcJABUudgCNAQAWAAcJABUudgCNAQABLgAECgkJFAATAFESAA==.Facethegem:BAABLgAECn8UAAMTAAkJURLeWQBQAQATAAYJ6hHeWQBQAQASAAYJGRKpSwAGAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAATAFESAA==.Facethezoom:BAABLgAECn8oAAIDAAkJrxzEEwCkAgADAAkJrxzEEwCkAgABLgAECgkJFAATAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAMAAAAAA==.',
Fe='Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQUAAkJNwrUFgBiAQAUAAkJNwrUFgBiAQAXAAIJAg5SHQBjAAAYAAIJ4AsKhABVAAAAAA==.Fiztweaver:BAAALgAECgEJAQAAAA==.Fizwithagun:BAAALgAECgEJAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.Forloyn:BAAALgADCgIJAgAAAA==.Foxdaloc:BAAALgAECgcJBwAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIWAAgJvAbrrQAlAQAWAAgJvAbrrQAlAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRZqIwDYAQABAAkJVRZqIwDYAQAZAAEJTwksVgArAAAAAA==.',
Ga='Galairn:BAAALgAECgYJCwAAAA==.Gallin:BAAALgADCggJDgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Ganicus:BAAALgAECgUJBwAAAA==.Gargoyle:BAAALgADCgMJAwAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxSGIwDXAQABAAkJDxSGIwDXAQAAAA==.Gasaiyuno:BAABLgAECn8oAAMaAAgJFQ6SPQAKAQAaAAcJOgySPQAKAQANAAgJ8QerXQD/AAAAAA==.',
Ge='Geves:BAABLgAECn8VAAIbAAYJyBNyLgAqAQAbAAYJyBNyLgAqAQAAAA==.',
Gl='Glinda:BAAALgADCgUJBQABLgAECgYJDwAMAAAAAA==.',
Gr='Grimmjob:BAAALgAECgEJAwAAAA==.Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgAECgEJAQAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAUJFAANADwXAA==.',
He='Hedgehog:BAAALgAECgcJCwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8bAAIJAAkJOxNCkgBOAQAJAAkJOxNCkgBOAQAAAA==.Hellraid:BAABLgAECn8dAAIVAAgJBBmXAwD6AQAVAAgJBBmXAwD6AQABLgAECggJJwAGAM0UAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECggJDAAAAA==.Holyyoshi:BAABLgAECn8WAAIJAAgJCRGiVgDeAQAJAAgJCRGiVgDeAQAAAA==.',
Hu='Humblépié:BAAALgADCgEJAQAAAA==.',
Hy='Hydrosavior:BAAALgAECgEJAgAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgIJAgAAAA==.',
In='Initalog:BAAALgAECgEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQABLgAECgkJHAAGAIQdAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8cAAIGAAkJhB18FQCkAgAGAAkJhB18FQCkAgAAAA==.Izumi:BAAALgAECgYJBgAAAA==.',
Ja='Jab:BAACLgAFFH8WAAIOAAYJ8wWWEgDRAAAOAAYJ8wWWEgDRAAAuAAQKfyoAAg4ACAmwDzkkADEBAA4ACAmwDzkkADEBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMOAAkJ2hV4HABoAQAOAAgJPxh4HABoAQALAAcJkgjvuAAHAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwAOANoVAA==.',
Je='Jennycraig:BAAALgADCgEJAQAAAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn80AAIVAAkJXiT4AgBAAwAVAAkJXiT4AgBAAwAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8wAAIcAAkJYhrtDQBaAgAcAAkJYhrtDQBaAgAAAA==.',
Jo='Joker:BAABLgAECn8gAAIKAAcJPQuWLAChAAAKAAcJPQuWLAChAAAAAA==.Jomama:BAABLgAECn8jAAIJAAkJKg7vZACmAQAJAAkJKg7vZACmAQAAAA==.Jonhee:BAAALgADCgIJAgAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh/uFABIAgABAAkJNh/uFABIAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Kaitnahar:BAAALgAECgUJBgABLgAECggJJwAGAM0UAA==.Karasendreth:BAAALgADCgkJDAAAAA==.Katiperry:BAAALgAECgYJDwAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kegs:BAAALgAECgEJAQABLgAECgkJMQAJAKwlAA==.Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgAECgQJBAABLgAECgkJMAAcAGIaAA==.Kes:BAAALgAECgUJCgAAAA==.',
Kh='Khaiden:BAAALgADCgEJAQAAAA==.',
Kk='Kk:BAAALgAECgIJAgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAMAAAAAA==.',
Kr='Kraio:BAAALgAECgUJBwAAAA==.Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJCwAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAMAAAAAA==.Leafygaga:BAABLgAECn8bAAIVAAkJnweGDQDgAAAVAAkJnweGDQDgAAAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECggJDQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgAECgMJAwABLgAECgkJIwAJACoOAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Maagnuss:BAAALgADCgYJBgAAAA==.Magetank:BAAALgAECgkJCQAAAA==.Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgkJEAAAAA==.Marie:BAAALgADCgcJBgAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJCAAAAA==.Meliôdas:BAAALgAECgMJDQAAAA==.Mendelson:BAAALgAECgEJAQABLgAECgYJCgAMAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAMAAAAAA==.Moo:BAAALgAECgYJEwAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAABLgAECn8cAAISAAcJ2AONcACZAAASAAcJ2AONcACZAAAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgkJCwAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Myrcy:BAAALgAECgUJBQAAAA==.Mysteer:BAAALgAECgcJDwABLgAECgkJGwAQAJILAA==.Mysteia:BAABLgAECn8nAAINAAkJmxxPEQCWAgANAAkJmxxPEQCWAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8XAAIdAAgJqBGaEgCNAQAdAAgJqBGaEgCNAQAAAA==.',
['Mø']='Mørdréd:BAAALgAECgEJAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAABLgAECn8VAAIeAAcJ0gzRFAAXAQAeAAcJ0gzRFAAXAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAcJJAAKABIUAA==.',
Ne='Necrobijuan:BAAALgAECgIJAgAAAA==.Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMJAAYJRxWyngBBAQAJAAYJehSyngBBAQAfAAQJ0wcOMgCFAAABLgAFFAQJCQAYAAQGAA==.Neodragoonz:BAAALgADCgkJDAABLgAFFAQJCQAYAAQGAA==.',
Ni='Nihilist:BAABLgAECn8dAAIOAAkJwB2yEAAAAgAOAAkJwB2yEAAAAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAACLgAFFH8VAAITAAQJFxwMEwA3AQATAAQJFxwMEwA3AQAuAAQKf2UAAhMACQkNITECANsCABMACQkNITECANsCAAAA.',
No='Noblessyou:BAAALgAECgYJCgAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.Nurgle:BAAALgAECgMJBAAAAA==.',
Ob='Obamanationn:BAAALgAECgQJBAAAAA==.Obeejoowan:BAAALgAECgUJBgAAAA==.Obeewand:BAAALgAECgYJEQAAAA==.Obijuan:BAABLgAECn8nAAIKAAkJFgdMfABHAQAKAAkJFgdMfABHAQAAAA==.',
Ol='Oll:BAAALgADCgEJAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.Ondrex:BAAALgAECgYJCgAAAA==.',
Or='Orientote:BAAALgAECgQJBAAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn9QAAMBAAkJrhSUAwABAgABAAkJrhSUAwABAgAgAAQJYgsGRwCuAAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIcAAgJ+SFuBwAOAwAcAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pa='Pallypocket:BAAALgADCgYJEgAAAA==.',
Pi='Pine:BAABLgAECn8YAAIFAAkJ7wuHMQCRAQAFAAkJ7wuHMQCRAQAAAA==.Pippi:BAAALgADCgYJBgAAAA==.',
Pl='Plateguy:BAAALgAECggJDQAAAA==.',
Po='Poxx:BAABLgAFFH8LAAIWAAQJ7R4eRQBdAQAWAAQJ7R4eRQBdAQABLgAFFAkJRAAbAHwhAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.Quinci:BAAALgAECgEJAQAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJCgAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.Raymondnodle:BAAALgAECgQJBAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8UAAQNAAUJPBfyHwBvAQANAAUJPBfyHwBvAQAaAAIJzRJ+MACCAAAcAAIJAQhXUABhAAAAAA==.Rhayvoke:BAABLgAECn8XAAQYAAcJyxc8HQDdAQAYAAcJkxc8HQDdAQAUAAMJ2gt1OgCWAAAXAAEJGRltOgBHAAABLgAFFAUJFAANADwXAA==.',
Ri='Rills:BAAALgAECgQJBQAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8MAAMaAAYJFReEEwAhAQAaAAUJoBqEEwAhAQANAAIJvwoLUgBgAAABLgAFFAkJXwARAHImAA==.Rossini:BAAALgADCgkJEgAAAA==.',
Ru='Rueittrebeck:BAAALgADCgYJBgABLgAECgYJCgAMAAAAAA==.Rush:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Rushs:BAAALgAECgUJEQABLgAECgYJCgAMAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8wAAIQAAkJyBo9FAAsAgAQAAkJyBo9FAAsAgAAAA==.Rynron:BAAALgAECgkJDgAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEwAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8jAAMPAAgJWhxYDwB6AgAPAAgJWhxYDwB6AgAQAAEJ9AUhlgAkAAAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgkJGwAQAJILAA==.',
Sb='Sbawar:BAAALgAECgEJAQAAAA==.',
Sc='Schmitty:BAAALgAECgEJAQAAAA==.',
Se='Sempiternal:BAACLgAFFH8mAAIFAAcJ8Q3QFgBwAQAFAAcJ8Q3QFgBwAQAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIJAAkJzxziNgAmAgAJAAkJzxziNgAmAgAAAA==.Shaunanigans:BAABLgAECn8dAAITAAkJphCBMgDpAQATAAkJphCBMgDpAQAAAA==.Shaunsdh:BAAALgAECgQJBAABLgAECgkJHQATAKYQAA==.Shaunwick:BAAALgAECgUJBAABLgAECgkJHQATAKYQAA==.Shego:BAACLgAFFH8HAAIRAAMJxiQtDgAoAQARAAMJxiQtDgAoAQAuAAQKfyMABBEACQn8IHAFAF8CAAsABwk6ILgxAHECABEABwkrI3AFAF8CAA4AAgkdItFLAGAAAAEuAAUUBAkGAAYAMw8A.Sheltered:BAABLgAECn8xAAIJAAkJrCVWBQBKAwAJAAkJrCVWBQBKAwAAAA==.',
Si='Sinadora:BAAALgAECgUJCAAAAA==.Sinakra:BAABLgAECn8iAAIJAAkJmw/QagCZAQAJAAkJmw/QagCZAQAAAA==.',
Sk='Skyslaughter:BAAALgAECgEJAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slapdh:BAACLgAFFH8PAAIDAAcJYxWiGABUAQADAAcJYxWiGABUAQAuAAQKfx0AAwMACQkdGU0uAA4CAAMABwmVIE0uAA4CAAIACQmXA0MqAHMBAAEuAAUUCQlEABsAfCEA.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH9EAAIbAAkJfCHHAQDkAgAbAAkJfCHHAQDkAgAuAAQKfygAAhsACQniJQACAJcDABsACQniJQACAJcDAAAA.',
Sp='Spirits:BAAALgAFFAIJAwABLgAFFAYJGwAFACsYAA==.Spritz:BAABLgAECn8oAAIKAAkJixVoBwAaAgAKAAkJixVoBwAaAgAAAA==.',
St='Stampede:BAABLgAECn8XAAIBAAYJlQMqfwB5AAABAAYJlQMqfwB5AAAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stevebills:BAAALgAECgEJAQAAAA==.Stice:BAAALgAECgEJAQAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCQAAAA==.Straya:BAABLgAECn8hAAMTAAkJDhXEJAAyAgATAAkJDhXEJAAyAgASAAEJPg1XrQAqAAAAAA==.',
Su='Subito:BAAALgADCgkJEgAAAA==.Sukittrebeck:BAAALgADCgEJAQABLgAECgYJCgAMAAAAAA==.',
['Sï']='Sïrloinalot:BAAALgADCgIJBAABLgAECgkJKQAWAGUOAA==.',
Ta='Taburiel:BAAALgADCgcJCQAAAA==.Taedwar:BAAALgADCgYJBgAAAA==.Tahirrah:BAABLgAECn8eAAIKAAkJ7RUZOgD2AQAKAAkJ7RUZOgD2AQAAAA==.Talindra:BAABLgAECn8cAAIOAAkJRQaNLAD3AAAOAAkJRQaNLAD3AAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9nAAMEAAkJJBOYJQAgAgAEAAkJJBOYJQAgAgAhAAkJNxWqDQDbAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJDgABLgAECgYJCgAMAAAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8bAAIFAAYJKxhUEgCfAQAFAAYJKxhUEgCfAQAuAAQKfzUAAwUACQk9H4sLANQCAAUACQk9H4sLANQCAAkABQkOC1v8ALwAAAAA.',
Tm='Tmnt:BAABLgAECn8oAAINAAkJbAv8UAArAQANAAkJbAv8UAArAQAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQTAAkJ1x3+bwAMAQATAAQJdBf+bwAMAQASAAcJvg/7TQD+AAAdAAUJPgkXLQCQAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trickze:BAAALgAECgUJBQAAAA==.Trundle:BAABLgAECn8UAAMRAAcJTRISEwBJAQARAAcJCxISEwBJAQAOAAQJKxMwNgC+AAAAAA==.',
Ts='Tsilihin:BAAALgAECgYJCAAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgANAA0eAA==.Tsurenity:BAACLgAFFH8GAAINAAIJDR6uDgCyAAANAAIJDR6uDgCyAAAuAAQKfxkAAg0ACAm+IjEEACwDAA0ACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgAECgEJAQAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAABLgAECn8XAAQhAAUJnghQNwB+AAAhAAQJWAdQNwB+AAAiAAMJ5QdPXABWAAAEAAMJbgOuwgBDAAABLgAFFAMJCAANAAQOAA==.',
Uk='Uki:BAAALgADCgUJCAAAAA==.',
Ur='Urbanfries:BAABLgAFFH8LAAMEAAYJZAg1JAA4AQAEAAYJZAg1JAA4AQAVAAMJcQGZSABSAAABLgAFFAcJGQATAHkbAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJZgANAJwgAA==.Varr:BAABLgAECn8XAAMCAAkJOhxmBQCKAQACAAkJOhxmBQCKAQAjAAIJIh4rHgCqAAAAAA==.Vayeda:BAABLgAECn8kAAIWAAkJ7iJLFADgAgAWAAkJ7iJLFADgAgAAAA==.',
Ve='Venderic:BAAALgAECgMJAwAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAYAAQGAA==.',
Vo='Voidpetal:BAAALgAECgEJAQAAAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Wo='Worramotreum:BAAALgAECgQJBAAAAA==.',
Xe='Xetz:BAABLgAECn8fAAMQAAkJ9gb+OgAmAQAQAAkJ9gb+OgAmAQAkAAEJawGKiQAkAAAAAA==.Xezar:BAACLgAFFH86AAQkAAkJtRo7BQAPAgAPAAkJhBcLCwBuAgAkAAYJYR47BQAPAgAQAAQJAAnHDADeAAAuAAQKfycABBAACQk5GzEPAJECABAACQk5GzEPAJECACQABwlrHpoWACcCAA8AAwmXH8oyAAwBAAAA.',
Xn='Xnobodie:BAAALgADCgIJAgAAAA==.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn82AAMWAAkJ5QvIegCDAQAWAAkJ5QvIegCDAQAlAAQJpwNoFQBxAAAAAA==.',
Yo='Yogi:BAAALgADCgkJCQAAAA==.Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAACLgAFFH8GAAIPAAMJTgjKNgCvAAAPAAMJTgjKNgCvAAAuAAQKfycAAg8ACAkiFhQdAOUBAA8ACAkiFhQdAOUBAAAA.',
Za='Zarigar:BAAALgADCgkJEgAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zedan:BAAALgAECgUJBQAAAA==.Zera:BAAALgAECgEJAQABLgAFFAMJAwAMAAAAAA==.Zerin:BAAALgAECgEJAQABLgAECgkJMQAJAKwlAA==.Zeroh:BAAALgAECgYJDQAAAA==.',
Zi='Zigzagger:BAAALgAECgQJBgAAAA==.',
Zn='Zna:BAAALgAECgUJEAAAAA==.',
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
