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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Priest-Discipline','Priest-Shadow','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','Unknown-Unknown','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Druid-Balance','Mage-Frost','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Monk-Windwalker','Rogue-Subtlety','Monk-Brewmaster','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Druid-Feral','Druid-Guardian','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abzu:BAAALgAECgEJAgAAAA==.',
Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Alkuron:BAAALgAECgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8iAAMCAAkJHx+FBwC5AgACAAkJHx+FBwC5AgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhpAIQA9AgAEAAgJyhpAIQA9AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn9AAAIFAAkJAh5dCgDmAgAFAAkJAh5dCgDmAgAAAA==.Amaraj:BAABLgAECn8jAAMGAAgJWhxYDwB6AgAGAAgJWhxYDwB6AgAHAAEJ9AUhlgAkAAAAAA==.Amoralibash:BAABLgAECn8nAAQIAAgJzRS+WACTAQAIAAgJzRS+WACTAQAJAAMJ4g3kKgBvAAAKAAIJZwiNQgApAAAAAA==.Amorianstus:BAAALgAECgQJBAAAAA==.',
An='Anguskhan:BAAALgAECgYJDwAAAA==.Anhafel:BAABLgAECn8lAAIDAAYJmRaMfAAnAQADAAYJmRaMfAAnAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAABLgAECn8WAAILAAkJkSAhAwDeAgALAAkJkSAhAwDeAgAAAA==.',
Ap='Apocalipze:BAAALgADCggJJAAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Archdruid:BAAALgAFFAEJAQAAAA==.Arcsisu:BAAALgAECgkJCAAAAA==.Ares:BAAALgAECgEJAQABLgAFFAcJJAAMABIUAA==.Arileous:BAABLgAECn8sAAIBAAYJQw7YDwDVAAABAAYJQw7YDwDVAAAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arrdyn:BAAALgAECgUJBwAAAA==.Artamis:BAAALgAECgEJAQAAAA==.Arthan:BAAALgADCgUJBQAAAA==.Artheen:BAAALgAECgcJBwAAAA==.',
As='Askorom:BAAALgADCgEJAQAAAA==.Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgALAJsPAA==.Aspp:BAABLgAECn8lAAINAAkJ4hQINAAuAgANAAkJ4hQINAAuAgAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.Austin:BAAALgAECgUJCgAAAA==.',
Ay='Ayeamanoob:BAAALgADCgEJAgABLgAECgYJCgAOAAAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.Bar:BAAALgAFFAMJAwAAAA==.Bault:BAAALgAECgYJBgABLgAFFAMJAwAOAAAAAA==.',
Be='Bearwitme:BAAALgADCgEJAQAAAA==.',
Bh='Bhalen:BAAALgADCgYJBgAAAA==.',
Bi='Bigmagic:BAAALgAECgEJBgAAAA==.Bigmoose:BAAALgAECgEJAQAAAA==.Bijou:BAAALgAECgEJAQAAAA==.Billzdaddy:BAAALgADCgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgcJDAAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBQAAAA==.Britnysteers:BAAALgADCgkJEAAAAA==.Brojin:BAAALgAECgEJAwAAAA==.Brungar:BAAALgAECgkJBAAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8fAAIPAAcJAxt3HgAmAgAPAAcJAxt3HgAmAgAAAA==.Bucksdk:BAABLgAECn8aAAMQAAgJKBKWJgAfAQAQAAcJYhSWJgAfAQANAAIJQgOdXgFEAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECggJGgAQACgSAA==.Bugsquasher:BAAALgADCgEJAQAAAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAOAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgAECgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalor:BAAALgAECgUJBgABLgAECgkJUAAGAOwfAA==.Cyrandalord:BAABLgAECn8WAAMGAAYJvBonBgCtAQAGAAYJvBonBgCtAQAHAAYJLgR/XgCdAAABLgAECgkJUAAGAOwfAA==.Cyrandalorr:BAABLgAECn9QAAMGAAkJ7B+BAQDeAgAGAAkJ7B+BAQDeAgAHAAUJEQa6QwDeAAAAAA==.Cyrandalör:BAAALgADCgUJBQABLgAECgkJUAAGAOwfAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAOAAAAAA==.Dardianil:BAAALgAECgYJBgABLgAECggJJwAIAM0UAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dasfrog:BAAALgADCgEJAQAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ9IKwC2AQAFAAkJYQ9IKwC2AQABLgABCgcJCQAOAAAAAA==.Dawnrise:BAAALgAECgMJAwAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH9fAAQRAAkJciYyAABDAwARAAkJzCIyAABDAwANAAgJfCWQAAB0AgAQAAIJgRugOQBQAAAuAAQKf0QABA0ACQntJgYAAKwDAA0ACQntJgYAAKwDABAABwkzJTYGAE8BABEABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIIAAkJRh7cIABgAgAIAAkJRh7cIABgAgABLgAECgkJMQALAKwlAA==.Deitha:BAAALgAECgUJCgAAAA==.Demonbane:BAABLgAECn8wAAMCAAkJfxwiCwB0AgACAAkJfxwiCwB0AgADAAcJXAoAkQD+AAAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMSAAgJ2g8RXQDPAAASAAUJaQYRXQDPAAATAAYJJRHpmgCdAAAAAA==.',
Do='Doci:BAABLgAECn8YAAIFAAkJ7wuHMQCRAQAFAAkJ7wuHMQCRAQAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8aAAIUAAgJWRf3DQDvAQAUAAgJWRf3DQDvAQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJEwAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAOAAAAAA==.',
Dy='Dyrillin:BAAALgAECgYJCAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
Ea='Earl:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgkJEQAAAA==.Ellgar:BAAALgAECgUJBgABLgAECgkJGAAVAGQYAA==.',
Em='Emerigosa:BAAALgAECgQJBAAAAA==.',
En='Endymion:BAABLgAECn8cAAIFAAgJAhUOKADLAQAFAAgJAhUOKADLAQAAAA==.',
Er='Erazar:BAAALgADCgIJAgABLgAECgkJUAAGAOwfAA==.',
Et='Eternity:BAACLgAFFH8kAAIMAAcJEhS/GwBDAQAMAAcJEhS/GwBDAQAuAAQKfy8AAgwACQkqIisMAOACAAwACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAATAFESAA==.Facetheflame:BAABLgAECn8ZAAIWAAcJABUudgCNAQAWAAcJABUudgCNAQABLgAECgkJFAATAFESAA==.Facethegem:BAABLgAECn8UAAMTAAkJURLeWQBQAQATAAYJ6hHeWQBQAQASAAYJGRKpSwAGAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAATAFESAA==.Facethezoom:BAABLgAECn8oAAIDAAkJrxzEEwCkAgADAAkJrxzEEwCkAgABLgAECgkJFAATAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAOAAAAAA==.',
Fe='Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQUAAkJNwrUFgBiAQAUAAkJNwrUFgBiAQAXAAIJAg5SHQBjAAAYAAIJ4AsKhABVAAAAAA==.Fiztweaver:BAAALgAECgEJAQABLgAECgkJKAAUADcKAA==.Fizwithagun:BAAALgAECgEJAQABLgAECgkJKAAUADcKAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.Forloyn:BAAALgADCgIJAgAAAA==.Foxdaloc:BAAALgAECgcJBwAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAOAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIWAAgJvAbrrQAlAQAWAAgJvAbrrQAlAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRZqIwDYAQABAAkJVRZqIwDYAQAZAAEJTwksVgArAAAAAA==.',
Ga='Galairn:BAAALgAECgYJCwAAAA==.Gallin:BAAALgADCggJDgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Ganicus:BAAALgAECgUJBwAAAA==.Gargoyle:BAAALgADCgMJAwAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxSGIwDXAQABAAkJDxSGIwDXAQAAAA==.Gasaiyuno:BAABLgAECn8oAAMaAAgJFQ6SPQAKAQAaAAcJOgySPQAKAQAPAAgJ8QerXQD/AAAAAA==.',
Ge='Geves:BAABLgAECn8VAAIbAAYJyBNyLgAqAQAbAAYJyBNyLgAqAQAAAA==.',
Gl='Glinda:BAAALgADCgUJBQABLgAECgYJDwAOAAAAAA==.',
Gr='Grimmjob:BAAALgAECgEJAwAAAA==.Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgAECgEJAQAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAUJFAAPADwXAA==.',
He='Hedgehog:BAAALgAECgcJCwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8bAAILAAkJOxNCkgBOAQALAAkJOxNCkgBOAQAAAA==.Hellraid:BAABLgAECn8dAAIVAAgJBBmbAwD6AQAVAAgJBBmbAwD6AQABLgAECggJJwAIAM0UAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECggJDAAAAA==.Holyyoshi:BAABLgAECn8WAAILAAgJCRGiVgDeAQALAAgJCRGiVgDeAQAAAA==.',
Hu='Humblépié:BAAALgADCgEJAQAAAA==.',
Hy='Hydrosavior:BAAALgAECgEJAgAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgIJAgAAAA==.',
In='Initalog:BAAALgAECggJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAOAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQABLgAECgkJHAAIAIQdAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8cAAIIAAkJhB18FQCkAgAIAAkJhB18FQCkAgAAAA==.Izumi:BAAALgAECgYJBgAAAA==.',
Ja='Jab:BAACLgAFFH8WAAIQAAYJ8wWdEgDRAAAQAAYJ8wWdEgDRAAAuAAQKfyoAAhAACAmwDzkkADEBABAACAmwDzkkADEBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMQAAkJ2hV4HABoAQAQAAgJPxh4HABoAQANAAcJkgjvuAAHAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwAQANoVAA==.',
Je='Jennycraig:BAAALgADCgEJAQAAAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn80AAIVAAkJXiT4AgBAAwAVAAkJXiT4AgBAAwAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8wAAIcAAkJYhrtDQBaAgAcAAkJYhrtDQBaAgAAAA==.',
Jo='Joker:BAABLgAECn8gAAIMAAcJPQvDLAChAAAMAAcJPQvDLAChAAAAAA==.Jomama:BAABLgAECn8jAAILAAkJKg7vZACmAQALAAkJKg7vZACmAQAAAA==.Jonhee:BAAALgADCgIJAgAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh/uFABIAgABAAkJNh/uFABIAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Kaitnahar:BAAALgAECgUJBgABLgAECggJJwAIAM0UAA==.Karasendreth:BAAALgADCgkJDAAAAA==.Katiperry:BAAALgAECgYJDwAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kegs:BAAALgAECgEJAQABLgAECgkJMQALAKwlAA==.Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgAECgQJBAABLgAECgkJMAAcAGIaAA==.Kes:BAAALgAECgUJCgAAAA==.',
Kh='Khaiden:BAAALgADCgEJAQAAAA==.',
Kk='Kk:BAAALgAECgIJAgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAOAAAAAA==.',
Kr='Kraio:BAAALgAECgUJBwAAAA==.Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJCwAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAOAAAAAA==.Leafygaga:BAABLgAECn8bAAIVAAkJnweVDQDgAAAVAAkJnweVDQDgAAAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECggJDQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgAECgMJAwABLgAECgkJIwALACoOAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Maagnuss:BAAALgADCgYJBgAAAA==.Magetank:BAAALgAECgkJCQAAAA==.Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgkJEAAAAA==.Marie:BAAALgADCgcJBgAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJCAAAAA==.Meliôdas:BAAALgAECgMJDQAAAA==.Mendelson:BAAALgAECgEJAQABLgAECgYJCgAOAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAOAAAAAA==.Moo:BAAALgAECgYJEwAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAABLgAECn8cAAISAAcJ2AONcACZAAASAAcJ2AONcACZAAAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgkJCwAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Myrcy:BAAALgAECgUJBQAAAA==.Mysteer:BAAALgAECgcJDwABLgAECgkJGwAHAJILAA==.Mysteia:BAABLgAECn8nAAIPAAkJmxxPEQCWAgAPAAkJmxxPEQCWAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8XAAIdAAgJqBGaEgCNAQAdAAgJqBGaEgCNAQAAAA==.',
['Mø']='Mørdréd:BAAALgAECgEJAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAABLgAECn8VAAIeAAcJ0gzRFAAXAQAeAAcJ0gzRFAAXAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAcJJAAMABIUAA==.',
Ne='Necrobijuan:BAAALgAECgIJAgAAAA==.Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMLAAYJRxWyngBBAQALAAYJehSyngBBAQAfAAQJ0wcOMgCFAAABLgAFFAQJCQAYAAQGAA==.Neodragoonz:BAAALgADCgkJDAABLgAFFAQJCQAYAAQGAA==.',
Ni='Nihilist:BAABLgAECn8dAAIQAAkJwB2yEAAAAgAQAAkJwB2yEAAAAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAACLgAFFH8VAAITAAQJFxwWEwA3AQATAAQJFxwWEwA3AQAuAAQKf2UAAhMACQkNITMCANsCABMACQkNITMCANsCAAAA.',
No='Noblessyou:BAAALgAECgYJCgAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.Nurgle:BAAALgAECgMJBAAAAA==.',
Ob='Obamanationn:BAAALgAECgQJBAAAAA==.Obeejoowan:BAAALgAECgUJBgAAAA==.Obeewand:BAAALgAECgYJEQAAAA==.Obijuan:BAABLgAECn8nAAIMAAkJFgdMfABHAQAMAAkJFgdMfABHAQAAAA==.',
Ol='Oll:BAAALgADCgEJAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.Ondrex:BAAALgAECgYJCgAAAA==.',
Or='Orientote:BAAALgAECgQJBAAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn9QAAMBAAkJrhSbAwABAgABAAkJrhSbAwABAgAgAAQJYgsGRwCuAAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIcAAgJ+SFuBwAOAwAcAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pa='Pallypocket:BAAALgADCgYJEgAAAA==.',
Pi='Pippi:BAAALgADCgYJBgAAAA==.',
Pl='Plateguy:BAAALgAECggJDQAAAA==.',
Po='Poxx:BAABLgAFFH8LAAIWAAQJ7R4eRQBdAQAWAAQJ7R4eRQBdAQABLgAFFAkJRAAbAHwhAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.Quinci:BAAALgAECgEJAQAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJCgAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.Raymondnodle:BAAALgAECgQJBAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8UAAQPAAUJPBfyHwBvAQAPAAUJPBfyHwBvAQAaAAIJzRJ+MACCAAAcAAIJAQhXUABhAAAAAA==.Rhayvoke:BAABLgAECn8XAAQYAAcJyxc8HQDdAQAYAAcJkxc8HQDdAQAUAAMJ2gt1OgCWAAAXAAEJGRltOgBHAAABLgAFFAUJFAAPADwXAA==.',
Ri='Rills:BAAALgAECgQJBQAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8MAAMaAAYJFReEEwAhAQAaAAUJoBqEEwAhAQAPAAIJvwoLUgBgAAABLgAFFAkJXwARAHImAA==.Rossini:BAAALgADCgkJEgAAAA==.',
Ru='Rueittrebeck:BAAALgADCgYJBgABLgAECgYJCgAOAAAAAA==.Rush:BAAALgAECgEJAQABLgAECgQJBQAOAAAAAA==.Rushs:BAAALgAECgUJEQABLgAECgYJCgAOAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8wAAIHAAkJyBo9FAAsAgAHAAkJyBo9FAAsAgAAAA==.Rynron:BAAALgAECgkJDgAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEwAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgkJGwAHAJILAA==.',
Sb='Sbawar:BAAALgAECgEJAQAAAA==.',
Sc='Schmitty:BAAALgAECgEJAQAAAA==.',
Se='Sempiternal:BAACLgAFFH8mAAIFAAcJ8Q3QFgBwAQAFAAcJ8Q3QFgBwAQAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAILAAkJzxziNgAmAgALAAkJzxziNgAmAgAAAA==.Shaunanigans:BAABLgAECn8dAAITAAkJphCBMgDpAQATAAkJphCBMgDpAQAAAA==.Shaunsdh:BAAALgAECgQJBAABLgAECgkJHQATAKYQAA==.Shaunwick:BAAALgAECgUJBAABLgAECgkJHQATAKYQAA==.Shego:BAACLgAFFH8HAAIRAAMJxiQtDgAoAQARAAMJxiQtDgAoAQAuAAQKfyMABBEACQn8IHAFAF8CAA0ABwk6ILgxAHECABEABwkrI3AFAF8CABAAAgkdItFLAGAAAAEuAAUUBAkGAAgAMw8A.Sheltered:BAABLgAECn8xAAILAAkJrCVWBQBKAwALAAkJrCVWBQBKAwAAAA==.',
Si='Sinadora:BAAALgAECgUJCAAAAA==.Sinakra:BAABLgAECn8iAAILAAkJmw/QagCZAQALAAkJmw/QagCZAQAAAA==.',
Sk='Skyslaughter:BAAALgAECgEJAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slapdh:BAACLgAFFH8PAAIDAAcJYxWlGABUAQADAAcJYxWlGABUAQAuAAQKfx0AAwMACQkdGU0uAA4CAAMABwmVIE0uAA4CAAIACQmXA0MqAHMBAAEuAAUUCQlEABsAfCEA.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH9EAAIbAAkJfCG9AQDlAgAbAAkJfCG9AQDlAgAuAAQKfygAAhsACQniJQACAJcDABsACQniJQACAJcDAAAA.',
Sp='Spirits:BAAALgAFFAIJAwABLgAFFAYJGwAFACsYAA==.Spritz:BAABLgAECn8oAAIMAAkJixV0BwAaAgAMAAkJixV0BwAaAgAAAA==.',
St='Stampede:BAABLgAECn8XAAIBAAYJlQMqfwB5AAABAAYJlQMqfwB5AAAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stevebills:BAAALgAECgEJAQAAAA==.Stice:BAAALgAECgEJAQAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCQAAAA==.Straya:BAABLgAECn8hAAMTAAkJDhXEJAAyAgATAAkJDhXEJAAyAgASAAEJPg1XrQAqAAAAAA==.',
Su='Subito:BAAALgADCgkJEgAAAA==.Sukittrebeck:BAAALgADCgEJAQABLgAECgYJCgAOAAAAAA==.',
['Sï']='Sïrloinalot:BAAALgADCgIJBAABLgAECgkJKQAWAGUOAA==.',
Ta='Taburiel:BAAALgADCgcJCQAAAA==.Taedwar:BAAALgADCgYJBgAAAA==.Tahirrah:BAABLgAECn8eAAIMAAkJ7RUZOgD2AQAMAAkJ7RUZOgD2AQAAAA==.Talindra:BAABLgAECn8cAAIQAAkJRQaNLAD3AAAQAAkJRQaNLAD3AAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9nAAMEAAkJJBOYJQAgAgAEAAkJJBOYJQAgAgAhAAkJNxWqDQDbAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJDgABLgAECgYJCgAOAAAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8bAAIFAAYJKxhUEgCfAQAFAAYJKxhUEgCfAQAuAAQKfzUAAwUACQk9H4sLANQCAAUACQk9H4sLANQCAAsABQkOC1v8ALwAAAAA.',
Tm='Tmnt:BAABLgAECn8oAAIPAAkJbAv8UAArAQAPAAkJbAv8UAArAQAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQTAAkJ1x3+bwAMAQATAAQJdBf+bwAMAQASAAcJvg/7TQD+AAAdAAUJPgkXLQCQAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trickze:BAAALgAECgUJBQAAAA==.Trundle:BAABLgAECn8UAAMRAAcJTRISEwBJAQARAAcJCxISEwBJAQAQAAQJKxMwNgC+AAAAAA==.',
Ts='Tsilihin:BAAALgAECgYJCAAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAPAA0eAA==.Tsurenity:BAACLgAFFH8GAAIPAAIJDR6uDgCyAAAPAAIJDR6uDgCyAAAuAAQKfxkAAg8ACAm+IjEEACwDAA8ACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgAECgEJAQAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAABLgAECn8XAAQhAAUJnghQNwB+AAAhAAQJWAdQNwB+AAAiAAMJ5QdPXABWAAAEAAMJbgOuwgBDAAABLgAFFAMJCAAPAAQOAA==.',
Uk='Uki:BAAALgADCgUJCAAAAA==.',
Ur='Urbanfries:BAABLgAFFH8LAAMEAAYJZAg1JAA4AQAEAAYJZAg1JAA4AQAVAAMJcQGZSABSAAABLgAFFAcJGQATAHkbAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJZgAPAJwgAA==.Varr:BAABLgAECn8XAAMCAAkJOhxtBQCKAQACAAkJOhxtBQCKAQAjAAIJIh4rHgCqAAAAAA==.Vayeda:BAABLgAECn8kAAIWAAkJ7iJLFADgAgAWAAkJ7iJLFADgAgAAAA==.',
Ve='Venderic:BAAALgAECgMJAwAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAYAAQGAA==.',
Vo='Voidpetal:BAAALgAECgEJAQAAAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Wo='Worramotreum:BAAALgAECgQJBAAAAA==.',
Xe='Xetz:BAABLgAECn8fAAMHAAkJ9gb+OgAmAQAHAAkJ9gb+OgAmAQAkAAEJawGKiQAkAAAAAA==.Xezar:BAACLgAFFH86AAQkAAkJtRo7BQAPAgAGAAkJhBcLCwBuAgAkAAYJYR47BQAPAgAHAAQJAAnHDADeAAAuAAQKfycABAcACQk5GzEPAJECAAcACQk5GzEPAJECACQABwlrHpoWACcCAAYAAwmXH8oyAAwBAAAA.',
Xn='Xnobodie:BAAALgADCgIJAgAAAA==.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn82AAMWAAkJ5QvIegCDAQAWAAkJ5QvIegCDAQAlAAQJpwNoFQBxAAAAAA==.',
Yo='Yogi:BAAALgADCgkJCQABLgAFFAIJAgAOAAAAAA==.Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAACLgAFFH8GAAIGAAMJTgjKNgCvAAAGAAMJTgjKNgCvAAAuAAQKfycAAgYACAkiFhQdAOUBAAYACAkiFhQdAOUBAAAA.',
Za='Zarigar:BAAALgADCgkJEgAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zedan:BAAALgAECgUJBQAAAA==.Zera:BAAALgAECgEJAQABLgAFFAMJAwAOAAAAAA==.Zerin:BAAALgAECgEJAQABLgAECgkJMQALAKwlAA==.Zeroh:BAAALgAECgYJDQAAAA==.',
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
