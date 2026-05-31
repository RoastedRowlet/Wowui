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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Monk-Mistweaver','DeathKnight-Blood','Priest-Discipline','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Warrior-Protection','Monk-Windwalker','Druid-Balance','Monk-Brewmaster','Shaman-Enhancement','Paladin-Protection','Warrior-Arms','Druid-Feral','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-05-31',data={Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8gAAMCAAgJZR1zCwBUAgACAAgJZR1zCwBUAgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhrNHgA+AgAEAAgJyhrNHgA+AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn86AAIFAAkJdBvQCQDcAgAFAAkJdBvQCQDcAgAAAA==.Amoralibash:BAABLgAECn8ZAAQGAAcJWhNwYQBzAQAGAAcJWhNwYQBzAQAHAAIJZwjxPAApAAAIAAEJAAATPwAAAAAAAA==.Amorianstus:BAAALgAECgQJBAAAAA==.',
An='Anguskhan:BAAALgAECgQJBgAAAA==.Anhafel:BAABLgAECn8jAAIDAAYJmRZVcgAkAQADAAYJmRZVcgAkAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAAALgAECgUJBQAAAA==.',
Ap='Apocalipze:BAAALgADCgYJEwAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAUJFQAJAP8aAA==.Arileous:BAABLgAECn8VAAIBAAUJwwuIWwDMAAABAAUJwwuIWwDMAAAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.',
As='Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAKAJsPAA==.Aspp:BAABLgAECn8jAAILAAkJWxONNgATAgALAAkJWxONNgATAgAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Bi='Bigmagic:BAAALgAECgEJAgAAAA==.Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgYJBwAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBQAAAA==.Britnysteers:BAAALgADCggJCAAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8XAAIMAAcJphqjGwAXAgAMAAcJphqjGwAXAgAAAA==.Bucksdk:BAABLgAECn8aAAMNAAgJKBJnIgAnAQANAAcJYhRnIgAnAQALAAIJQgN9OQFIAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECggJGgANACgSAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECgkJNgAOAPIdAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgADCgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn82AAMOAAkJ8h3ABQASAwAOAAkJ8h3ABQASAwAQAAUJEQa6QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAPAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgcJGQAGAFoTAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ9MJwC8AQAFAAkJYQ9MJwC8AQABLgABCgcJCQAPAAAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH8yAAMLAAgJnCCQAAB0AgALAAcJnCCQAAB0AgANAAIJgRvSLwBSAAAuAAQKfzUABAsACQmEJecAAN0DAAsACQmEJecAAN0DAA0ABQnaJKgQAAACABEABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIGAAkJRh48HQBoAgAGAAkJRh48HQBoAgABLgAECgkJKgAKAKwlAA==.Demonbane:BAABLgAECn8uAAMCAAkJfxwcCQCAAgACAAkJfxwcCQCAAgADAAcJXAp0hwD1AAAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMSAAgJ2g8RXQDPAAASAAUJaQYRXQDPAAATAAYJJREmjQCcAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8VAAIUAAYJXBkcEAC5AQAUAAYJXBkcEAC5AQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJEAAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAPAAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCggJCAAAAA==.Ellgar:BAAALgADCgUJBQABLgAECgQJCwAPAAAAAA==.',
En='Endymion:BAABLgAECn8aAAIFAAgJoRNJJgDCAQAFAAgJoRNJJgDCAQAAAA==.',
Et='Eternity:BAACLgAFFH8VAAIJAAUJ/xr7KgA/AQAJAAUJ/xr7KgA/AQAuAAQKfy8AAgkACQkqIisMAOACAAkACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAATAFESAA==.Facetheflame:BAAALgAECgcJDQABLgAECgkJFAATAFESAA==.Facethegem:BAABLgAECn8UAAMTAAkJURI7UQBSAQATAAYJ6hE7UQBSAQASAAYJGRKgQwALAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAATAFESAA==.Facethezoom:BAAALgAECgYJDwABLgAECgkJFAATAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAPAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8HAAIDAAMJGhBiVwDJAAADAAMJGhBiVwDJAAAuAAQKfx0AAwMACQkdGUIqAAwCAAMABwmVIEIqAAwCAAIACQmXA0MqAHMBAAEuAAUUBwkdABUAZBwA.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQUAAkJNwrcFABtAQAUAAkJNwrcFABtAQAWAAIJAg7uGgBlAAAXAAIJ4AuYdABYAAAAAA==.Fizwithagun:BAAALgAECgEJAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.Foxdaloc:BAAALgAECgEJAQAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIYAAgJvAaCpwAWAQAYAAgJvAaCpwAWAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRYnHwDkAQABAAkJVRYnHwDkAQAZAAEJTwmvTgArAAAAAA==.',
Ga='Galairn:BAAALgAECgUJBQAAAA==.Gallin:BAAALgADCggJCgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Gargoyle:BAAALgADCgMJAwAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxSaHwDhAQABAAkJDxSaHwDhAQAAAA==.Gasaiyuno:BAABLgAECn8oAAMaAAgJFQ6KNQAYAQAaAAcJOgyKNQAYAQAMAAgJ8QdITwD+AAAAAA==.',
Ge='Geves:BAABLgAECn8VAAIVAAYJyBMTKgAvAQAVAAYJyBMTKgAvAQAAAA==.',
Gr='Grimmjob:BAAALgAECgEJAQAAAA==.Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgADCggJEAAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAQJEgAMAGsYAA==.',
He='Hedgehog:BAAALgAECgYJCgAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8ZAAIKAAgJ/BCVhABMAQAKAAgJ/BCVhABMAQAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECgQJBQAAAA==.Holyyoshi:BAABLgAECn8WAAIKAAgJCRGiVgDeAQAKAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Im='Impearsmoke:BAAALgADCgUJBQABLgAECggJFAASANoPAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8WAAIGAAkJhB0aEwCpAgAGAAkJhB0aEwCpAgAAAA==.',
Ja='Jab:BAACLgAFFH8JAAINAAQJvAL2KQBzAAANAAQJvAL2KQBzAAAuAAQKfyQAAg0ABwmAEa4hADUBAA0ABwmAEa4hADUBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMNAAkJ2hV4HABoAQANAAgJPxh4HABoAQALAAcJkggqpwANAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwANANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn80AAIbAAkJXiRrAgBEAwAbAAkJXiRrAgBEAwAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8oAAIcAAgJnRz1EAAhAgAcAAgJnRz1EAAhAgAAAA==.',
Jo='Joker:BAABLgAECn8cAAIJAAcJSgh6jQANAQAJAAcJSgh6jQANAQAAAA==.Jomama:BAABLgAECn8cAAIKAAkJMQzDaQCDAQAKAAkJMQzDaQCDAQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh85EgBRAgABAAkJNh85EgBRAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCggJCAAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECggJKAAcAJ0cAA==.Kes:BAAALgAECgUJCgAAAA==.',
Kk='Kk:BAAALgAECgEJAQAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAPAAAAAA==.',
Kr='Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJBAAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAPAAAAAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECggJDQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgAECgMJAwABLgAECgkJHAAKADEMAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marie:BAAALgADCgcJBgAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJCAAAAA==.Meliôdas:BAAALgAECgEJBwAAAA==.Mendelson:BAAALgADCgEJAgABLgAECgUJBwAPAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAPAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAAALgAECgYJDQAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCggJCAAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwABLgAECgkJFwAQADwKAA==.Mysteia:BAABLgAECn8lAAIMAAkJfBzkDgCTAgAMAAkJfBzkDgCTAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8WAAIdAAcJOxE3FQBKAQAdAAcJOxE3FQBKAQAAAA==.',
['Mø']='Mørdréd:BAAALgAECgEJAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAAALgAECgcJDgAAAA==.Navy:BAAALgAECgYJDgABLgAFFAUJFQAJAP8aAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMKAAYJRxWyngBBAQAKAAYJehSyngBBAQAeAAQJ0wcOMgCFAAABLgAFFAQJCQAXAAQGAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAQJCQAXAAQGAA==.',
Ni='Nihilist:BAABLgAECn8cAAINAAkJwB0yDgANAgANAAkJwB0yDgANAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAABLgAECn8+AAITAAgJQR+fEgChAgATAAgJQR+fEgChAgAAAA==.',
No='Noblessyou:BAAALgADCgcJBwABLgAECgUJBwAPAAAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJHQAAAA==.Obijuan:BAABLgAECn8dAAIJAAcJfQb5hgAaAQAJAAcJfQb5hgAaAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn8eAAMBAAYJ6Q/+RgAVAQABAAYJiw/+RgAVAQAfAAQJYgvePQC2AAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIcAAgJ+SFuBwAOAwAcAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pi='Pine:BAABLgAECn8YAAIFAAkJ7wszLQCWAQAFAAkJ7wszLQCWAQAAAA==.',
Pl='Plateguy:BAAALgAECgMJAwAAAA==.',
Po='Poxx:BAABLgAFFH8HAAIYAAMJwxofYQANAQAYAAMJwxofYQANAQABLgAFFAcJHQAVAGQcAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJCAAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8SAAQMAAQJaxh/HgArAQAMAAQJaxh/HgArAQAaAAIJzRK/JwCNAAAcAAIJAQjASABiAAAAAA==.Rhayvoke:BAABLgAECn8XAAQXAAcJyxc8HQDdAQAXAAcJkxc8HQDdAQAUAAMJ2gt1OgCWAAAWAAEJGRltOgBHAAABLgAFFAQJEgAMAGsYAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8JAAMaAAYJLBb6DgAyAQAaAAUJoBr6DgAyAQAMAAIJ2wi0PwBkAAABLgAFFAgJMgALAJwgAA==.Rossini:BAAALgADCggJCAAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.Rushs:BAAALgAECgEJAQABLgAECgUJBwAPAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8vAAIQAAkJaRrNEQArAgAQAAkJaRrNEQArAgAAAA==.Rynron:BAAALgAECgcJDAAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEQAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8cAAIOAAgJCRpHDwBeAgAOAAgJCRpHDwBeAgAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgkJFwAQADwKAA==.',
Se='Sempiternal:BAACLgAFFH8WAAIFAAUJOREPGABLAQAFAAUJOREPGABLAQAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIKAAkJzxzYLwApAgAKAAkJzxzYLwApAgAAAA==.Shaunanigans:BAABLgAECn8WAAITAAkJ8A06PACkAQATAAkJ8A06PACkAQAAAA==.Shaunsdh:BAAALgAECgQJBAABLgAECgkJFgATAPANAA==.Shaunwick:BAAALgAECgQJBAABLgAECgkJFgATAPANAA==.Shego:BAACLgAFFH8HAAIRAAMJxiT2CAA4AQARAAMJxiT2CAA4AQAuAAQKfyMABBEACQn8IHQEAFsCAAsABwk6ILgxAHECABEABwkrI3QEAFsCAA0AAgkdIs9EAGIAAAEuAAUUBAkGAAYAMw8A.Sheltered:BAABLgAECn8qAAIKAAkJrCUABABNAwAKAAkJrCUABABNAwAAAA==.',
Si='Sinadora:BAAALgAECgUJCAAAAA==.Sinakra:BAABLgAECn8iAAIKAAkJmw8BYgCUAQAKAAkJmw8BYgCUAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8dAAIVAAcJZBzhBAArAgAVAAcJZBzhBAArAgAuAAQKfygAAhUACQniJQACAJcDABUACQniJQACAJcDAAAA.',
Sp='Spritz:BAAALgAECggJDwAAAA==.',
St='Stampede:BAAALgAECgUJCAAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCAAAAA==.Straya:BAABLgAECn8eAAITAAgJCxWYKwDzAQATAAgJCxWYKwDzAQAAAA==.',
Su='Subito:BAAALgADCggJCAAAAA==.',
Ta='Tahirrah:BAABLgAECn8cAAIJAAgJDBafRgC4AQAJAAgJDBafRgC4AQAAAA==.Talindra:BAABLgAECn8ZAAINAAgJugYILgDWAAANAAgJugYILgDWAAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9LAAMgAAkJlBIODADaAQAgAAkJlBIODADaAQAEAAkJOA36RgBiAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJBwAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8LAAIFAAMJtiD1HQAZAQAFAAMJtiD1HQAZAQAuAAQKfywAAwUACAlRH/ANAKECAAUACAlRH/ANAKECAAoABQkOC13rALIAAAAA.',
Tm='Tmnt:BAABLgAECn8cAAIMAAcJGgumTwD9AAAMAAcJGgumTwD9AAAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQTAAkJ1x3AZQAOAQATAAQJdBfAZQAOAQASAAcJvg/BRAAHAQAdAAUJPgn1JgCTAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJEQAAAA==.',
Ts='Tsilihin:BAAALgAECgYJCAAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAMAA0eAA==.Tsurenity:BAACLgAFFH8GAAIMAAIJDR6uDgCyAAAMAAIJDR6uDgCyAAAuAAQKfxkAAgwACAm+IjEEACwDAAwACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAECgkJDwABLgAECggJLgAMANgOAA==.',
Ur='Urbanfries:BAABLgAFFH8KAAMEAAYJ1wfcGgBmAQAEAAYJ1wfcGgBmAQAbAAMJcQF0PQBTAAABLgAFFAUJEwATAIAfAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJLQAMAPscAA==.Varr:BAAALgAECgYJCgAAAA==.Vayeda:BAABLgAECn8kAAIYAAkJ7iIXEQDiAgAYAAkJ7iIXEQDiAgAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAXAAQGAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Xe='Xetz:BAABLgAECn8YAAMQAAkJ9gbINQAfAQAQAAkJ9gbINQAfAQAhAAEJawGKiQAkAAAAAA==.Xezar:BAACLgAFFH8nAAQhAAYJYR67AgArAgAhAAYJYR67AgArAgAOAAQJJA/DIAAVAQAQAAQJAAnHDADeAAAuAAQKfycABBAACQk5GzEPAJECABAACQk5GzEPAJECACEABwlrHpoWACcCAA4AAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn82AAMYAAkJ5QuccgB7AQAYAAkJ5QuccgB7AQAiAAQJpwNoFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAACLgAFFH8GAAIOAAMJTgjtLAC4AAAOAAMJTgjtLAC4AAAuAAQKfycAAg4ACAkiFtEYAOwBAA4ACAkiFtEYAOwBAAAA.',
Za='Zarigar:BAAALgADCggJCAAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zeroh:BAAALgAECgYJDQAAAA==.',
Zi='Zigzagger:BAAALgAECgQJBgAAAA==.',
Zn='Zna:BAAALgAECgUJCQAAAA==.',
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
