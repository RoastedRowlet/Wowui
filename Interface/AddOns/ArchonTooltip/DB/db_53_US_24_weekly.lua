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

local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warlock-Demonology','Mage-Arcane','Mage-Frost','Druid-Feral','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Blood','Rogue-Outlaw','Monk-Brewmaster','Warlock-Destruction','Druid-Guardian','Druid-Balance','Paladin-Holy','Evoker-Augmentation','Priest-Shadow','Warrior-Fury','DeathKnight-Frost','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Druid-Restoration','Hunter-BeastMastery','Paladin-Protection','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Devourer','Priest-Holy','Hunter-Survival','Warrior-Protection','Priest-Discipline','Warlock-Affliction',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Actualape:BAAANQAECgQIBgAAAA==.',
Ad='Addy:BAABNQAECoEhAAIBAAgK8xiXIwBYAgABAAgK8xiXIwBYAgAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAAANQAECgUIDgAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQAECgIIAgAAAA==.Aispere:BAAANQADCgYICgABNQAECgEIAgACAAAAAA==.',
Al='Alerzhulan:BAAANQAECgUIEAAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAAANQAECgcIEwAAAA==.Alorely:BAAANQAECgYIEQAAAA==.',
Am='Amanara:BAAANQAECgUIDAAAAA==.Amoonia:BAAANQADCgYIEAAAAA==.',
An='Anciientpaw:BAABNQAECoEeAAMDAAgKux9iJQCwAgADAAgKux9iJQCwAgAEAAMKrA/82QCrAAAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgYIDgAAAA==.Anguirus:BAABNQAECoEfAAIEAAgKoAQOlABCAQAEAAgKoAQOlABCAQAAAA==.Anitax:BAAANQAECgQIBQABNQAECgkJGAAEAIAYAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIFAAAAA==.Arcadian:BAABNQAECoErAAIFAAgKqQ81hADtAQAFAAgKqQ81hADtAQAAAA==.Arceeprime:BAAANQADCgcICQAAAA==.Arextheelder:BAAANQAECgUIDAAAAA==.Argentum:BAAANQADCggICAABNQAECggIIQABAPMYAA==.Armorscales:BAABNQAECoEdAAIGAAkK/x+bJgDSAgAGAAkK/x+bJgDSAgAAAA==.Arntraz:BAAANQAECgIIAwAAAA==.Arrabbiato:BAAANQAECggIDgAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQADCggIDQAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAAANQAECgQIDAAAAA==.Astayoni:BAAANQAECgQIBgAAAA==.Asterfleur:BAAANQADCgYIBwABNQAECgUIBgACAAAAAA==.Astrine:BAABNQAECoEgAAMHAAkK2xRfiQBSAgAHAAkKlBJfiQBSAgAIAAYKOhHbFwAVAQAAAA==.',
At='Ataraxya:BAAANQAECgUIBwAAAA==.',
Au='Auberon:BAABNQAECoEgAAIJAAkKBhZ1CQB8AgAJAAkKBhZ1CQB8AgAAAA==.Aufta:BAABNQAECoEXAAMKAAYKNgUqLQDXAAAKAAYKNgUqLQDXAAALAAUKbgZeQgDOAAAAAA==.Aumer:BAAANQADCggICAAAAA==.Aura:BAAANQADCgcIBwAAAA==.',
Az='Azi:BAACNQAFFIEJAAIMAAQKghJyDgApAQAMAAQKghJyDgApAQA1AAQKgSgAAgwACQoxH6wOAOcCAAwACQoxH6wOAOcCAAAA.Azurite:BAAANQADCgYIFQAAAA==.',
Ba='Backpedal:BAAANQAECgIIAgAAAA==.Badankhadonk:BAACNQAFFIEIAAMDAAQKTxfuDABSAQADAAQKTxfuDABSAQAEAAEK1g6rKABKAAA1AAQKgTQAAwMACQr7JI4DAKMDAAMACQr7JI4DAKMDAAQABArKGliSAEYBAAAA.Bakkutteh:BAAANQABCgIIBAAAAA==.Bakuhiko:BAAANQAECgQIBgAAAA==.Balen:BAAANQAECgQICAAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.Bariden:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAACNQAFFIEHAAINAAQK+BMSCwA2AQANAAQK+BMSCwA2AQA1AAQKgR4AAg0ACApLIc8VAPQCAA0ACApLIc8VAPQCAAAA.Beethozart:BAAANQADCggIEAAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAAANQAECgUIDAAAAA==.Beliice:BAAANQADCgIIAgABNQAECgUIDAACAAAAAA==.Bellafleur:BAAANQAECgQIBAABNQAECgUIBgACAAAAAA==.Bellawesome:BAAANQABCgQIBAAAAA==.Bendeekay:BAACNQAFFIEJAAIOAAQKlB7cCwBpAQAOAAQKlB7cCwBpAQA1AAQKgS0AAg4ACQpmIn0JAF4DAA4ACQpmIn0JAF4DAAAA.Benilok:BAAANQAECgYIEQAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bf='Bfh:BAAANQADCgQIBAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQAECgEIAQAAAA==.',
Bl='Blackblood:BAABNQAECoEYAAIBAAcKzgwQQQCAAQABAAcKzgwQQQCAAQAAAA==.Bloodache:BAAANQAECgYIDgAAAA==.Blux:BAAANQAECgIIAwAAAA==.',
Bo='Boil:BAABNQAECoEbAAIPAAcKEgTvDwALAQAPAAcKEgTvDwALAQAAAA==.Bonemarrow:BAAANQAECgMIBQAAAA==.Bordin:BAAANQADCgEIAQAAAA==.',
Br='Brakeable:BAAANQADCgIIBAAAAA==.Braké:BAAANQAECgYIEAAAAA==.Brewskies:BAABNQAECoEkAAIQAAgK+yPKAwA0AwAQAAgK+yPKAwA0AwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brioche:BAAANQADCgUIBgAAAA==.Brionthicc:BAAANQAECgMIBQABNQAFFAQICgARADgRAA==.Brownington:BAABNQAECoEgAAQSAAgKmyNCGwCFAQATAAYKjyEGNgASAgASAAQKZiJCGwCFAQAJAAIK0yE8JAC7AAAAAA==.Bruhilda:BAAANQAECgUIDQAAAA==.Brìonik:BAACNQAFFIEKAAMRAAQKOBGhCQCqAAARAAIKxRehCQCqAAAGAAIKrAquKwCPAAA1AAQKgS8AAxEACQo/H3UGAJwCABEACAp0HXUGAJwCAAYABwqgGihbACQCAAAA.',
Bu='Bubbleroundi:BAABNQAECoEoAAIUAAgK0hDGVQD3AQAUAAgK0hDGVQD3AQAAAA==.Bubudder:BAABNQAECoEmAAINAAgK7yRpEQAWAwANAAgK7yRpEQAWAwAAAA==.Buffstuff:BAABNQAECoEXAAIVAAgK+xAyCQDGAQAVAAgK+xAyCQDGAQAAAA==.Burgerlock:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAAANQAECgYIEAAAAA==.Canadaishere:BAAANQADCgMIAwAAAA==.Cantheartitz:BAAANQAECgQJCAAAAA==.Catdav:BAAANQAECgUIDAAAAA==.',
Ch='Charbol:BAAANQADCgQIBAABNQADCggICAACAAAAAA==.Chelraani:BAAANQAECgYIDQAAAA==.Chess:BAAANQAECgcICwAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBgAAAA==.',
Ci='Ciarianna:BAAANQADCgcIBwABNQAECggIIQABAPMYAA==.Cigar:BAAANQADCgUICQABNQAECgYIEAACAAAAAA==.',
Cl='Clazzicola:BAACNQAFFIEGAAILAAQKzxBTCAAeAQALAAQKzxBTCAAeAQA1AAQKgR8AAgsACQrtIJcRALQCAAsACQrtIJcRALQCAAAA.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgMICAAAAA==.Coogsayer:BAAANQADCgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.',
Cp='Cptncrush:BAABNQAECoEYAAIDAAcKKxyWRwAYAgADAAcKKxyWRwAYAgAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.Creature:BAAANQAECgEIAgAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAABNQAECoEeAAIWAAgKqhVXHwAbAgAWAAgKqhVXHwAbAgAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAACNQAFFIEKAAIXAAQKmBrPAABqAQAXAAQKmBrPAABqAQA1AAQKgS8AAhcACQplJYEAAMkDABcACQplJYEAAMkDAAAA.',
Da='Dadbodftw:BAAANQAECgQIDQAAAA==.Daddylight:BAAANQAECgUIEAAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgUICwAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgQIAwAAAA==.',
De='Deadlight:BAABNQAECoEjAAIYAAgKcQ2eOgClAQAYAAgKcQ2eOgClAQAAAA==.Deadtofall:BAAANQADCgYIEAAAAA==.Deathshikzs:BAABNQAECoEfAAIOAAgKNxoMLQBGAgAOAAgKNxoMLQBGAgABNQAECgkJGAAEAIAYAA==.Decix:BAAANQAECgIIAgABNQAFFAMICAAWAOQSAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAABNQAECoEWAAIXAAkKeR82AgBCAwAXAAkKeR82AgBCAwABNQAECgkJHQALAHEaAA==.Demonllxll:BAAANQAECgUIDgAAAA==.Demontime:BAAANQADCgcIDAABNQAECgQIBAACAAAAAA==.Desolation:BAABNQAECoEjAAIHAAgKcCMDNwAOAwAHAAgKcCMDNwAOAwAAAA==.Despia:BAAANQAECgYIDQAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAAANQAECgYIDQAAAA==.Diety:BAABNQAECoEdAAILAAkKcRrKEAC+AgALAAkKcRrKEAC+AgAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgUIBwAAAA==.',
Dj='Djpallyd:BAABNQAECoEfAAIZAAkK3RK3ZwA3AgAZAAkK3RK3ZwA3AgAAAA==.',
Do='Dotmami:BAAANQAECgcICwAAAA==.Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECoEyAAMaAAkKhyANBQBTAwAaAAkKhyANBQBTAwAbAAEKIQ04OAA1AAAAAA==.Draktyr:BAACNQAFFIEGAAIFAAMKORlqGgD4AAAFAAMKORlqGgD4AAA1AAQKgSsAAwUACQrTIGIcADkDAAUACQrTIGIcADkDABcAAQosBuEvAC4AAAAA.Drlovely:BAAANQADCgQJBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Elianda:BAAANQADCgYIBgAAAA==.Ellalais:BAAANQAECgQICgAAAA==.Ellismom:BAABNQAECoEjAAINAAgKZh0UMQBGAgANAAgKZh0UMQBGAgAAAA==.',
En='Enamorada:BAAANQAECgEJAQABNQAECgcIFQADAC0XAA==.Enchanceurpp:BAAANQADCggIGQAAAA==.End:BAAANQAECgIIAgAAAA==.',
Eo='Eolyndyn:BAAANQADCgQIBQAAAA==.',
Er='Ereithelda:BAACNQAFFIEJAAIKAAQKDRmJBABZAQAKAAQKDRmJBABZAQA1AAQKgS8AAgoACQofJI8CAIIDAAoACQofJI8CAIIDAAAA.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAECgkJMgAaAIcgAA==.Errutu:BAABNQAECoEkAAIcAAgKAxJRFwATAgAcAAgKAxJRFwATAgAAAA==.',
Ev='Evox:BAAANQAECgUICQAAAA==.',
Fa='Falgar:BAAANQADCgQIBAAAAA==.Fann:BAABNQAECoEYAAIdAAcKGgZ2OgAVAQAdAAcKGgZ2OgAVAQAAAA==.Fargrim:BAAANQADCggICAAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgIIAgAAAA==.Fewz:BAACNQAFFIEJAAMIAAQKOxkwAQA2AQAIAAMKGiAwAQA2AQAHAAEKoAROWAA/AAA1AAQKgTIAAwgACQq7JXIAAMQDAAgACQq7JXIAAMQDAAcAAQoQD1ShAT4AAAAA.',
Fl='Flakflap:BAAANQAECgUIBQABNQAFFAIIBQAOADsPAA==.Flakov:BAAANQADCggIDgABNQAFFAIIBQAOADsPAA==.Flaktop:BAACNQAFFIEFAAIOAAIKOw/mHQB5AAAOAAIKOw/mHQB5AAA1AAQKgS8AAg4ACQoZHwIaAMYCAA4ACQoZHwIaAMYCAAAA.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgQIBQAAAA==.Fluffie:BAAANQABCgcICgAAAA==.',
Fo='Forbacon:BAABNQAECoEeAAIOAAgKexqlLABIAgAOAAgKexqlLABIAgAAAA==.Force:BAABNQAECoEXAAMYAAcKcwS1VQAIAQAYAAcKcwS1VQAIAQANAAEKRwNZ3wAiAAAAAA==.Fouris:BAAANQAECgIIAgAAAA==.',
Fr='Fridgie:BAACNQAFFIEKAAIeAAQKvA+9DQBBAQAeAAQKvA+9DQBBAQA1AAQKgS0AAh4ACQr4ItIVAC0DAB4ACQr4ItIVAC0DAAAA.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIDQAAAA==.Frozenturtle:BAAANQAECgUIDAAAAA==.',
Ft='Ftwiamtank:BAAANQAECgcIDAAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAACNQAFFIEFAAIHAAQK1QztIgAwAQAHAAQK1QztIgAwAQA1AAQKgSkAAgcACQpvHLVbALUCAAcACQpvHLVbALUCAAAA.',
Ge='Geddan:BAAANQADCgYICAAAAA==.Genericck:BAAANQAECgUIBgAAAA==.Genericdh:BAAANQAFFAEIAQAAAA==.Genericpal:BAABNQAECoEpAAMfAAkK/yC4BwAMAwAfAAgKXSO4BwAMAwAZAAIK8Q9QQAF1AAAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.',
Gn='Gnawbear:BAEBNQAECoEeAAIgAAgKQheLHgBhAgAgAAgKQheLHgBhAgAAAA==.',
Go='Goatassassin:BAABNQAECoEaAAMcAAgKMBPWFQAjAgAcAAgKchLWFQAjAgAgAAIKawqZeQBwAAAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECggIGgAcADATAA==.Gobogoolina:BAAANQADCgUICAAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQAECgQIBwAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Haikuu:BAAANQADCgcIBwAAAA==.Hamnqueso:BAAANQADCgYIDgABNQAECgQIDQACAAAAAA==.Hardeesdelux:BAAANQAECgQICAAAAA==.Hazis:BAACNQAFFIEFAAIOAAMK5hGHFQDQAAAOAAMK5hGHFQDQAAA1AAQKgTMAAg4ACQoHH00RAA4DAA4ACQoHH00RAA4DAAAA.',
Hi='Hinala:BAABNQAECoEfAAIOAAkKrgpAUACTAQAOAAkKrgpAUACTAQAAAA==.',
Ho='Holy:BAAANQAECgUIBQABNQAECgkJLwAEAEwcAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAABNQAECoEjAAMFAAkKxCR6CwCVAwAFAAkKxCR6CwCVAwAXAAEKdRMBKwA+AAAAAA==.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgUIDQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAABNQAECoEiAAIeAAgKnSJyHQAHAwAeAAgKnSJyHQAHAwAAAA==.',
In='Inanitas:BAAANQADCggICAAAAA==.Innominot:BAAANQAECgQIBQAAAA==.',
Ir='Irukox:BAAANQADCgIIAwAAAA==.',
Ja='Jackoldean:BAAANQADCgUICwAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jalene:BAAANQAECgQICAAAAA==.Jargen:BAAANQADCgYIBwABNQADCggICAACAAAAAA==.',
Je='Jettabae:BAAANQAECgIIAgABNQAFFAQICgAZANsJAA==.Jettadari:BAAANQAECgYICgABNQAFFAQICgAZANsJAA==.Jettadin:BAACNQAFFIEKAAIZAAQK2wkpEAAIAQAZAAQK2wkpEAAIAQA1AAQKgSIAAhkACQoGIgQdADkDABkACQoGIgQdADkDAAAA.',
Jt='Jt:BAAANQAECgQIBQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAACNQAFFIEKAAIDAAQKPxpvDABcAQADAAQKPxpvDABcAQA1AAQKgSgAAwMACQoyIuMSABoDAAMACQoyIuMSABoDACEABArtDAAkAN8AAAAA.',
Ka='Kakozaps:BAACNQAFFIEJAAMhAAQKvxqCAgBkAQAhAAQKvxqCAgBkAQAEAAEKmAzTKQBHAAA1AAQKgTsAAyEACQrEIicCAI0DACEACQpmIicCAI0DAAQACArFIPUsAKYCAAAA.Kallar:BAAANQAECgcIEAAAAA==.Kathrynne:BAAANQAECgMIAwAAAA==.Kayeera:BAAANQAECgQIBgAAAA==.Kaylrandi:BAAANQADCgUIEQAAAA==.Kayna:BAAANQAECgUIBQAAAA==.',
Ke='Kearza:BAAANQAECgMIBQAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgYIFwAZAKkbAA==.Kennethv:BAAANQAECgUIDAAAAA==.Keny:BAAANQAECgUJBgABNQAECgYIDwACAAAAAA==.Kero:BAAANQADCgcICgABNQAECgcIEAACAAAAAA==.Kethie:BAAANQADCgcIBwAAAA==.Kethra:BAAANQADCgQIBAAAAA==.Kev:BAAANQAECggIAwAAAA==.',
Kh='Khalesie:BAAANQADCgIIBAAAAA==.Khibanee:BAAANQAECgMIBQAAAA==.Khiell:BAABNQAECoEgAAMXAAgKPhqQBwBSAgAXAAcKuxuQBwBSAgAFAAIKxw88GQFrAAAAAA==.Khrominius:BAAANQAECgYIDwAAAA==.',
Ki='Kinigit:BAAANQAECgUJCgABNQAFFAQICQATABITAA==.Kirïtö:BAAANQADCgMIAwAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAABNQAECoElAAIHAAkKRRdEXQCyAgAHAAkKRRdEXQCyAgAAAA==.',
Ko='Komamura:BAAANQAECgMIAwAAAA==.Konpalitaa:BAAANQAECgEIAQAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.Krátos:BAAANQAECgcIEgAAAA==.',
Ku='Kungphu:BAAANQADCgYIBwAAAA==.Kuranaa:BAAANQAECgEIAgAAAA==.Kurulak:BAABNQAECoEbAAIiAAcKBQslMwCEAQAiAAcKBQslMwCEAQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.Kynn:BAAANQADCgMIAwAAAA==.',
La='Lacerveza:BAAANQAECgMIBAAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.Laylah:BAAANQADCgMIBQAAAA==.',
Le='Leriope:BAABNQAECoEkAAIGAAgKXRAIdADcAQAGAAgKXRAIdADcAQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgUIDQABNQAECggIIQAFAKAdAA==.Lilem:BAAANQADCgYICAAAAA==.Limboh:BAAANQADCgcIBwAAAA==.',
Lj='Lj:BAABNQAECoEbAAIUAAgK5Rz9LQCTAgAUAAgK5Rz9LQCTAgAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcIGwAAAA==.Mager:BAAANQAECgIIAwAAAA==.Mageshyte:BAACNQAFFIEFAAIHAAMKUA/rKwDuAAAHAAMKUA/rKwDuAAA1AAQKgS0AAgcACQrnHvVDAO0CAAcACQrnHvVDAO0CAAAA.Magolock:BAAANQAECgUIDQAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAABNQAECoEsAAIgAAkKmCAUEQDVAgAgAAkKmCAUEQDVAgAAAA==.Mamajumbo:BAAANQAECgYIDgAAAA==.Mana:BAABNQAECoEvAAIEAAkKTBwpJADWAgAEAAkKTBwpJADWAgAAAA==.Marellias:BAABNQAECoEUAAMeAAgKahs1QACGAgAeAAgKahs1QACGAgAMAAEK7wZsfgAxAAABNQAECggIHAAZAOolAA==.Marikel:BAAANQAECgQIBwAAAA==.Marlea:BAAANQAECgYIEgAAAA==.Maruka:BAABNQAECoEtAAIGAAkKlh+ZEQA2AwAGAAkKlh+ZEQA2AwAAAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Meronpan:BAAANQADCgUIBwAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAAANQAECgYIEAAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIJAgAAAA==.Migrains:BAABNQAECoEjAAIfAAgKKR6EDQCgAgAfAAgKKR6EDQCgAgAAAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQAGAP8fAA==.Miskaabin:BAAANQAECgUIEAAAAA==.Missdemon:BAAANQADCggICAAAAA==.',
Mo='Mogral:BAAANQADCgQIBAAAAA==.Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUICwAAAA==.Monsart:BAAANQADCggIEwAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgMJBQAAAA==.Moralizdormi:BAABNQAECoEfAAIVAAgKXwzNCwB3AQAVAAgKXwzNCwB3AQAAAA==.Moregana:BAAANQADCgIIAgAAAA==.Mortiis:BAAANQADCggICAAAAA==.',
Mp='Mpd:BAAANQAECgQIBQAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgUICwAAAA==.',
['Mí']='Míerín:BAACNQAFFIEHAAIeAAQKzhbLCwBfAQAeAAQKzhbLCwBfAQA1AAQKgTAAAh4ACQqGJWUFAKwDAB4ACQqGJWUFAKwDAAAA.',
Na='Naama:BAAANQADCgYICwAAAA==.Naelih:BAAANQAECgYICwAAAA==.Nargo:BAAANQABCgMIAQAAAA==.Natlès:BAAANQAECgMIAwABNQAECgcICwACAAAAAA==.Natzu:BAAANQAECgMIBQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAABNQAECoElAAIZAAkKsRYjcgAcAgAZAAkKsRYjcgAcAgAAAA==.',
Ne='Necronu:BAAANQADCggICAABNQAECgkJMgAaAIcgAA==.',
Ni='Nikkolos:BAAANQADCgUIBQAAAA==.',
No='Nogusta:BAACNQAFFIEJAAIFAAQK3wqPFwAjAQAFAAQK3wqPFwAjAQA1AAQKgS4AAgUACQolGENHAJsCAAUACQolGENHAJsCAAAA.Notdecix:BAACNQAFFIEIAAMWAAMK5BIHCwAAAQAWAAMK5BIHCwAAAQAjAAEKQwCBMgAoAAA1AAQKgSIAAxYACQptHhINAAQDABYACQptHhINAAQDACMACApdFuxHACgCAAAA.',
Nu='Nuggets:BAAANQAECgUICQAAAA==.',
Ob='Obyss:BAAANQADCgQIBAAAAA==.',
Od='Odinsrain:BAAANQAECgQIBAABNQAECgkJKgAUAGQUAA==.',
On='Onlyshams:BAAANQAECgYICQAAAA==.Onulock:BAAANQAECgUIBgABNQAECgkJMgAaAIcgAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAAANQAECgUICwAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Palinia:BAAANQAECgEIAQABNQAECgYIEwACAAAAAA==.Pallyoop:BAABNQAECoEWAAMUAAgKKwv8agCwAQAUAAgKKwv8agCwAQAZAAYKigVt8wD9AAAAAA==.Pandarina:BAAANQADCgYIEAAAAA==.Papilock:BAAANQADCgUIBQABNQAECgcIFQADAC0XAA==.Pathalogical:BAAANQADCggIDwABNQAECgYICAACAAAAAA==.Patharok:BAAANQADCgMJAwABNQAECgYICAACAAAAAA==.Pathator:BAAANQAECgYICAAAAA==.Patheros:BAAANQABCgUJBQABNQAECgYICAACAAAAAA==.Patholan:BAAANQADCggICAABNQAECgYICAACAAAAAA==.Patholans:BAAANQADCgEIAQABNQAECgYICAACAAAAAA==.Paxmansigh:BAAANQAECgMIBgAAAA==.',
Ph='Phantöm:BAABNQAECoEiAAIXAAcKjRyFCAAxAgAXAAcKjRyFCAAxAgAAAA==.',
Pl='Placcid:BAABNQAECoEbAAIeAAgK3A6jaAAXAgAeAAgK3A6jaAAXAgAAAA==.Planknstein:BAAANQAECggIBwAAAA==.Plantoor:BAABNQAECoEjAAIkAAgKABU2BQBGAgAkAAgKABU2BQBGAgAAAA==.',
Po='Pockett:BAAANQAECgIIAgAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAABNQAECoEkAAMDAAgKHw/0aACiAQADAAgKHw/0aACiAQAEAAYK2gY8oAAmAQAAAA==.',
Pr='Prismclaw:BAABNQAECoEbAAIIAAgKlhAPDQCwAQAIAAgKlhAPDQCwAQAAAA==.Processing:BAACNQAFFIEKAAITAAQKfg80EAAsAQATAAQKfg80EAAsAQA1AAQKgS8AAhMACQo5IYQUAA0DABMACQo5IYQUAA0DAAAA.',
Pu='Puddle:BAAANQAECgQICAAAAA==.Puddleheal:BAAANQAECgEIAQABNQAECgQICAACAAAAAA==.Puffdamagic:BAABNQAECoEpAAMaAAgKQg5PIACxAQAaAAgKQg5PIACxAQAVAAgK6AkeDABuAQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQADCgUJCgAAAA==.',
Qp='Qplus:BAABNQAECoEYAAIeAAcKDArBlgCoAQAeAAcKDArBlgCoAQAAAA==.',
Qs='Qstorm:BAAANQADCgcIDQAAAA==.',
Qu='Quaenie:BAABNQAECoEXAAIjAAcKvQ7pdQCBAQAjAAcKvQ7pdQCBAQAAAA==.Quintin:BAAANQAECgQIBAAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgQICAAAAA==.Rayleigh:BAAANQAECgUIDAABNQADCgMIAwACAAAAAA==.',
Re='Redchord:BAAANQAECgQIBAAAAA==.Regidør:BAABNQAFFIEFAAIZAAMKjReUEAACAQAZAAMKjReUEAACAQAAAA==.Regixa:BAAANQAECgUIBQAAAA==.Relik:BAAANQAECgYIEwAAAA==.',
Rh='Rhaspus:BAAANQAECgUICwAAAA==.',
Ri='Rillenne:BAAANQADCgcIBwAAAA==.Rilliccine:BAAANQAECgIIAgAAAA==.Rilliguine:BAAANQADCgQIBAAAAA==.Rillinetti:BAABNQAECoEXAAIGAAcK+xATgwCxAQAGAAcK+xATgwCxAQAAAA==.Rillini:BAAANQAECgQICAAAAA==.Rilliti:BAAANQADCgcJEgAAAA==.Risky:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAAANQAECgYIDQAAAA==.Rookdh:BAACNQAFFIEKAAIBAAQKBRQ4CgBHAQABAAQKBRQ4CgBHAQA1AAQKgS4AAgEACQopICYRAP0CAAEACQopICYRAP0CAAAA.Rosey:BAAANQAECgYIEwAAAA==.Royale:BAAANQAECgYIEgAAAA==.',
Ru='Rudeus:BAAANQAECgQIBgAAAA==.Rudyeightbal:BAAANQADCgYIBgAAAA==.Rum:BAAANQADCggIIwAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECgMIBAAAAA==.Sagesse:BAAANQADCggJFAAAAA==.Saisera:BAAANQAECgQIBAAAAA==.Samifleur:BAAANQAECgUIBgAAAA==.Sammy:BAABNQAECoEYAAMZAAcKqwlpwABiAQAZAAcKqwlpwABiAQAUAAEKaQGQHQEbAAAAAA==.Santaclaaws:BAACNQAFFIEHAAIiAAQKIxuXBwBiAQAiAAQKIxuXBwBiAQA1AAQKgTQAAyIACQqGJAUHAFoDACIACAqPJQUHAFoDAAEAAgriGoBtAIoAAAAA.Santafuego:BAAANQAECgUICgABNQAFFAQIBwAiACMbAA==.Santapal:BAABNQAECoEpAAMUAAkK+RtgHQDnAgAUAAkK+RtgHQDnAgAZAAEKBAQTiwEpAAABNQAFFAQIBwAiACMbAA==.Saphotic:BAAANQAFFAEIAQABNQAFFAMICAAWAOQSAA==.Saydragon:BAAANQADCgQIBAAAAA==.Sayvil:BAAANQAECgYIFwABNQAECgcIEAACAAAAAQ==.',
Se='Selbor:BAAANQAECgUIBQAAAA==.Semmers:BAAANQAECgYIEAAAAA==.Sensational:BAAANQAECgcIDwAAAA==.Septiria:BAAANQAECgMIBAAAAA==.Sergio:BAAANQADCgcIDwAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgACAAAAAA==.Shalash:BAAANQADCgYIBgABNQAECgkJHQAgANsaAA==.Shamadeano:BAAANQAECgUIBQAAAA==.Shamanshikz:BAABNQAECoEYAAIEAAkKgBhALACpAgAEAAkKgBhALACpAgAAAA==.Shamiska:BAAANQAECggIDQAAAA==.Shampooh:BAAANQAECgEIAQAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAABNQAECoEkAAIDAAgKIhwULQCJAgADAAgKIhwULQCJAgAAAA==.Sharazzy:BAAANQAECgIIAgAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shian:BAAANQAECgYIDQAAAA==.Shieldee:BAABNQAECoEXAAIZAAgK8hb6dQASAgAZAAgK8hb6dQASAgAAAA==.Shigaraki:BAAANQAECgcICgAAAA==.Shikzzs:BAAANQAECgcIEwABNQAECgkJGAAEAIAYAA==.Shockeei:BAABNQAECoErAAIHAAkKOCMGGQBpAwAHAAkKOCMGGQBpAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQADCggIIAAAAA==.',
Si='Sickwitit:BAAANQAECggICAAAAA==.Sighh:BAAANQADCgEIAQAAAA==.Sighhy:BAAANQADCggIDQAAAA==.Sijth:BAABNQAECoFDAAMUAAgKVxxSJwCzAgAUAAgKVxxSJwCzAgAZAAQKZw+ZGgG7AAAAAA==.Silvereyes:BAAANQADCgIIAgAAAA==.Silverwar:BAABNQAECoEcAAIlAAcK8RpKDwAJAgAlAAcK8RpKDwAJAgAAAA==.Simmi:BAEANQAECgQIBAABNQAFFAMICQAUABMkAA==.Simmune:BAECNQAFFIEJAAIUAAMKEyRGDgBEAQAUAAMKEyRGDgBEAQA1AAQKgSsAAhQACQo5IgYJAHMDABQACQo5IgYJAHMDAAAA.Sinarala:BAAANQADCgYIBgAAAA==.Sirlavan:BAAANQADCgcIBwAAAA==.Six:BAAANQADCggICAAAAA==.Sixior:BAABNQAECoEcAAIFAAcKwR4/XgBUAgAFAAcKwR4/XgBUAgAAAA==.Sixogue:BAAANQADCggIDwAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skanknstein:BAAANQADCgQIBAAAAA==.Skepti:BAAANQAECgYIEwAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAAANQAECgYIEwAAAA==.',
Sm='Smeeta:BAABNQAECoEjAAIOAAkKgR2PFADyAgAOAAkKgR2PFADyAgAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Soram:BAAANQADCgYIBgAAAA==.Sosa:BAAANQAECgMIBQABNQAFFAYIFQAfAJEjAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBAAAAA==.Soùl:BAAANQAECgQIBgAAAA==.',
Sp='Sparkley:BAAANQAECgUICQABNQAECggIKQAaAEIOAA==.Spike:BAAANQAECgUICAAAAA==.Spinspinspin:BAAANQADCggICAAAAA==.',
St='Starlara:BAAANQABCgYICAAAAA==.Stazz:BAABNQAECoEiAAIeAAgKEgeajwC5AQAeAAgKEgeajwC5AQAAAA==.Steelerayne:BAAANQAECgUICAAAAA==.Stian:BAAANQAECgIIAgAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAABNQAECoEXAAIEAAgKrQwKaQC1AQAEAAgKrQwKaQC1AQAAAA==.Stormii:BAAANQAECgEIAQAAAA==.Stormtotem:BAAANQAECgEIAQAAAA==.Strangerdk:BAAANQAECgYIEwAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sv='Svenraiden:BAAANQABCgEIAQAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECoEpAAISAAgKLwqWIABPAQASAAgKLwqWIABPAQAAAA==.Swordfish:BAAANQAECgQIBgAAAA==.',
Sy='Sybrooke:BAAANQADCgYIDwAAAA==.Sydran:BAAANQADCgMIAwAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAABNQAECoEkAAIIAAgKFiKhAwDkAgAIAAgKFiKhAwDkAgAAAA==.Taegia:BAAANQADCgUIBQABNQAFFAQICQAKAA0ZAA==.Talanth:BAAANQAECgYIEAAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tandisong:BAAANQADCgEIAQAAAA==.Tarrisx:BAAANQADCgEJAQABNQAECgkJIwAOAIEdAA==.Tashi:BAAANQADCggICAAAAA==.Tayon:BAAANQAECgUIDAAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Tearza:BAAANQADCgIIAgAAAA==.Termana:BAACNQAFFIEJAAIlAAMKLSKJAgApAQAlAAMKLSKJAgApAQA1AAQKgS8AAiUACQrWJZgAANsDACUACQrWJZgAANsDAAAA.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Thegame:BAAANQADCgQIBAAAAA==.Theodoró:BAAANQAECgYICwAAAA==.Thereza:BAAANQAECgUIBwAAAA==.Thiccpickle:BAAANQAECgEIAQABNQAECgcICwACAAAAAA==.Thug:BAAANQADCgcIFQAAAA==.',
Ti='Tiferet:BAABNQAECoEdAAMjAAcKsB96PABUAgAjAAcKsB96PABUAgAWAAIK0AYmYgBPAAAAAA==.Tigiw:BAAANQAECgMIBQAAAA==.Tinysunshine:BAAANQAECgQICAAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAABNQAECoEYAAIeAAcKMBPUfgDgAQAeAAcKMBPUfgDgAQAAAA==.Tomato:BAACNQAFFIEFAAMRAAQKogjHDQCbAAARAAIKSgzHDQCbAAAGAAIK+QTpLgB+AAA1AAQKgSYAAxEACQpsHLgFAK4CABEACAqyHbgFAK4CAAYABAopF87FABEBAAAA.Torfelori:BAAANQAECgQICAAAAA==.Torvalar:BAABNQAECoEjAAIZAAgKJRJYhADtAQAZAAgKJRJYhADtAQAAAA==.Tove:BAAANQAECgYIDwAAAA==.',
Tr='Trûth:BAAANQAECggIDwAAAA==.',
Tu='Turdyl:BAABNQAECoEhAAIZAAkKlQ5ghQDqAQAZAAkKlQ5ghQDqAQAAAA==.',
Tw='Twindadlock:BAAANQABCgIIAgABNQAECgQIDQACAAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggIEQAAAA==.',
['Tá']='Tárris:BAABNQAECoEaAAIGAAcKaRwoTgBKAgAGAAcKaRwoTgBKAgABNQAECgkJIwAOAIEdAA==.',
['Tô']='Tôx:BAABNQAECoEbAAMEAAgKyB05NACCAgAEAAgKyB05NACCAgADAAMKOAkQ1wCRAAAAAA==.',
Um='Umbranwings:BAAANQAECgUIEQAAAA==.',
Un='Unheardjp:BAAANQAECgEIAQAAAA==.',
Ur='Ursus:BAAANQAECgYIEgAAAA==.',
Va='Vaerix:BAAANQAECgYIDQAAAA==.Valydrin:BAABNQAECoEdAAMjAAgKjhapUgAAAgAjAAgKjhapUgAAAgAWAAMKWga0VwB6AAAAAA==.',
Ve='Vexadrine:BAACNQAFFIEKAAIQAAQKVRUvBAAwAQAQAAQKVRUvBAAwAQA1AAQKgTAAAhAACQq4H3AEABgDABAACQq4H3AEABgDAAAA.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vu='Vuldrak:BAAANQAECggICAAAAA==.',
Vy='Vysis:BAACNQAFFIEHAAIWAAQKTxEsCQA6AQAWAAQKTxEsCQA6AQA1AAQKgTIABBYACQooHm8MAA0DABYACQooHm8MAA0DACMABwpOIOJOAA4CACYABQqyFg4LAH0BAAAA.',
['Ví']='Ví:BAAANQAECgEIAQAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAABNQAECoEbAAQQAAcKohi9DgDnAQAQAAcK1he9DgDnAQALAAUKPxGtOQAOAQAKAAQKWQg6NQCaAAAAAA==.Widgit:BAAANQADCgUIBwAAAA==.Wieldblade:BAABNQAECoEkAAMZAAgKbhWxdAAVAgAZAAgKbhWxdAAVAgAUAAIK2ArH8ABjAAAAAA==.',
Wo='Woolverine:BAAANQAECgUICwAAAA==.',
Wu='Wunderbar:BAAANQAECgYIDQAAAA==.',
Wy='Wyldfire:BAACNQAFFIEJAAITAAQKEhPoDwAxAQATAAQKEhPoDwAxAQA1AAQKgTIAAhMACQo3I4YHAIoDABMACQo3I4YHAIoDAAAA.',
Xa='Xanith:BAAANQAECgcICAAAAA==.Xanyth:BAAANQADCggICAAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Ya='Yardly:BAAANQADCggICgAAAA==.',
Yi='Yia:BAAANQAECgUIDAABNQAECgUIDQACAAAAAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECoEZAAMLAAgKciWOCAAzAwALAAgKciWOCAAzAwAKAAIK5AqYOwBoAAAAAA==.',
Za='Zalerodora:BAAANQADCgEIAQABNQAECgUICwACAAAAAA==.Zarich:BAABNQAECoEbAAInAAcK3h6RBABpAgAnAAcK3h6RBABpAgAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECgcIGAADAC0eAA==.Zogah:BAEANQAECgQIBAABNQAECgcIGAADAC0eAA==.Zoganian:BAEANQAECgMIBQABNQAECgcIGAADAC0eAA==.Zoghog:BAAANQAECgQIBAAAAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
Zy='Zyaire:BAAANQABCgQIBQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
['Ço']='Çosmos:BAAANQADCgUIBwAAAA==.',
['Év']='Évélýn:BAAANQADCgUIBQAAAA==.',
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
