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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Shaman-Elemental','Druid-Guardian','Monk-Brewmaster','Druid-Balance','Paladin-Protection','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','Paladin-Holy','DemonHunter-Vengeance','Hunter-Survival','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Frost','Warrior-Fury','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-05-30',data={Ae='Aegisthal:BAACLgAFFH8JAAIBAAQJkRn3DQAuAQABAAQJkRn3DQAuAQAuAAQKfxsAAgEACQldINYEAMACAAEACQldINYEAMACAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgEJAQAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJKgACAFkLAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Althenzdormu:BAABLgAECn8lAAMDAAgJWQuwCwBHAQADAAgJKwmwCwBHAQAEAAcJiAoLQwD8AAAAAA==.Altruist:BAABLgAECn8fAAMFAAgJ3Rv8DAA2AgAFAAgJ3Rv8DAA2AgAGAAIJnAQk+AA2AAABLgAECggJNgABAL0ZAA==.',
Am='Amaethon:BAAALgAECgcJEgAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn85AAIHAAkJVx2DDQDTAgAHAAkJVx2DDQDTAgAAAA==.Andorra:BAAALgADCggJBwAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn82AAIIAAgJQCH0BgDzAgAIAAgJQCH0BgDzAgAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIJAAgJTAgWOwD6AAAJAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Around:BAAALgADCgIJAgAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8uAAQDAAgJ9xV2BgDSAQADAAgJ9xV2BgDSAQALAAQJpxTuHQD2AAAEAAEJsQNcigAmAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn82AAIMAAgJABG/CACkAQAMAAgJABG/CACkAQAAAA==.',
Az='Azbogah:BAAALgAECgQJBAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAANAGkVAA==.Balthenor:BAACLgAFFH8GAAIOAAIJqxMpIgCoAAAOAAIJqxMpIgCoAAAuAAQKfx4AAg4ACAn+IZMRAAQDAA4ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8oAAIJAAkJyRpcDAC1AgAJAAkJyRpcDAC1AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAKAAAAAA==.Berse:BAABLgAECn8YAAICAAYJRB8AaABbAQACAAYJRB8AaABbAQAAAA==.',
Bi='Bilko:BAAALgADCgcJCAAAAA==.Birdymage:BAABLgAECn8VAAIPAAUJHBS/tQD8AAAPAAUJHBS/tQD8AAAAAA==.',
Bl='Blightbeard:BAABLgAECn8VAAIQAAgJLAgUhgBDAQAQAAgJLAgUhgBDAQAAAA==.Blîss:BAAALgAECgYJCAAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAYJHgAQAA4VAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgkJGgAAAA==.',
Br='Brut:BAABLgAECn8eAAIGAAkJAx7XQQCrAQAGAAkJAx7XQQCrAQAAAA==.',
Bu='Bustus:BAABLgAECn8rAAIRAAgJJw0rSABbAQARAAgJJw0rSABbAQAAAA==.',
Ca='Carmasutra:BAAALgADCggJCAAAAA==.Caroll:BAABLgAECn8UAAQSAAcJaRA2LwBBAQASAAcJaRA2LwBBAQAIAAQJcA+jQgDSAAATAAMJexSHQgDKAAAAAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8aAAIOAAYJMQ1VtgD5AAAOAAYJMQ1VtgD5AAAAAA==.',
Ch='Chenzhen:BAAALgAECgUJCgAAAA==.Chilly:BAAALgAECgYJEgABLgAFFAUJDAAJAFIPAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn82AAIBAAgJvRkPDQADAgABAAgJvRkPDQADAgAAAA==.Corannis:BAABLgAECn8qAAIUAAgJURb1IADDAQAUAAgJURb1IADDAQAAAA==.Cowabunga:BAAALgADCgkJCQABLgAECgkJNAAVAFcYAA==.',
Cr='Cranberries:BAABLgAECn8bAAMTAAcJyxf+IgCVAQATAAYJpxj+IgCVAQAIAAcJNRAVKgBfAQAAAA==.Crockett:BAAALgADCgIJAgABLgAECgUJEAAKAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Curtis:BAAALgAECgYJDQABLgAECggJKAAWAJwfAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAECgkJOgAFANIUAA==.Dantez:BAABLgAECn8UAAMXAAgJFh85DAB9AgAXAAgJFh85DAB9AgARAAYJ3A62WQAYAQAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8qAAIGAAkJAhvmGwBZAgAGAAkJAhvmGwBZAgAAAA==.Dawnmane:BAAALgAECgEJAQAAAA==.',
De='Delderach:BAABLgAECn8aAAIYAAYJmRISHQATAQAYAAYJmRISHQATAQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn81AAIQAAkJHRyoHgB9AgAQAAkJHRyoHgB9AgAAAA==.',
Di='Dirkette:BAABLgAECn8oAAIIAAkJKARqMgArAQAIAAkJKARqMgArAQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJKAAIACgEAA==.Dirksavoid:BAAALgAECgUJBQABLgAECgkJKAAIACgEAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8wAAIZAAgJSRvlEQAeAgAZAAgJSRvlEQAeAgAAAA==.',
Dr='Dracmiz:BAAALgAECgEJAQAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgYJDAAKAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drathan:BAAALgADCgYJBQAAAA==.Drewella:BAAALgADCgkJCQAAAA==.',
El='Elaenei:BAAALgADCgkJJgAAAA==.Eliance:BAABLgAECn8aAAIMAAYJHAOfFgCtAAAMAAYJHAOfFgCtAAAAAA==.Elienn:BAAALgAECgEJAQAAAA==.Elsewhere:BAABLgAECn8bAAMEAAkJtQytLABsAQAEAAkJtQytLABsAQALAAEJwQgoPAAkAAAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8lAAIaAAgJoRbJFwCLAQAaAAgJoRbJFwCLAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fa='Fatherbetter:BAAALgAECgEJAQABLgAECgkJJAAGABYhAA==.',
Fe='Feeltheburn:BAAALgAFFAEJAQAAAA==.Feloras:BAAALgAECgYJCwAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.',
Fo='Foxina:BAAALgADCgcJBwAAAA==.',
Fu='Fusaa:BAABLgAECn85AAIbAAkJwRQkMQAIAgAbAAkJwRQkMQAIAgAAAA==.',
Ga='Gallindo:BAAALgADCgYJBgABLgAECgcJEwAKAAAAAA==.Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gelst:BAAALgADCgYJBgAAAA==.Gerbzarrion:BAABLgAECn8YAAIPAAUJfAXs9gCVAAAPAAUJfAXs9gCVAAAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAABLgAECn86AAIFAAkJ0hReEQD1AQAFAAkJ0hReEQD1AQAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAAALgAFFAIJAgAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAKAAAAAA==.Hawknnin:BAABLgAECn8XAAIcAAYJNSR3EgBpAgAcAAYJNSR3EgBpAgAAAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgAECgEJAgAAAA==.',
Hu='Hunterpulled:BAAALgAFFAIJBAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgMJAwAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwATAMsXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8dAAIQAAkJ1Q2wTwDBAQAQAAkJ1Q2wTwDBAQAAAA==.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgcJEwAKAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn8nAAIRAAgJtRuFFgCAAgARAAgJtRuFFgCAAgAAAA==.',
Jo='Johalea:BAAALgAECgEJAQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8UAAIOAAcJMxz+SQDQAQAOAAcJMxz+SQDQAQAAAA==.',
Ka='Kaileena:BAABLgAECn8xAAIdAAkJ0hcpBgAcAgAdAAkJ0hcpBgAcAgAAAA==.Kaimare:BAAALgADCgUJCAAAAA==.Kandistars:BAABLgAECn8jAAIXAAgJUhIAJgCDAQAXAAgJUhIAJgCDAQAAAA==.Kasia:BAABLgAECn8iAAIHAAgJnhtaIgAnAgAHAAgJnhtaIgAnAgAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAIQAAgJiBZgVgCuAQAQAAgJiBZgVgCuAQAAAA==.Kirarah:BAABLgAECn8xAAICAAgJECSgDADaAgACAAgJECSgDADaAgAAAA==.Kirarose:BAACLgAFFH8TAAMSAAUJrBvRDgBbAQASAAUJrBvRDgBbAQATAAIJ2gGdKwBMAAAuAAQKfxwAAxIACQmmIhgPAEwCABIACQmmIhgPAEwCABMAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8xAAIJAAkJOQ9SKAC5AQAJAAkJOQ9SKAC5AQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAAALgAECgUJCwAAAA==.Krunch:BAAALgADCgkJEgABLgAECgYJCgAKAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAINAAgJRhtsBAAyAgANAAgJRhtsBAAyAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8qAAICAAkJOyF6DADbAgACAAkJOyF6DADbAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgQJBgAAAA==.Legenddairy:BAABLgAECn80AAMVAAkJVxiBCQAwAgAVAAkJkBeBCQAwAgAXAAkJRhDxLwCIAQAAAA==.',
Li='Lizardath:BAACLgAFFH8GAAMCAAMJxwSgdACDAAACAAIJAgegdACDAAAeAAMJhwAeJwB/AAAuAAQKfyQAAwIACQmKCcNtAE4BAAIACAkjCsNtAE4BAB4AAgnOBmdKAG8AAAAA.',
Lj='Ljósálfr:BAABLgAECn84AAIBAAkJWSOnAgAKAwABAAkJWSOnAgAKAwAAAA==.',
Lo='Lochramae:BAABLgAECn85AAIaAAkJdxZ6FACyAQAaAAkJdxZ6FACyAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAABLgAECn8kAAIGAAgJFiESFQCGAgAGAAgJFiESFQCGAgAAAA==.',
Ly='Lyssena:BAAALgAECgUJBQAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgADCggJDgABLgAECgYJDAAKAAAAAA==.Mahangi:BAAALgADCgkJEAAAAA==.Mamimisan:BAABLgAECn8uAAIHAAkJHR+NCgD3AgAHAAkJHR+NCgD3AgAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAOAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCggJCAAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJCwAAAA==.',
Mi='Mistazee:BAAALgADCgIJAgAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMVAAcJoRjMEgCiAQAVAAcJoRjMEgCiAQARAAMJ7AZPpwBWAAAAAA==.Mizkat:BAABLgAECn8lAAQVAAkJdxoGCABUAgAVAAkJdxoGCABUAgAfAAEJSw7oQwA1AAARAAIJHA2bzwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Mormra:BAABLgAECn8qAAMCAAgJWQuVZABiAQACAAgJWQuVZABiAQAgAAEJ1QEdPwAeAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQeAAgJlSVXBgCfAgAeAAcJ4iRXBgCfAgACAAYJliQLNwDqAQAgAAIJ/SN9HAC2AAAAAA==.',
['Më']='Mërcy:BAAALgAECgEJAQAAAA==.',
Na='Naklus:BAAALgAECgYJBwAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8aAAIHAAkJtRFaJgAOAgAHAAkJtRFaJgAOAgABLgAECgkJOgAFANIUAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgADCgkJEwAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgYJCgAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJDwAAAA==.',
Ol='Olivia:BAAALgAECgYJBgABLgAFFAgJGQAGACshAA==.',
Or='Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8VAAIfAAYJEBoUEQCDAQAfAAYJEBoUEQCDAQAAAA==.',
Pa='Parne:BAAALgADCggJDQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgIJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8rAAIcAAgJ+RneFwAzAgAcAAgJ+RneFwAzAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn82AAIhAAgJChKNCgB9AQAhAAgJChKNCgB9AQAAAA==.Ranron:BAAALgAECgQJBgAAAA==.Rassaphore:BAABLgAECn8ZAAIZAAgJfh4aCwB9AgAZAAgJfh4aCwB9AgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8iAAIiAAgJwxVnCgCqAQAiAAgJwxVnCgCqAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJHgAGAAMeAA==.Rionach:BAABLgAECn82AAIVAAgJ2QgaLADYAAAVAAgJ2QgaLADYAAAAAA==.Ritsara:BAABLgAECn8UAAIYAAcJyQ1RIgDmAAAYAAcJyQ1RIgDmAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAKAAAAAA==.Rivon:BAABLgAECn8jAAMcAAkJgxh+HQABAgAcAAgJWBd+HQABAgAOAAEJagt7WAE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgUJBwABLgAFFAMJBQAGAJcTAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgYJDAAAAA==.',
Se='Seanan:BAAALgAECgkJEgABLgAECgkJKQAOAHgdAA==.Seanx:BAABLgAECn8pAAMOAAkJeB19HACCAgAOAAkJeB19HACCAgAYAAYJhhJuIAD2AAAAAA==.',
Sh='Shenlong:BAABLgAFFH8GAAIQAAIJrhl3tQCPAAAQAAIJrhl3tQCPAAAAAA==.Shigurexx:BAABLgAECn81AAMCAAkJ+B6LDgDJAgACAAkJ+B6LDgDJAgAgAAYJ4Bc7EAA+AQAAAA==.Shoe:BAABLgAECn8/AAMDAAkJBhz0AgBoAgADAAkJBhz0AgBoAgAEAAcJyxD/IwCiAQAAAA==.Shootup:BAAALgAECgEJAQAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIOAAcJ8gP84AC+AAAOAAcJ8gP84AC+AAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgAECgEJAQAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgUJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgIJAwAAAA==.',
Ta='Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8iAAIBAAgJTRbGEgCoAQABAAgJTRbGEgCoAQAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIVAAQJiBDzDgDjAAAVAAQJiBDzDgDjAAAuAAQKfxwAAhUACQmwH2kEALkCABUACQmwH2kEALkCAAAA.',
Th='There:BAAALgAECgcJDAAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgYJDgAAAA==.',
To='Toom:BAABLgAECn8aAAICAAYJ3QrHiQASAQACAAYJ3QrHiQASAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgIJAgABLgAECgkJOgAFANIUAA==.Trophyhubby:BAABLgAECn8lAAMTAAgJqAxeNgAPAQATAAcJOwxeNgAPAQASAAgJQQblPAD6AAAAAA==.',
Tu='Tuknark:BAAALgAECgEJAQAAAA==.Tuktuvak:BAAALgAECgUJBQABLgAECgkJOAABAFkjAA==.Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgcJEAAAAA==.Tyeriel:BAACLgAFFH8eAAMQAAYJDhXcKACLAQAQAAUJDhXcKACLAQAaAAEJAAANSQAAAAAuAAQKfx8AAxAACQnZHtkiALQCABAACAn/HtkiALQCABoAAwkMGv8tANQAAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAYJHgAQAA4VAA==.',
Us='Usato:BAAALgAECgYJDAAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8UAAIOAAYJkwZb3gDBAAAOAAYJkwZb3gDBAAAAAA==.Valvet:BAAALgADCgkJKwAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8IAAIQAAQJrwRqcwD3AAAQAAQJrwRqcwD3AAAuAAQKfxUAAxoABwnnFBQgADkBABoABQm7GxQgADkBABAABgmxB1i+AOgAAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgQJBAAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIGAAcJHiTjJQBvAgAGAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwAKAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAKAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBwAAAA==.',
['Vá']='Vásh:BAAALgADCgkJEQAAAA==.',
We='Webjibaro:BAAALgAECgMJBgAAAA==.Weeblewobble:BAAALgAECgEJAQAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCQAAAA==.William:BAABLgAECn8fAAICAAkJmSG2BwANAwACAAkJmSG2BwANAwAAAA==.Windee:BAABLgAECn8ZAAIZAAYJqg15PQDxAAAZAAYJqg15PQDxAAAAAA==.',
Wr='Wrast:BAABLgAECn8gAAMgAAgJqAeoGADXAAACAAYJeQmBkgD/AAAgAAcJkwaoGADXAAAAAA==.Wravyn:BAAALgAECgQJBQAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMNAAQJuw5VCgCqAAAbAAMJgAiWcADJAAANAAIJuhVVCgCqAAAuAAQKfyYABA0ACQk0HYMDAF0CAA0ACQk0HYMDAF0CABsABgmmEtpnAGIBACEAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAABLgAECn86AAIjAAkJxyC7BQDzAgAjAAkJxyC7BQDzAgAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8MAAIkAAQJfgySCAATAQAkAAQJfgySCAATAQAuAAQKfxgAAiQACQnKHGsFAHkCACQACQnKHGsFAHkCAAAA.Zatika:BAABLgAECn8zAAMPAAkJHhgZOQAdAgAPAAkJKRUZOQAdAgAlAAcJ1xjmBgCgAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8aAAIXAAYJmAbPTgC1AAAXAAYJmAbPTgC1AAAAAA==.',
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
