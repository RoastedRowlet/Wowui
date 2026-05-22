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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','Priest-Shadow','Unknown-Unknown','DeathKnight-Frost','Warlock-Demonology','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Warrior-Protection','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Monk-Brewmaster','Shaman-Enhancement','Paladin-Protection','Druid-Feral','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-05-17',data={Ae='Aeterna:BAAALgAECgQJBQAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8cAAMCAAcJfyBQCwAdAgACAAcJfyBQCwAdAgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhpHGQA+AgAEAAgJyhpHGQA+AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn81AAIFAAkJEBokDACNAgAFAAkJEBokDACNAgAAAA==.Amoralibash:BAAALgAECgYJDQAAAA==.Amorianstus:BAAALgAECgEJAQAAAA==.',
An='Anguskhan:BAAALgADCgUJCAAAAA==.Anhafel:BAABLgAECn8hAAIDAAYJtRTKbAAGAQADAAYJtRTKbAAGAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ap='Apocalipze:BAAALgADCgYJCwAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAQJDQAGABUYAA==.Arileous:BAAALgAECgUJDAAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.',
As='Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAHAJsPAA==.Aspp:BAABLgAECn8YAAIIAAgJJQ7oWACDAQAIAAgJJQ7oWACDAQAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Bi='Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgADCgEJAQAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgYJBwAAAA==.Blutopic:BAAALgADCgUJBwAAAA==.',
Br='Briar:BAAALgAECgMJBAAAAA==.Britnysteers:BAAALgADCgUJBQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAAALgAECgYJEAAAAA==.Bucksdk:BAABLgAECn8ZAAMJAAcJYRRUGwA0AQAJAAcJYRRUGwA0AQAIAAEJuAG8PgEaAAAAAA==.Buckshotheal:BAAALgADCgcJCAABLgAECgcJGQAJAGEUAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Cantmilkthis:BAAALgADCgIJAQAAAA==.Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECgkJKAAKAK0bAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgADCgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn8oAAMKAAkJrRvXBgDPAgAKAAkJrRvXBgDPAgALAAUJEQa6QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgQJCAAMAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgYJDQAMAAAAAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ/nHwDEAQAFAAkJYQ/nHwDEAQABLgABCgcJBwAMAAAAAA==.',
De='Deadcow:BAAALgAECgIJAgAAAA==.Deathzdemize:BAACLgAFFH8nAAMIAAgJlCCQAAB0AgAIAAcJlCCQAAB0AgAJAAEJAAATLgAAAAAuAAQKfzUABAgACQmEJecAAN0DAAgACQmEJecAAN0DAAkABQnaJKgQAAACAA0ABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIOAAkJQx70FAB4AgAOAAkJQx70FAB4AgABLgAECgkJKgAHAKwlAA==.Demonbane:BAABLgAECn8qAAMCAAkJGBz8BgB9AgACAAkJGBz8BgB9AgADAAcJWgoNdAD0AAAAAA==.',
Di='Diancie:BAAALgAECgIJAgAAAA==.Dirtpear:BAABLgAECn8UAAMPAAgJ2g8RXQDPAAAPAAUJaQYRXQDPAAAQAAYJJRGOdACeAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8UAAIRAAYJXBlrDQC8AQARAAYJXBlrDQC8AQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgUJDAAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAMAAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgUJBQAAAA==.',
En='Endymion:BAABLgAECn8YAAIFAAgJlhNRHwDIAQAFAAgJlhNRHwDIAQAAAA==.',
Et='Eternity:BAACLgAFFH8NAAIGAAQJFRgsHwBAAQAGAAQJFRgsHwBAAQAuAAQKfy4AAgYACQkpIisMAOACAAYACQkpIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJAwAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAAQAFISAA==.Facetheflame:BAAALgAECgYJBwABLgAECgkJFAAQAFISAA==.Facethegem:BAABLgAECn8UAAMQAAkJUhKHQQBVAQAQAAYJ6xGHQQBVAQAPAAYJGRIwNwARAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAAQAFISAA==.Facethezoom:BAAALgADCgcJBwABLgAECgkJFAAQAFISAA==.Father:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8FAAIDAAIJvRDAVgCVAAADAAIJvRDAVgCVAAAuAAQKfx0AAwMACQkXGVYhABMCAAMABwmNIFYhABMCAAIACQmXA0MqAHMBAAEuAAUUBwkZABIAbxsA.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8nAAQRAAkJNwp/EQB0AQARAAkJNwp/EQB0AQATAAIJAg7vFQBwAAAUAAEJ4gkrcwAvAAAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.',
Fr='Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIVAAgJvAYsjAAtAQAVAAgJvAYsjAAtAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuBZDFwD0AQABAAkJVRZDFwD0AQAWAAEJSQkLRgAlAAAAAA==.',
Ga='Galairn:BAAALgAECgUJBQAAAA==.Gallin:BAAALgADCgYJBgAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxT4FwDtAQABAAkJDxT4FwDtAQAAAA==.Gasaiyuno:BAABLgAECn8dAAMXAAgJ7QeqOgD/AAAXAAgJ7QeqOgD/AAAYAAcJMQZ/QQC5AAAAAA==.',
Ge='Geves:BAAALgAECgYJEAAAAA==.',
Gr='Gryfter:BAAALgADCgYJBgAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAQJCgAXADcLAA==.',
He='Hedgehog:BAAALgAECgQJBwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8XAAIHAAgJ/BAbaABiAQAHAAgJ/BAbaABiAQAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgADCgYJBgAAAA==.Holyyoshi:BAABLgAECn8WAAIHAAgJCRGiVgDeAQAHAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Im='Impearsmoke:BAAALgADCgUJBQABLgAECggJFAAPANoPAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAAALgAECggJDgAAAA==.',
Ja='Jab:BAACLgAFFH8IAAIJAAQJRQK/HgCDAAAJAAQJRQK/HgCDAAAuAAQKfyQAAgkABwmAEa4hADUBAAkABwmAEa4hADUBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMJAAkJ2hV4HABoAQAJAAgJPxh4HABoAQAIAAcJkghsjAATAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwAJANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn8qAAIZAAgJuCJXBwCjAgAZAAgJuCJXBwCjAgAAAA==.Jinu:BAABLgAECn8YAAIDAAgJ/h4ZMwAuAgADAAgJ/h4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8eAAIaAAgJoBwpDQAvAgAaAAgJoBwpDQAvAgAAAA==.',
Jo='Joker:BAABLgAECn8XAAIGAAcJAQfhfAD3AAAGAAcJAQfhfAD3AAAAAA==.Jomama:BAABLgAECn8UAAIHAAgJ6QuNdABHAQAHAAgJ6QuNdABHAQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNR/qCwBtAgABAAkJNR/qCwBtAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCgUJBQAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECggJHgAaAKAcAA==.Kes:BAAALgAECgUJCgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAMAAAAAA==.',
Kr='Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
La='Lad:BAAALgAECgQJBgAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgADCgcJDAAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJGwAQAPQZAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECgMJBQAAAA==.',
Li='Lilthiccy:BAAALgADCgUJBQABLgAECggJFAAHAOkLAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Meliôdas:BAAALgAECgEJBgAAAA==.Mendelson:BAAALgADCgEJAQABLgAECgUJBwAMAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAMAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAAALgAECgIJAgAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgUJBQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwAAAA==.Mysteia:BAABLgAECn8iAAIXAAgJ9BzMEABCAgAXAAgJ9BzMEABCAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8UAAIbAAYJDREZFAAOAQAbAAYJDREZFAAOAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAAALgAECgEJAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAQJDQAGABUYAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMHAAYJRxWyngBBAQAHAAYJehSyngBBAQAcAAQJ0wcOMgCFAAABLgAFFAMJCAAUAMEGAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAMJCAAUAMEGAA==.',
Ni='Nihilist:BAABLgAECn8bAAIJAAkJgx3bCgAXAgAJAAkJgx3bCgAXAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAABLgAECn8uAAIQAAgJ8h5ODwCTAgAQAAgJ8h5ODwCTAgAAAA==.',
No='Noblessyou:BAAALgADCgEJAQABLgAECgUJBwAMAAAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJGwAAAA==.Obijuan:BAAALgAECgYJEQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAAALgAECgYJEgAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIaAAgJ+SFuBwAOAwAaAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pi='Pine:BAABLgAECn8XAAIFAAgJ/gzbKwByAQAFAAgJ/gzbKwByAQAAAA==.',
Pl='Plateguy:BAAALgADCgQJAwAAAA==.',
Po='Poxx:BAAALgAFFAIJAwABLgAFFAcJGQASAG8bAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgADCgIJAgAAAA==.Ranker:BAAALgAECgQJBQAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8KAAQXAAQJNwsoGwD1AAAXAAQJNwsoGwD1AAAaAAIJAQjYPgBmAAAYAAEJ4RRTJgBNAAAAAA==.Rhayvoke:BAABLgAECn8XAAQUAAcJyxc8HQDdAQAUAAcJkxc8HQDdAQARAAMJ2gt1OgCWAAATAAEJGRltOgBHAAABLgAFFAQJCgAXADcLAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAAALgAFFAIJBAABLgAFFAgJJwAIAJQgAA==.Rossini:BAAALgADCgUJBQAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Rushs:BAAALgADCgEJAgABLgAECgUJBwAMAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8oAAILAAgJ7RlIFQDeAQALAAgJ7RlIFQDeAQAAAA==.Rynron:BAAALgAECgQJCQAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEQAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8XAAIKAAgJPRgpDgBDAgAKAAgJPRgpDgBDAgAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgcJDwAMAAAAAA==.',
Se='Sempiternal:BAACLgAFFH8PAAIFAAQJnhBVGQAVAQAFAAQJnhBVGQAVAQAuAAQKfzUAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIHAAkJzhzAIABJAgAHAAkJzhzAIABJAgAAAA==.Shaunanigans:BAAALgAECggJDgAAAA==.Shaunsdh:BAAALgAECgEJAQABLgAECggJDgAMAAAAAA==.Shaunwick:BAAALgAECgQJBAABLgAECggJDgAMAAAAAA==.Shego:BAACLgAFFH8FAAINAAMJkiPgBAA+AQANAAMJkiPgBAA+AQAuAAQKfxsABA0ACQmMIDgGANsBAAgABwk6ILgxAHECAA0ABgkHIjgGANsBAAkAAgkdIiU5AGQAAAAA.Sheltered:BAABLgAECn8qAAIHAAkJrCUZAgBgAwAHAAkJrCUZAgBgAwAAAA==.',
Si='Sinadora:BAAALgAECgUJAgAAAA==.Sinakra:BAABLgAECn8iAAIHAAkJmw87SACxAQAHAAkJmw87SACxAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8ZAAISAAcJbxuhAQBCAgASAAcJbxuhAQBCAgAuAAQKfygAAhIACQniJXcBADMDABIACQniJXcBADMDAAAA.',
Sp='Spritz:BAAALgAECgYJDAAAAA==.',
St='Stampede:BAAALgADCggJHQAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCgUJBQAAAA==.Straya:BAABLgAECn8aAAIQAAgJeBJ5KwDAAQAQAAgJeBJ5KwDAAQAAAA==.',
Su='Subito:BAAALgADCgUJBQAAAA==.',
Ta='Tahirrah:BAABLgAECn8YAAIGAAgJXhXJPgCgAQAGAAgJXhXJPgCgAQAAAA==.Talindra:BAABLgAECn8VAAIJAAgJaQZHJQDeAAAJAAgJaQZHJQDeAAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.',
Te='Temperånce:BAABLgAECn85AAMEAAkJNw1dPQBiAQAEAAkJNw1dPQBiAQAdAAgJKgmoEgA7AQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJBwAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJGAAAAA==.',
Ti='Tino:BAACLgAFFH8FAAIFAAMJJhrcHAD3AAAFAAMJJhrcHAD3AAAuAAQKfygAAwUACAl+HvwTAHMCAAUACAl+HvwTAHMCAAcABQkOC968AMwAAAAA.',
Tm='Tmnt:BAABLgAECn8XAAIXAAcJGgvFOgD/AAAXAAcJGgvFOgD/AAAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8XAAQPAAgJug8qOAAMAQAPAAcJvQ8qOAAMAQAQAAMJvxqzXwDjAAAbAAQJgQoMIgBiAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJEAAAAA==.',
Ts='Tsilihin:BAAALgAECgYJBwAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAXAA0eAA==.Tsurenity:BAACLgAFFH8GAAIXAAIJDR6uDgCyAAAXAAIJDR6uDgCyAAAuAAQKfxkAAhcACAm+IjEEACwDABcACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAECgkJCwABLgAECggJIgAXAG0MAA==.',
Va='Valerus:BAAALgAECgQJCAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAgJHAAXAMAYAA==.Varr:BAAALgAECgMJBgAAAA==.Vayeda:BAABLgAECn8kAAIVAAkJ7SKcCgD8AgAVAAkJ7SKcCgD8AgAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAMJCAAUAMEGAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAQAAAA==.',
Xe='Xetz:BAAALgAECgcJDQAAAA==.Xezar:BAACLgAFFH8UAAQLAAUJAAnHDADeAAALAAQJAAnHDADeAAAeAAEJXyMHIQBpAAAKAAIJ2AVEMABLAAAuAAQKfycABAsACQk3GzEPAJECAAsACQk3GzEPAJECAB4ABwlrHpoWACcCAAoAAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn8sAAMVAAkJ4wsSXACSAQAVAAkJ4wsSXACSAQAfAAQJpwNoFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAABLgAECn8dAAIKAAgJGxOMHACwAQAKAAgJGxOMHACwAQAAAA==.',
Za='Zarigar:BAAALgADCgUJBQAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zeroh:BAAALgAECgYJDQAAAA==.',
Zi='Zigzagger:BAAALgAECgQJBgAAAA==.',
Zn='Zna:BAAALgAECgUJCAAAAA==.',
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
