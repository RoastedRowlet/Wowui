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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Monk-Mistweaver','DeathKnight-Blood','Priest-Discipline','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Warlock-Demonology','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Warrior-Protection','Monk-Windwalker','Druid-Balance','Monk-Brewmaster','Shaman-Enhancement','Paladin-Protection','Warrior-Arms','Druid-Feral','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-05-24',data={Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8fAAMCAAgJZR0RCgBaAgACAAgJZR0RCgBaAgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhrXHAA+AgAEAAgJyhrXHAA+AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn81AAIFAAkJDhq7DgCGAgAFAAkJDhq7DgCGAgAAAA==.Amoralibash:BAAALgAECgYJEgAAAA==.Amorianstus:BAAALgAECgEJAQAAAA==.',
An='Anguskhan:BAAALgAECgIJAgAAAA==.Anhafel:BAABLgAECn8jAAIDAAYJmRaIbAAnAQADAAYJmRaIbAAnAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAAALgAECgQJBAAAAA==.',
Ap='Apocalipze:BAAALgADCgYJDgAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAUJEQAGAP8aAA==.Arileous:BAAALgAECgUJEQAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.',
As='Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAHAJsPAA==.Aspp:BAABLgAECn8eAAIIAAgJog/cWwCTAQAIAAgJog/cWwCTAQAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Bi='Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgYJBwAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBAAAAA==.Britnysteers:BAAALgADCggJCAAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8XAAIJAAcJpRrdGQAOAgAJAAcJpRrdGQAOAgAAAA==.Bucksdk:BAABLgAECn8ZAAMKAAcJYhSjHwAqAQAKAAcJYhSjHwAqAQAIAAEJuQESXwEdAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECgcJGQAKAGIUAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECgkJMAALACMcAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgADCgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn8wAAMLAAkJIxz+BgDqAgALAAkJIxz+BgDqAgANAAUJEQa6QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAMAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgYJEgAMAAAAAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ+dJAC+AQAFAAkJYQ+dJAC+AQABLgABCgcJCQAMAAAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH8tAAMIAAgJmyCQAAB0AgAIAAcJmyCQAAB0AgAKAAIJgRvfKgBUAAAuAAQKfzUABAgACQmEJecAAN0DAAgACQmEJecAAN0DAAoABQnaJKgQAAACAA4ABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIPAAkJRh5NGgBvAgAPAAkJRh5NGgBvAgABLgAECgkJKgAHAKwlAA==.Demonbane:BAABLgAECn8tAAMCAAkJgByWCAB4AgACAAkJgByWCAB4AgADAAcJXApmfAACAQAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMQAAgJ2g8RXQDPAAAQAAUJaQYRXQDPAAARAAYJJRHnggCeAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8VAAISAAYJXBk7DwC4AQASAAYJXBk7DwC4AQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJDgAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAMAAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCggJCAAAAA==.',
En='Endymion:BAABLgAECn8aAAIFAAgJoROiIwDFAQAFAAgJoROiIwDFAQAAAA==.',
Et='Eternity:BAACLgAFFH8RAAIGAAUJ/xoKHwBNAQAGAAUJ/xoKHwBNAQAuAAQKfy8AAgYACQkqIisMAOACAAYACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAARAFESAA==.Facetheflame:BAAALgAECgYJCAABLgAECgkJFAARAFESAA==.Facethegem:BAABLgAECn8UAAMRAAkJURL2SgBTAQARAAYJ6hH2SgBTAQAQAAYJGRK1PgAMAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAARAFESAA==.Facethezoom:BAAALgAECgYJCQABLgAECgkJFAARAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAMAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8HAAIDAAMJGhDNTQDSAAADAAMJGhDNTQDSAAAuAAQKfx0AAwMACQkdGUonABICAAMABwmVIEonABICAAIACQmXA0MqAHMBAAEuAAUUBwkZABMAbxsA.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQSAAkJNwqGEwBxAQASAAkJNwqGEwBxAQAUAAIJAg4AGQBpAAAVAAIJ4AuebgBbAAAAAA==.Fizwithagun:BAAALgAECgEJAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIWAAgJvAZ1lgAzAQAWAAgJvAZ1lgAzAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRYwHADqAQABAAkJVRYwHADqAQAXAAEJTwkWSgArAAAAAA==.',
Ga='Galairn:BAAALgAECgUJBQAAAA==.Gallin:BAAALgADCgYJBgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxTgHADkAQABAAkJDxTgHADkAQAAAA==.Gasaiyuno:BAABLgAECn8hAAMJAAgJ8QfbRQABAQAJAAgJ8QfbRQABAQAYAAcJVQj8QADSAAAAAA==.',
Ge='Geves:BAABLgAECn8VAAITAAYJyBPPJgA0AQATAAYJyBPPJgA0AQAAAA==.',
Gr='Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgADCggJDAAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAQJDgAJAGsYAA==.',
He='Hedgehog:BAAALgAECgUJCQAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8YAAIHAAgJ/BBldABnAQAHAAgJ/BBldABnAQAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECgQJBQAAAA==.Holyyoshi:BAABLgAECn8WAAIHAAgJCRGiVgDeAQAHAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Im='Impearsmoke:BAAALgADCgUJBQABLgAECggJFAAQANoPAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8UAAIPAAgJwx1JHgBYAgAPAAgJwx1JHgBYAgAAAA==.',
Ja='Jab:BAACLgAFFH8JAAIKAAQJvALBJAB9AAAKAAQJvALBJAB9AAAuAAQKfyQAAgoABwmAEa4hADUBAAoABwmAEa4hADUBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMKAAkJ2hV4HABoAQAKAAgJPxh4HABoAQAIAAcJkgiynAANAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwAKANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn8zAAIZAAgJayT9BQDcAgAZAAgJayT9BQDcAgAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8iAAIaAAgJnRyzDwAkAgAaAAgJnRyzDwAkAgAAAA==.',
Jo='Joker:BAABLgAECn8cAAIGAAcJSggdhAAKAQAGAAcJSggdhAAKAQAAAA==.Jomama:BAABLgAECn8aAAIHAAgJ6gsUewBaAQAHAAgJ6gsUewBaAQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh8EEABYAgABAAkJNh8EEABYAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCggJCAAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECggJIgAaAJ0cAA==.Kes:BAAALgAECgUJCgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAMAAAAAA==.',
Kr='Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJBAAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAMAAAAAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECgcJDAAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgADCgUJBQABLgAECggJGgAHAOoLAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJBAAAAA==.Meliôdas:BAAALgAECgEJBwAAAA==.Mendelson:BAAALgADCgEJAgABLgAECgUJBwAMAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAMAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAAALgAECgUJCgAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCggJCAAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwABLgAECggJEAAMAAAAAA==.Mysteia:BAABLgAECn8lAAIJAAkJfBx0DQCTAgAJAAkJfBx0DQCTAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8WAAIbAAcJOxH4EgBLAQAbAAcJOxH4EgBLAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAAALgAECgYJBwAAAA==.Navy:BAAALgAECgYJDgABLgAFFAUJEQAGAP8aAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMHAAYJRxWyngBBAQAHAAYJehSyngBBAQAcAAQJ0wcOMgCFAAABLgAFFAQJCQAVAAQGAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAQJCQAVAAQGAA==.',
Ni='Nihilist:BAABLgAECn8cAAIKAAkJwB2pDAAUAgAKAAkJwB2pDAAUAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAABLgAECn82AAIRAAgJDx8SEQCeAgARAAgJDx8SEQCeAgAAAA==.',
No='Noblessyou:BAAALgADCgEJAQABLgAECgUJBwAMAAAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJGwAAAA==.Obijuan:BAABLgAECn8WAAIGAAcJzwVjhAAJAQAGAAcJzwVjhAAJAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn8YAAMBAAYJ6Q80RQALAQABAAYJ8w40RQALAQAdAAQJYgswOAC3AAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIaAAgJ+SFuBwAOAwAaAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pi='Pine:BAABLgAECn8YAAIFAAkJ7wtkKgCYAQAFAAkJ7wtkKgCYAQAAAA==.',
Pl='Plateguy:BAAALgADCgQJAwAAAA==.',
Po='Poxx:BAABLgAFFH8GAAIWAAMJqBZfXQADAQAWAAMJqBZfXQADAQABLgAFFAcJGQATAG8bAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJBgAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8OAAQJAAQJaxjGGAA9AQAJAAQJaxjGGAA9AQAaAAIJAQj2RABlAAAYAAEJ4RQ4LQBNAAAAAA==.Rhayvoke:BAABLgAECn8XAAQVAAcJyxc8HQDdAQAVAAcJkxc8HQDdAQASAAMJ2gt1OgCWAAAUAAEJGRltOgBHAAABLgAFFAQJDgAJAGsYAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8JAAMYAAYJLBZaDAA7AQAYAAUJoBpaDAA7AQAJAAIJ2wgqNABzAAABLgAFFAgJLQAIAJsgAA==.Rossini:BAAALgADCggJCAAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAMAAAAAA==.Rushs:BAAALgADCgIJAwABLgAECgUJBwAMAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8tAAINAAkJBRrTEAAvAgANAAkJBRrTEAAvAgAAAA==.Rynron:BAAALgAECgQJCQAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEQAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8cAAILAAgJCRq6DQBpAgALAAgJCRq6DQBpAgAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECggJEAAMAAAAAA==.',
Se='Sempiternal:BAACLgAFFH8SAAIFAAQJnhDpHgD+AAAFAAQJnhDpHgD+AAAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIHAAkJzxzNKAA/AgAHAAkJzxzNKAA/AgAAAA==.Shaunanigans:BAABLgAECn8UAAIRAAgJDQ9HQAB+AQARAAgJDQ9HQAB+AQAAAA==.Shaunsdh:BAAALgAECgEJAQABLgAECggJFAARAA0PAA==.Shaunwick:BAAALgAECgQJBAABLgAECggJFAARAA0PAA==.Shego:BAACLgAFFH8GAAIOAAMJxiQFBwBCAQAOAAMJxiQFBwBCAQAuAAQKfyAABA4ACQnRIHMEAEoCAAgABwk6ILgxAHECAA4ABwnTInMEAEoCAAoAAgkdItw/AGMAAAEuAAUUBAkGAA8AMw8A.Sheltered:BAABLgAECn8qAAIHAAkJrCUVAwBbAwAHAAkJrCUVAwBbAwAAAA==.',
Si='Sinadora:BAAALgAECgUJAgAAAA==.Sinakra:BAABLgAECn8iAAIHAAkJmw9oUgC1AQAHAAkJmw9oUgC1AQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8ZAAITAAcJbxukAwAlAgATAAcJbxukAwAlAgAuAAQKfygAAhMACQniJQACAJcDABMACQniJQACAJcDAAAA.',
Sp='Spritz:BAAALgAECgcJDgAAAA==.',
St='Stampede:BAAALgAECgMJAwAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCAAAAA==.Straya:BAABLgAECn8eAAIRAAgJCxW3JwD2AQARAAgJCxW3JwD2AQAAAA==.',
Su='Subito:BAAALgADCggJCAAAAA==.',
Ta='Tahirrah:BAABLgAECn8cAAIGAAgJDBb6PwC4AQAGAAgJDBb6PwC4AQAAAA==.Talindra:BAABLgAECn8ZAAIKAAgJugbJKgDXAAAKAAgJugbJKgDXAAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9CAAMeAAkJEQ9xDQCuAQAeAAkJEQ9xDQCuAQAEAAkJOA16QwBiAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJBwAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8GAAIFAAMJJhoaIQDuAAAFAAMJJhoaIQDuAAAuAAQKfywAAwUACAlRH2wMAKYCAAUACAlRH2wMAKYCAAcABQkOC4nUAMoAAAAA.',
Tm='Tmnt:BAABLgAECn8cAAIJAAcJGgsDRgAAAQAJAAcJGgsDRgAAAQAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQRAAkJ1x0FXgAPAQARAAQJdBcFXgAPAQAQAAcJvg+SPwAJAQAbAAUJPgkQIwCTAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJEAAAAA==.',
Ts='Tsilihin:BAAALgAECgYJBwAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAJAA0eAA==.Tsurenity:BAACLgAFFH8GAAIJAAIJDR6uDgCyAAAJAAIJDR6uDgCyAAAuAAQKfxkAAgkACAm+IjEEACwDAAkACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAECgkJDgABLgAECggJKwAJAOUNAA==.',
Ur='Urbanfries:BAAALgAFFAQJBAABLgAFFAUJEwARAIAfAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJHQAJAPgWAA==.Varr:BAAALgAECgYJCQAAAA==.Vayeda:BAABLgAECn8kAAIWAAkJ7iKPDgDxAgAWAAkJ7iKPDgDxAgAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAVAAQGAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Xe='Xetz:BAAALgAECggJEwAAAA==.Xezar:BAACLgAFFH8cAAQNAAYJYA3HDADeAAANAAQJAAnHDADeAAALAAMJOQ2uJgDOAAAfAAIJOxzJJQBlAAAuAAQKfycABA0ACQk5GzEPAJECAA0ACQk5GzEPAJECAB8ABwlrHpoWACcCAAsAAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn8xAAMWAAkJ5Qt/ZgCWAQAWAAkJ5Qt/ZgCWAQAgAAQJpwNoFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAABLgAECn8lAAILAAgJIhbUFwDrAQALAAgJIhbUFwDrAQAAAA==.',
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
