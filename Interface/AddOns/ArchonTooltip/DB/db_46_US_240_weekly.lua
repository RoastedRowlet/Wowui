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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Monk-Mistweaver','DeathKnight-Blood','Priest-Discipline','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Warrior-Protection','Monk-Windwalker','Druid-Balance','Monk-Brewmaster','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Druid-Feral','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=46,date='2026-06-07',data={Ae='Aeterna:BAAALgAECgUJBgAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJIwABAA8UAA==.Allure:BAABLgAECn8iAAMCAAkJHx/SBgC9AgACAAkJHx/SBgC9AgADAAQJ4QucpwDCAAAAAA==.Almasy:BAABLgAECn8WAAIEAAgJyhoZIAA9AgAEAAgJyhoZIAA9AgAAAA==.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn86AAIFAAkJdBuaCgDZAgAFAAkJdBuaCgDZAgAAAA==.Amoralibash:BAABLgAECn8dAAQGAAcJxxO/YQB3AQAGAAcJxxO/YQB3AQAHAAIJPxIENgBAAAAIAAIJZwhUPwApAAAAAA==.Amorianstus:BAAALgAECgQJBAAAAA==.',
An='Anguskhan:BAAALgAECgQJBwAAAA==.Anhafel:BAABLgAECn8jAAIDAAYJmRZVdwAnAQADAAYJmRZVdwAnAQAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ao='Aoife:BAAALgAECgYJBwAAAA==.',
Ap='Apocalipze:BAAALgADCgYJGQAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAUJFQAJAP8aAA==.Arileous:BAABLgAECn8bAAIBAAYJuA10SwARAQABAAYJuA10SwARAQAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.Artheen:BAAALgAECgcJBwAAAA==.',
As='Asmoodeus:BAAALgAECgYJCAABLgAECgkJIgAKAJsPAA==.Aspp:BAABLgAECn8jAAILAAkJWxPmOQASAgALAAkJWxPmOQASAgAAAA==.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Babykittae:BAAALgADCgEJAQAAAA==.Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Be='Bearwitme:BAAALgADCgEJAQAAAA==.',
Bh='Bhalen:BAAALgADCgUJBQAAAA==.',
Bi='Bigmagic:BAAALgAECgEJAwAAAA==.Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgAECgQJBAAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgcJCwAAAA==.Blutopic:BAAALgAECgYJBgAAAA==.',
Br='Briar:BAAALgAECgMJBQAAAA==.Britnysteers:BAAALgADCgkJCQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAABLgAECn8bAAIMAAcJ1BrKHAAgAgAMAAcJ1BrKHAAgAgAAAA==.Bucksdk:BAABLgAECn8aAAMNAAgJKBKbJAAjAQANAAcJYhSbJAAjAQALAAIJQgOASQFIAAAAAA==.Buckshotheal:BAAALgAECgYJBgABLgAECggJGgANACgSAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECgkJPAAOAPIdAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Coach:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Ct='Cts:BAAALgADCgEJAQAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn88AAMOAAkJ8h1SBgATAwAOAAkJ8h1SBgATAwAQAAUJEQa6QwDeAAAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgYJDAAPAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgcJHQAGAMcTAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJCwAAAA==.Dave:BAABLgAECn8aAAIFAAkJYQ9ZKQC5AQAFAAkJYQ9ZKQC5AQABLgABCgcJCQAPAAAAAA==.',
De='Deadcow:BAAALgAECgMJBAAAAA==.Deathzdemize:BAACLgAFFH8yAAMLAAgJnCCQAAB0AgALAAcJnCCQAAB0AgANAAIJgRurNABSAAAuAAQKfzUABAsACQmEJecAAN0DAAsACQmEJecAAN0DAA0ABQnaJKgQAAACABEABAmDFVgNANgAAAAA.Decay:BAABLgAECn8sAAIGAAkJRh4QHwBkAgAGAAkJRh4QHwBkAgABLgAECgkJKgAKAKwlAA==.Demonbane:BAABLgAECn8uAAMCAAkJfxwXCgB6AgACAAkJfxwXCgB6AgADAAcJXAoDiwD+AAAAAA==.',
Di='Diancie:BAAALgAECgMJAwAAAA==.Dirtpear:BAABLgAECn8UAAMSAAgJ2g8RXQDPAAASAAUJaQYRXQDPAAATAAYJJRH6kwCcAAAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJCwAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAABLgAECn8WAAIUAAYJXBmuEAC4AQAUAAYJXBmuEAC4AQAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgYJEAAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAPAAAAAA==.',
Dy='Dyrillin:BAAALgADCgUJCgAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgkJCQAAAA==.Ellgar:BAAALgADCgUJBQABLgAECgYJEQAPAAAAAA==.',
En='Endymion:BAABLgAECn8cAAIFAAgJAhVLJgDNAQAFAAgJAhVLJgDNAQAAAA==.',
Et='Eternity:BAACLgAFFH8VAAIJAAUJ/xo2MwA6AQAJAAUJ/xo2MwA6AQAuAAQKfy8AAgkACQkqIisMAOACAAkACQkqIisMAOACAAAA.',
Ev='Evigs:BAAALgADCgMJBAAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgYJBgABLgAECgkJFAATAFESAA==.Facetheflame:BAAALgAECgcJEQABLgAECgkJFAATAFESAA==.Facethegem:BAABLgAECn8UAAMTAAkJURLBVQBRAQATAAYJ6hHBVQBRAQASAAYJGRKsRwAHAQAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAATAFESAA==.Facethezoom:BAAALgAFFAEJAQABLgAECgkJFAATAFESAA==.Father:BAAALgAECgEJAgABLgAECgQJBQAPAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8KAAIDAAQJGhDAXwDAAAADAAQJGhDAXwDAAAAuAAQKfx0AAwMACQkdGRIsAA4CAAMABwmVIBIsAA4CAAIACQmXA0MqAHMBAAEuAAUUBwkdABUAZBwA.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJDQAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8oAAQUAAkJNwqfFQBsAQAUAAkJNwqfFQBsAQAWAAIJAg44HABjAAAXAAIJ4Au8fQBVAAAAAA==.Fizwithagun:BAAALgAECgEJAQAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.Foxdaloc:BAAALgAECgEJAQAAAA==.',
Fr='Friend:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAIYAAgJvAZhpwArAQAYAAgJvAZhpwArAQAAAA==.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8cAAMBAAkJuRb9IADjAQABAAkJVRb9IADjAQAZAAEJTwleUgArAAAAAA==.',
Ga='Galairn:BAAALgAECgYJCwAAAA==.Gallin:BAAALgADCggJCgAAAA==.Gamorlon:BAAALgAECgYJBgAAAA==.Ganicus:BAAALgAECgIJAwAAAA==.Gargoyle:BAAALgADCgMJAwAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8jAAIBAAkJDxSBIQDgAQABAAkJDxSBIQDgAQAAAA==.Gasaiyuno:BAABLgAECn8oAAMaAAgJFQ6EOQAQAQAaAAcJOgyEOQAQAQAMAAgJ8QdMVgD+AAAAAA==.',
Ge='Geves:BAABLgAECn8VAAIVAAYJyBNHLAArAQAVAAYJyBNHLAArAQAAAA==.',
Gr='Grimmjob:BAAALgAECgEJAQAAAA==.Gromdred:BAAALgADCgMJAwAAAA==.Gryfter:BAAALgAECgEJAQAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAUJEwAMADcVAA==.',
He='Hedgehog:BAAALgAECgYJCgAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8ZAAIKAAgJ/BAFigBSAQAKAAgJ/BAFigBSAQAAAA==.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgcJDwAAAA==.Holysquid:BAAALgAECggJDAAAAA==.Holyyoshi:BAABLgAECn8WAAIKAAgJCRGiVgDeAQAKAAgJCRGiVgDeAQAAAA==.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAPAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAABLgAECn8cAAIGAAkJhB0EFACoAgAGAAkJhB0EFACoAgAAAA==.',
Ja='Jab:BAACLgAFFH8JAAINAAQJvAKtLgBxAAANAAQJvAKtLgBxAAAuAAQKfyQAAg0ABwmAEa4hADUBAA0ABwmAEa4hADUBAAAA.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMNAAkJ2hV4HABoAQANAAgJPxh4HABoAQALAAcJkgg6rwANAQAAAA==.Jaspper:BAAALgAECgYJCwABLgAECgkJHwANANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn80AAIbAAkJXiS0AgBCAwAbAAkJXiS0AgBCAwAAAA==.Jinu:BAABLgAECn8ZAAIDAAgJ/x4ZMwAuAgADAAgJ/x4ZMwAuAgAAAA==.Jiéqu:BAABLgAECn8tAAIcAAkJYhoyDQBcAgAcAAkJYhoyDQBcAgAAAA==.',
Jo='Joker:BAABLgAECn8cAAIJAAcJSgiNlQAJAQAJAAcJSgiNlQAJAQAAAA==.Jomama:BAABLgAECn8jAAIKAAkJKg4mYACnAQAKAAkJKg4mYACnAQAAAA==.Jork:BAABLgAECn8lAAIBAAkJNh/HEwBOAgABAAkJNh/HEwBOAgAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCgkJCQAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECgkJLQAcAGIaAA==.Kes:BAAALgAECgUJCgAAAA==.',
Kk='Kk:BAAALgAECgEJAQAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAPAAAAAA==.',
Kr='Kredron:BAAALgAECgEJAQAAAA==.Kristiani:BAAALgADCgIJAgAAAA==.',
Ky='Kylowren:BAAALgAECgQJBgAAAA==.',
La='Lad:BAAALgAECgQJBwAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgAECgIJAgAAAA==.',
Le='Leaffy:BAAALgAECgEJAwABLgAECggJEgAPAAAAAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECggJDQAAAA==.',
Li='Liana:BAAALgAECgEJAQAAAA==.Lilthiccy:BAAALgAECgMJAwABLgAECgkJIwAKACoOAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marie:BAAALgADCgcJBgAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Medvedev:BAAALgAECgQJCAAAAA==.Meliôdas:BAAALgAECgEJCAAAAA==.Mendelson:BAAALgADCgEJAgABLgAECgUJCAAPAAAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAPAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAAALgAECgYJEgAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgkJCQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwABLgAECgkJGQAQAJILAA==.Mysteia:BAABLgAECn8lAAIMAAkJfBwGEACUAgAMAAkJfBwGEACUAgAAAA==.',
['Mà']='Màkina:BAABLgAECn8WAAIdAAcJOxHAFgBKAQAdAAcJOxHAFgBKAQAAAA==.',
['Mø']='Mørdréd:BAAALgAECgEJAQAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Naughtyhuman:BAABLgAECn8UAAIeAAcJPAxYFAAQAQAeAAcJPAxYFAAQAQAAAA==.Navy:BAAALgAECgYJDgABLgAFFAUJFQAJAP8aAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8ZAAMKAAYJRxWyngBBAQAKAAYJehSyngBBAQAfAAQJ0wcOMgCFAAABLgAFFAQJCQAXAAQGAA==.Neodragoonz:BAAALgADCgYJBwABLgAFFAQJCQAXAAQGAA==.',
Ni='Nihilist:BAABLgAECn8cAAINAAkJwB2RDwAGAgANAAkJwB2RDwAGAgAAAA==.Nimbuss:BAAALgAECggJEwAAAA==.Nitequilz:BAABLgAECn9EAAITAAgJQR/hEQC1AgATAAgJQR/hEQC1AgAAAA==.',
No='Noblessyou:BAAALgADCgcJBwABLgAECgUJCAAPAAAAAA==.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJIgAAAA==.Obijuan:BAABLgAECn8iAAIJAAgJrQZXdQBLAQAJAAgJrQZXdQBLAQAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAABLgAECn8lAAMBAAcJjQ92OwBRAQABAAcJPw92OwBRAQAgAAQJYgtWQgC0AAAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIcAAgJ+SFuBwAOAwAcAAgJ+SFuBwAOAwAAAA==.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pa='Pallypocket:BAAALgADCgYJBgAAAA==.',
Pi='Pine:BAABLgAECn8YAAIFAAkJ7wtTLwCUAQAFAAkJ7wtTLwCUAQAAAA==.',
Pl='Plateguy:BAAALgAECgMJAwAAAA==.',
Po='Poxx:BAABLgAFFH8HAAIYAAMJwxoLawAHAQAYAAMJwxoLawAHAQABLgAFFAcJHQAVAGQcAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgAECgIJAgAAAA==.Ranker:BAAALgAECgQJCgAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8TAAQMAAUJNxUYHQBhAQAMAAUJNxUYHQBhAQAaAAIJzRKnKwCNAAAcAAIJAQhqTABiAAAAAA==.Rhayvoke:BAABLgAECn8XAAQXAAcJyxc8HQDdAQAXAAcJkxc8HQDdAQAUAAMJ2gt1OgCWAAAWAAEJGRltOgBHAAABLgAFFAUJEwAMADcVAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAABLgAFFH8JAAMaAAYJLBYxEQArAQAaAAUJoBoxEQArAQAMAAIJ2wjcSABhAAABLgAFFAgJMgALAJwgAA==.Rossini:BAAALgADCgkJCQAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAPAAAAAA==.Rushs:BAAALgAECgEJAgABLgAECgUJCAAPAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8vAAIQAAkJaRoDEwAzAgAQAAkJaRoDEwAzAgAAAA==.Rynron:BAAALgAECgcJDAAAAA==.',
Sa='Sabeatris:BAAALgAECgYJEQAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAABLgAECn8cAAIOAAgJCRqZEABeAgAOAAgJCRqZEABeAgAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgkJGQAQAJILAA==.',
Se='Sempiternal:BAACLgAFFH8cAAIFAAYJ7g8yEwCJAQAFAAYJ7g8yEwCJAQAuAAQKfzYAAgUACQm6E1ItAM8BAAUACQm6E1ItAM8BAAAA.',
Sh='Shadowsmite:BAABLgAECn8UAAIKAAkJzxyjMwAoAgAKAAkJzxyjMwAoAgAAAA==.Shaunanigans:BAABLgAECn8dAAITAAkJpRCGLwDrAQATAAkJpRCGLwDrAQAAAA==.Shaunsdh:BAAALgAECgQJBAABLgAECgkJHQATAKUQAA==.Shaunwick:BAAALgAECgUJBAABLgAECgkJHQATAKUQAA==.Shego:BAACLgAFFH8HAAIRAAMJxiQQCwAuAQARAAMJxiQQCwAuAQAuAAQKfyMABBEACQn8IO8EAGMCAAsABwk6ILgxAHECABEABwkrI+8EAGMCAA0AAgkdIkJIAGIAAAEuAAUUBAkGAAYAMw8A.Sheltered:BAABLgAECn8qAAIKAAkJrCXABABMAwAKAAkJrCXABABMAwAAAA==.',
Si='Sinadora:BAAALgAECgUJCAAAAA==.Sinakra:BAABLgAECn8iAAIKAAkJmw+eZACdAQAKAAkJmw+eZACdAQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAgAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8dAAIVAAcJZBw5AwDJAQAVAAcJZBw5AwDJAQAuAAQKfygAAhUACQniJQACAJcDABUACQniJQACAJcDAAAA.',
Sp='Spritz:BAAALgAECggJEwAAAA==.',
St='Stampede:BAAALgAECgYJDQAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCggJCAAAAA==.Straya:BAABLgAECn8hAAMTAAkJDhW0IgAyAgATAAkJDhW0IgAyAgASAAEJPg1UowAqAAAAAA==.',
Su='Subito:BAAALgADCgkJCQAAAA==.',
Ta='Taburiel:BAAALgADCgEJAQAAAA==.Tahirrah:BAABLgAECn8eAAIJAAkJ7RVBNQD9AQAJAAkJ7RVBNQD9AQAAAA==.Talindra:BAABLgAECn8cAAINAAkJRQYMKgD9AAANAAkJRQYMKgD9AAAAAA==.Tanis:BAAALgAECgYJCwAAAA==.Taylea:BAAALgAECgQJBAAAAA==.',
Te='Temperånce:BAABLgAECn9UAAMhAAkJ8BKaDADfAQAhAAkJ8BKaDADfAQAEAAkJOA0cSgBeAQAAAA==.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJCAAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgAECgcJBwAAAA==.Thumpers:BAAALgADCgcJHgAAAA==.',
Ti='Tino:BAACLgAFFH8OAAIFAAMJtiAkIAAUAQAFAAMJtiAkIAAUAQAuAAQKfy4AAwUACQnqHPkKANMCAAUACQnqHPkKANMCAAoABQkOCzHyALwAAAAA.',
Tm='Tmnt:BAABLgAECn8gAAIMAAgJogsXSwApAQAMAAgJogsXSwApAQAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8ZAAQTAAkJ1x3eagANAQATAAQJdBfeagANAQASAAcJvg/CSQD/AAAdAAUJPgkaKgCQAAAAAA==.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJEQAAAA==.',
Ts='Tsilihin:BAAALgAECgYJCAAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAMAA0eAA==.Tsurenity:BAACLgAFFH8GAAIMAAIJDR6uDgCyAAAMAAIJDR6uDgCyAAAuAAQKfxkAAgwACAm+IjEEACwDAAwACAm+IjEEACwDAAAA.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAFFAEJAQABLgAFFAIJBQAMACAEAA==.',
Uk='Uki:BAAALgADCgQJBAAAAA==.',
Ur='Urbanfries:BAABLgAFFH8KAAMEAAYJ1wcAHwBVAQAEAAYJ1wcAHwBVAQAbAAMJcQHdQgBSAAABLgAFFAUJFwATAIAfAA==.',
Va='Valerus:BAAALgAECgYJDAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAkJNgAMABseAA==.Varr:BAAALgAECgYJDAAAAA==.Vayeda:BAABLgAECn8kAAIYAAkJ7iK8EgDlAgAYAAkJ7iK8EgDlAgAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAQJCQAXAAQGAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAgAAAA==.',
Xe='Xetz:BAABLgAECn8fAAMQAAkJ9gZ1NgA0AQAQAAkJ9gZ1NgA0AQAiAAEJawGKiQAkAAAAAA==.Xezar:BAACLgAFFH8tAAQiAAYJex7QAwAcAgAiAAYJYR7QAwAcAgAOAAYJKRViEgDZAQAQAAQJAAnHDADeAAAuAAQKfycABBAACQk5GzEPAJECABAACQk5GzEPAJECACIABwlrHpoWACcCAA4AAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn82AAMYAAkJ5QsUdACMAQAYAAkJ5QsUdACMAQAjAAQJpwNoFQBxAAAAAA==.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAACLgAFFH8GAAIOAAMJTgi5MQCxAAAOAAMJTgi5MQCxAAAuAAQKfycAAg4ACAkiFuoaAOsBAA4ACAkiFuoaAOsBAAAA.',
Za='Zarigar:BAAALgADCgkJCQAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
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
