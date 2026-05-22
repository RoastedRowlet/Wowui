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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Priest-Holy','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Vengeance','Druid-Balance','Priest-Shadow','Druid-Feral','Hunter-Marksmanship','Hunter-Survival','Paladin-Holy','Warlock-Destruction','DeathKnight-Frost','Paladin-Protection','Warrior-Fury','Shaman-Enhancement','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-05-16',data={Ae='Aegisthal:BAABLgAECn8ZAAIBAAgJxh4pCQAbAgABAAgJxh4pCQAbAgAAAA==.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgADCgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJJAACAEMLAA==.',
Ak='Akélla:BAAALgAECgkJCQAAAA==.',
Al='Alanerazza:BAAALgADCgYJBgAAAA==.Althenzdormu:BAABLgAECn8YAAMDAAYJRQyQDQDuAAADAAYJOAmQDQDuAAAEAAUJvAt0RwC3AAAAAA==.Altruist:BAABLgAECn8VAAMFAAYJXRqdFgBrAQAFAAYJXRqdFgBrAQAGAAIJnARdzAA9AAABLgAECggJJwABAGcXAA==.',
Am='Amaethon:BAAALgAECgYJDgAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8nAAIHAAgJ0h/vDACiAgAHAAgJ0h/vDACiAgAAAA==.Andorra:BAAALgADCgUJBAAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8nAAIIAAgJaR76BwCpAgAIAAgJaR76BwCpAgAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIJAAgJTAgWOwD6AAAJAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8nAAQDAAgJDhWnBQC6AQADAAgJDhWnBQC6AQALAAQJpxQpGQD5AAAEAAEJsQPgdAAnAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8nAAIMAAgJwAsNCQBrAQAMAAgJwAsNCQBrAQAAAA==.',
Az='Azbogah:BAAALgADCgkJEgAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAANAGkVAA==.Balthenor:BAACLgAFFH8GAAIOAAIJqxMpIgCoAAAOAAIJqxMpIgCoAAAuAAQKfx4AAg4ACAn+IZMRAAQDAA4ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8eAAIJAAkJyRqRCAC0AgAJAAkJyRqRCAC0AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAKAAAAAA==.Berse:BAABLgAECn8YAAICAAYJRB9TSQBsAQACAAYJRB9TSQBsAQAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgUJEQAAAA==.',
Bl='Blightbeard:BAAALgAECgYJEwAAAA==.Blîss:BAAALgAECgUJBQAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAUJGQAPAH8UAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgcJDwAAAA==.',
Br='Brut:BAABLgAECn8YAAIGAAgJdx0EOQAQAgAGAAgJdx0EOQAQAgAAAA==.',
Bu='Bustus:BAABLgAECn8kAAIQAAgJJw2KPABZAQAQAAgJJw2KPABZAQAAAA==.',
Ca='Carmasutra:BAAALgADCgYJBQAAAA==.Caroll:BAAALgAECgUJBgAAAA==.Carsomavra:BAAALgADCggJGwAAAA==.Cathercy:BAAALgAECgUJDgAAAA==.',
Ch='Chenzhen:BAAALgADCgYJBgAAAA==.Chilly:BAAALgAECgYJDgABLgAFFAMJAwAKAAAAAA==.Chunt:BAAALgAECgIJAgAAAA==.',
Co='Compliance:BAABLgAECn8nAAIBAAgJZxfjDQC8AQABAAgJZxfjDQC8AQAAAA==.Corannis:BAABLgAECn8bAAIRAAgJdxHyJABqAQARAAgJdxHyJABqAQAAAA==.Cowabunga:BAAALgADCgkJCQABLgAECgkJJQASAJwQAA==.',
Cr='Cranberries:BAABLgAECn8UAAMTAAcJEBdWGwCjAQATAAYJpxhWGwCjAQAIAAcJYw+UIABrAQAAAA==.Crockett:BAAALgADCgIJAgABLgAECgUJCwAKAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Curtis:BAAALgAECgYJDQABLgAECggJGAAUAMgaAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJBQAAAA==.Dalra:BAAALgADCgUJBQABLgAECggJMAAFACwVAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8cAAIGAAgJARgrLQDKAQAGAAgJARgrLQDKAQAAAA==.',
De='Delderach:BAAALgAECgUJDgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8lAAIPAAgJ6Rc1OgDRAQAPAAgJ6Rc1OgDRAQAAAA==.',
Di='Dirkette:BAABLgAECn8iAAIIAAgJ+QMTLAAXAQAIAAgJ+QMTLAAXAQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECggJIgAIAPkDAA==.Dirksavoid:BAAALgAECgUJBQABLgAECggJIgAIAPkDAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8jAAIVAAgJIhj9EgDXAQAVAAgJIhj9EgDXAQAAAA==.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgMJAwAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgUJBQAKAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drathan:BAAALgADCgYJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCggJFAAAAA==.Eliance:BAAALgAECgUJDgAAAA==.Elienn:BAAALgADCgcJBwAAAA==.Elsewhere:BAABLgAECn8YAAMEAAgJAA0PKgA/AQAEAAgJAA0PKgA/AQALAAEJwQheMwAkAAAAAA==.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8fAAIWAAgJ8RSBFgBcAQAWAAgJ8RSBFgBcAQAAAA==.',
Eu='Eunja:BAEALgAECgYJBgAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fe='Feeltheburn:BAAALgAECgYJBgAAAA==.Feloras:BAAALgAECgUJBQAAAA==.',
Fu='Fusaa:BAABLgAECn8oAAIXAAgJshOnPwCfAQAXAAgJshOnPwCfAQAAAA==.',
Ga='Gallindo:BAAALgADCgYJBgABLgAECgYJDQAKAAAAAA==.Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gelst:BAAALgADCgUJBQAAAA==.Gerbzarrion:BAAALgAECgUJDgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAABLgAECn8wAAIFAAgJLBWOEAC5AQAFAAgJLBWOEAC5AQAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Hawknnin:BAAALgAECgUJCwAAAA==.',
He='Hechicera:BAAALgAECgkJCQAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBQAAAA==.Huroona:BAAALgADCgcJEAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJFAATABAXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8ZAAIPAAgJcgzUWgBuAQAPAAgJcgzUWgBuAQAAAA==.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgYJDQAKAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn8YAAIQAAYJFBr2KwCxAQAQAAYJFBr2KwCxAQAAAA==.',
Jo='Johalea:BAAALgADCgYJBQAAAA==.',
['Jå']='Jåsper:BAAALgAECgcJEgAAAA==.',
Ka='Kaileena:BAABLgAECn8kAAIYAAgJ0hefBgDRAQAYAAgJ0hefBgDRAQAAAA==.Kaimare:BAAALgADCgUJBgAAAA==.Kandistars:BAABLgAECn8cAAIZAAgJIgwPKQAsAQAZAAgJIgwPKQAsAQAAAA==.Kasia:BAABLgAECn8YAAIHAAYJOx91KgC4AQAHAAYJOx91KgC4AQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8ZAAIPAAgJiBZ3QgC1AQAPAAgJiBZ3QgC1AQAAAA==.Kirarah:BAABLgAECn8iAAICAAgJ2yJxDQChAgACAAgJ2yJxDQChAgAAAA==.Kirarose:BAACLgAFFH8NAAMaAAQJfBD2DwA5AQAaAAQJfBD2DwA5AQATAAIJ2gEMIQBbAAAuAAQKfxUAAxoABwneHWEWADUCABoABwneHWEWADUCABMAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8hAAIJAAgJhw/TIQCMAQAJAAgJhw/TIQCMAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJGAAAAA==.',
Ky='Kylia:BAABLgAECn8VAAINAAYJ4RzKBwCEAQANAAYJ4RzKBwCEAQAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8gAAICAAgJLiDUGgA3AgACAAgJLiDUGgA3AgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8lAAMSAAkJnBBJEABxAQAZAAkJBg/xLwCIAQASAAkJsg1JEABxAQAAAA==.',
Li='Lizardath:BAABLgAECn8gAAICAAgJAQoVUwBPAQACAAgJAQoVUwBPAQAAAA==.',
Lj='Ljósálfr:BAABLgAECn8rAAIBAAkJGSIhAwDPAgABAAkJGSIhAwDPAgAAAA==.',
Lo='Lochramae:BAABLgAECn8oAAIWAAgJ2xWjFQBmAQAWAAgJ2xWjFQBmAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJBwAAAA==.',
Lu='Lumanoughty:BAAALgADCggJFAAAAA==.Lunargaze:BAABLgAECn8bAAIGAAcJTSA1HwAUAgAGAAcJTSA1HwAUAgAAAA==.',
Ly='Lyssena:BAAALgAECgUJBQABLgAECggJEQAKAAAAAA==.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgUJBQAKAAAAAA==.Mahangi:BAAALgADCgkJEAAAAA==.Mamimisan:BAABLgAECn8iAAIHAAgJUx/rCwCwAgAHAAgJUx/rCwCwAgAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAOAKsTAA==.Medios:BAAALgAECgYJBwAAAA==.Metalicfox:BAAALgADCgQJBQAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgYJDwAAAA==.Mizkat:BAABLgAECn8eAAQSAAgJSRmJCgDUAQASAAgJSRmJCgDUAQAbAAEJSw6HMgAzAAAQAAIJHA2bzwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Mormra:BAABLgAECn8kAAMCAAgJQwvrTgBbAQACAAgJQwvrTgBbAQAcAAEJ1QGfNQAeAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQdAAgJlCUzCABgAgAdAAcJ4iQzCABgAgACAAYJlSTlJAD+AQAcAAIJ/SPnFgC+AAAAAA==.',
['Më']='Mërcy:BAAALgADCgcJBwAAAA==.',
Na='Naklus:BAAALgAECgUJBQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECggJEQABLgAECggJMAAFACwVAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgADCgQJBQAAAA==.',
Ni='Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgYJCgAAAA==.',
Nu='Nuvi:BAAALgAECgMJAwAAAA==.',
Ol='Olivia:BAAALgADCgYJBgABLgAFFAgJGQAGACshAA==.',
Or='Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAAALgAECgQJDAAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8cAAIeAAgJgRiDFgAKAgAeAAgJgRiDFgAKAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Qu='Quetzalcoatl:BAAALgAECgkJCQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8nAAIfAAgJ/w4RCgBSAQAfAAgJ/w4RCgBSAQAAAA==.Rassaphore:BAAALgAECgYJDgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8YAAIgAAYJfxjJCwA7AQAgAAYJfxjJCwA7AQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJGAAGAHcdAA==.Rionach:BAABLgAECn8nAAISAAgJjge9IADEAAASAAgJjge9IADEAAAAAA==.Ritsara:BAAALgAECgcJEgAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAKAAAAAA==.Rivon:BAABLgAECn8aAAIeAAYJORcTLQBbAQAeAAYJORcTLQBbAQAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgUJBwABLgAECgcJGQAGAJ0cAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgMJBQAAAA==.',
Se='Seanx:BAABLgAECn8oAAMOAAgJGB9CHABZAgAOAAgJGB9CHABZAgAhAAYJhhLZGAD/AAAAAA==.',
Sh='Shenlong:BAABLgAFFH8FAAIPAAIJrhnthACjAAAPAAIJrhnthACjAAAAAA==.Shigurexx:BAABLgAECn8lAAMCAAkJEh0jEACIAgACAAkJEh0jEACIAgAcAAYJbRKuQgBNAQAAAA==.Shoe:BAABLgAECn86AAMDAAkJBBzfAQCFAgADAAkJBBzfAQCFAgAEAAYJmRANKABLAQAAAA==.Shootup:BAAALgADCgYJBgAAAA==.',
Si='Sigmandis:BAAALgAECgcJEgAAAA==.Siph:BAAALgAECgYJCQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgcJEQAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJCwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Sybryn:BAAALgADCgQJBAAAAA==.',
Ta='Taliadrin:BAAALgAECgIJAgAAAA==.Tamarins:BAABLgAECn8YAAIBAAYJthu7EwBjAQABAAYJthu7EwBjAQAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAACLgAFFH8FAAISAAMJXw6sCwCzAAASAAMJXw6sCwCzAAAuAAQKfxwAAhIACQmwH9QCAL8CABIACQmwH9QCAL8CAAAA.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgMJBAAAAA==.',
To='Toom:BAAALgAECgUJDgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJMAAFACwVAA==.Trophyhubby:BAABLgAECn8fAAMTAAgJGwySRgAfAQATAAYJDg2SRgAfAQAaAAgJZATcMwD1AAAAAA==.',
Tu='Tuknark:BAAALgADCgYJBgAAAA==.Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDgAAAA==.Tyeriel:BAACLgAFFH8ZAAMPAAUJfxRaOwBAAQAPAAQJfxRaOwBAAQAWAAEJAABONQAAAAAuAAQKfx8AAw8ACQnZHtkiALQCAA8ACAn/HtkiALQCABYAAwkMGqEjAOAAAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAUJGQAPAH8UAA==.',
Us='Usato:BAAALgAECgUJBQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgUJCAAAAA==.Valvet:BAAALgADCgkJKQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAAALgAECgcJDwAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIGAAcJFSTjJQBvAgAGAAcJFSTjJQBvAgAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAKAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
['Vá']='Vásh:BAAALgADCggJCAAAAA==.',
We='Weeblewobble:BAAALgADCggJCgAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCQAAAA==.William:BAABLgAECn8UAAICAAcJuh3fKADqAQACAAcJuh3fKADqAQAAAA==.Windee:BAAALgAECgYJEgAAAA==.',
Wr='Wrast:BAABLgAECn8XAAIcAAcJkgZeFADZAAAcAAcJkgZeFADZAAAAAA==.Wravyn:BAAALgADCgcJBwAAAA==.',
Xy='Xyara:BAABLgAECn8mAAQNAAkJNB2lAQCEAgANAAkJNB2lAQCEAgAXAAYJphIFTwBvAQAfAAMJoBNmOwDGAAAAAA==.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8oAAIiAAkJfh8uCACbAgAiAAkJfh8uCACbAgAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAABLgAFFH8FAAIjAAMJ9wsrBwDaAAAjAAMJ9wsrBwDaAAAAAA==.Zatika:BAABLgAECn8qAAMkAAkJ2hV+AwCmAQAlAAkJbhCEPwDcAQAkAAcJthh+AwCmAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAAALgAECgUJDgAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
