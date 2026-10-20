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

local lookup = {'DemonHunter-Havoc','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Outlaw','Monk-Brewmaster','Warlock-Destruction','Druid-Guardian','Druid-Balance','Paladin-Holy','Evoker-Augmentation','Shaman-Enhancement','Priest-Holy','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Rogue-Assassination','Warlock-Affliction','Hunter-Survival','DemonHunter-Vengeance',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Actualape:BAAANQAECgQIBgAAAA==.',
Ad='Addy:BAABNQAECn8qAAIBAAkK4RW/JwBgAgABAAkK4RW/JwBgAgAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAABNQAECn8VAAICAAYKtwf/RADeAAACAAYKtwf/RADeAAAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQAECgQIBgAAAA==.Aispere:BAAANQAECgEIAgABNQAECgQICAADAAAAAA==.',
Al='Alerzhulan:BAAANQAECgUIEAAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAABNQAECn8eAAIEAAgKXw9EpgDUAQAEAAgKXw9EpgDUAQAAAA==.Alorely:BAABNQAECn8eAAMFAAcK2A/9MgCLAQAFAAcK2A/9MgCLAQAGAAMKWxBpBQCiAAAAAA==.',
Am='Amanara:BAABNQAECn8XAAMHAAYK4wffPQCtAAAIAAUKyggVkADoAAAHAAUKbwTfPQCtAAAAAA==.Amoonia:BAAANQADCgYIFQAAAA==.',
An='Anciientpaw:BAABNQAECn8eAAMJAAgKux8bLwClAgAJAAgKux8bLwClAgAKAAMKIg3B9QCpAAAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgcIDwAAAA==.Anguirus:BAABNQAECn8kAAIKAAkKfANLqgA/AQAKAAkKfANLqgA/AQAAAA==.Anitax:BAAANQAECggIEAABNQAECgoKHgAKAMoaAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Ao='Aoman:BAAANQAECgQIBQAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIFAAAAA==.Arcadian:BAABNQAECn85AAMLAAoK0RBDOQA0AQALAAoKqRBDOQA0AQAMAAIKBRGdJQCCAAAAAA==.Arceeprime:BAAANQAECgMIAgAAAA==.Arextheelder:BAAANQAECgUIDAAAAA==.Argentum:BAAANQADCggICAABNQAECgkJKgABAOEVAA==.Armorscales:BAABNQAECn8dAAINAAkKfSD4MwC5AgANAAkKfSD4MwC5AgAAAA==.Arntraz:BAAANQAECgIIAwAAAA==.Arrabbiato:BAABNQAECn8YAAIOAAcKLAo1sQCiAQAOAAcKLAo1sQCiAQAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQADCggIEAAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAABNQAECn8aAAIFAAoKoAr6DwASAQAFAAoKoAr6DwASAQAAAA==.Astayoni:BAAANQAECgUIBgAAAA==.Asterfleur:BAAANQAECgQICAABNQAECgYICAADAAAAAA==.Astrine:BAABNQAECn8gAAMPAAkKKxUHHAAQAQAQAAkKOxPsowA5AgAPAAYKng8HHAAQAQAAAA==.',
At='Ataraxya:BAAANQAECgYIDQAAAA==.',
Au='Auberon:BAABNQAECn8oAAIRAAoK3xfZCQCiAgARAAoK3xfZCQCiAgAAAA==.Aufta:BAABNQAECn8dAAMSAAcKoweaQwD8AAASAAYKoweaQwD8AAATAAYKNgXdMgDTAAAAAA==.Aumer:BAAANQADCggICAAAAA==.Aura:BAAANQADCgcIBwAAAA==.',
Az='Azi:BAACNQAFFH8NAAIUAAUKjRSfCwCEAQAUAAUKjRSfCwCEAQA1AAQKfy8AAhQACgrxHp0RANkCABQACgrxHp0RANkCAAAA.Azurite:BAAANQADCgYIFQAAAA==.',
Ba='Backpedal:BAAANQAECgUIBAAAAA==.Badankhadonk:BAACNQAFFH8PAAMJAAUKQB4sCQC9AQAJAAUKQB4sCQC9AQAKAAEK1g6JMABJAAA1AAQKfzkAAwkACQr7JIcFAJsDAAkACQr7JIcFAJsDAAoABAoXHVmqAD8BAAAA.Bakkutteh:BAAANQABCgIIBQAAAA==.Bakuhiko:BAAANQAECgUICAAAAA==.Balen:BAABNQAECn8UAAMEAAYKdQwk/QAlAQAEAAYKPgsk/QAlAQACAAIKqQxGZQBMAAAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.Bariden:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAACNQAFFH8JAAIIAAUKNBPKCACLAQAIAAUKNBPKCACLAQA1AAQKfyYAAggACQrZIAMZAPcCAAgACQrZIAMZAPcCAAAA.Beethozart:BAAANQADCggIEgAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAAANQAECgYIEgAAAA==.Beliice:BAAANQADCgIIAgABNQAECgYIEgADAAAAAA==.Bellafleur:BAAANQAECgQIDQABNQAECgYICAADAAAAAA==.Bellawesome:BAAANQAECgMIAwAAAA==.Bendeekay:BAACNQAFFH8QAAIVAAUKiyLECwCYAQAVAAUKiyLECwCYAQA1AAQKfzIAAxUACQopIyMJAHADABUACQopIyMJAHADAAgAAgq4EntSADgAAAAA.Benilok:BAAANQAECgYIEQAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bf='Bfh:BAAANQAECggICAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQAECgEIAQAAAA==.',
Bl='Blackblood:BAABNQAECn8iAAIBAAcKWQy/SACEAQABAAcKWQy/SACEAQAAAA==.Bladestriker:BAAANQAECgMIAwAAAA==.Bloodache:BAABNQAECn8cAAIWAAkKFiEXEADxAgAWAAkKFiEXEADxAgAAAA==.Blux:BAAANQAECgQIBgAAAA==.',
Bo='Boil:BAABNQAECn8mAAIXAAcKyQS+EAAPAQAXAAcKyQS+EAAPAQAAAA==.Bonemarrow:BAAANQAECgUICgAAAA==.Bordin:BAAANQADCgYIBwAAAA==.Bows:BAAANQAECggICAAAAA==.',
Br='Brakeable:BAAANQAECgYICQAAAA==.Braké:BAABNQAECn8YAAICAAcKFiHkFABbAgACAAcKFiHkFABbAgAAAA==.Brewskies:BAABNQAECn81AAIYAAoKJyI7AAAvAwAYAAoKJyI7AAAvAwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brioche:BAAANQADCgUIBgAAAA==.Brionthicc:BAAANQAECgMIBQABNQAFFAUIDwAZAMURAA==.Brownington:BAABNQAECn8iAAQaAAkKDCPjGADlAQAbAAYKwB84PgAHAgAaAAUKfSLjGADlAQARAAIK0yFFKwC3AAAAAA==.Bruhilda:BAAANQAECgYIDQAAAA==.Brìonik:BAACNQAFFH8PAAMZAAUKxRHeCQCnAAANAAMKHgq2JADbAAAZAAIKbRneCQCnAAA1AAQKfzYAAxkACgrkGzUHAJQCABkACApiGzUHAJQCAA0ACAr0F785AB4BAAAA.',
Bu='Bubbleroundi:BAABNQAECn87AAIcAAoKThAzCgAfAgAcAAoKThAzCgAfAgAAAA==.Bubudder:BAABNQAECn81AAMIAAoKMSBrDABXAwAIAAkKYiJrDABXAwAHAAYKQhSUEQB5AQAAAA==.Buffstuff:BAABNQAECn8nAAIdAAkKqQ1TAgBOAQAdAAkKqQ1TAgBOAQAAAA==.Burgerlock:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAABNQAECn8dAAIFAAoKdQaOCQBbAQAFAAoKdQaOCQBbAQAAAA==.Canadaishere:BAAANQADCgMIAwAAAA==.Canadaispimp:BAAANQADCgEIAQAAAA==.Cantheartitz:BAAANQAECgUICgAAAA==.Catdav:BAABNQAECn8bAAIeAAYK3R3JDAAtAQAeAAYK3R3JDAAtAQAAAA==.',
Ch='Charbol:BAAANQADCgQICAABNQADCggIEQADAAAAAA==.Chelraani:BAABNQAECn8fAAIEAAgKjRTXLgBzAQAEAAgKjRTXLgBzAQAAAA==.Chess:BAAANQAECggIDgAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBgAAAA==.',
Ci='Ciarianna:BAAANQADCgcIBwABNQAECgkJKgABAOEVAA==.Cigar:BAAANQADCgUICQABNQAECgYIEAADAAAAAA==.',
Cl='Clazzicola:BAACNQAFFH8JAAISAAQKThq/CQAyAQASAAQKThq/CQAyAQA1AAQKfyQAAhIACgqnHf0VAKECABIACgqnHf0VAKECAAAA.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgQICwAAAA==.Coogsayer:BAAANQADCgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.Cowgoboom:BAAANQADCgUICQAAAA==.',
Cp='Cptncrush:BAABNQAECn8hAAMJAAcKKxwAVwANAgAJAAcKKxwAVwANAgAKAAMKexM+SAC1AAAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.Creature:BAAANQAECgQIBgAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAABNQAECn8jAAIFAAkKaBQ2IAA4AgAFAAkKaBQ2IAA4AgAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAACNQAFFH8PAAIMAAUKTBqVAADPAQAMAAUKTBqVAADPAQA1AAQKfzYAAgwACgr7JMwAALwDAAwACgr7JMwAALwDAAAA.',
Da='Dadbodftw:BAAANQAECgQIEQAAAA==.Daddylight:BAABNQAECn8fAAIEAAkK8gu8UAAjAQAEAAkK8gu8UAAjAQAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Darkdottie:BAAANQAECgYIDgAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgQIAwAAAA==.Dayday:BAAANQAECggICAAAAA==.',
De='Deadlight:BAABNQAECn8uAAIHAAkKVxBaOAD0AQAHAAkKVxBaOAD0AQAAAA==.Deadtofall:BAAANQADCgcIFQAAAA==.Deathshikzs:BAABNQAECn8jAAMVAAkK8RvLKgBwAgAVAAkK8RvLKgBwAgAIAAEKqweDVwAsAAABNQAECgoKHgAKAMoaAA==.Decix:BAAANQAECgQIBAABNQAFFAQIDAAFAH8VAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAABNQAECn8cAAMMAAoKUB4yAwAsAwAMAAoKUB4yAwAsAwALAAIK8BIzLQF6AAAAAA==.Demonllxll:BAAANQAECgUIDgAAAA==.Demontime:BAAANQADCgcIDAABNQAECgQIBAADAAAAAA==.Desolation:BAABNQAECn80AAIQAAoKdSKyAwC3AgAQAAoKdSKyAwC3AgAAAA==.Despia:BAABNQAECn8fAAMfAAgKiCKjBQClAgAfAAgKiCKjBQClAgAFAAQK8wwzUQDMAAAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAABNQAECn8fAAMgAAgKIg15NwBhAQAgAAgKIg15NwBhAQAbAAYKWwOfhAC/AAAAAA==.Diety:BAABNQAECn8nAAISAAkKihpYEwC/AgASAAkKihpYEwC/AgABNQAECgoKHAAMAFAeAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgYIDAAAAA==.',
Dj='Djpallyd:BAABNQAECn8jAAIEAAoK2BXhggAiAgAEAAoK2BXhggAiAgAAAA==.',
Do='Dornoll:BAAANQADCgQIBAAAAA==.Dotmami:BAAANQAECgcICwAAAA==.Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECn9AAAMhAAoKdCE+AQClAgAhAAoKdCE+AQClAgAiAAEKAACGPAA1AAABNQAFFAUICgANAKsQAA==.Draktyr:BAACNQAFFH8JAAILAAQK5BBKGwA5AQALAAQK5BBKGwA5AQA1AAQKfzMAAwsACgp9IvgXAFkDAAsACgp9IvgXAFkDAAwAAQoAABQ2AC4AAAAA.Drlovely:BAAANQADCgQIBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Elianda:BAAANQADCggIDgAAAA==.Ellalais:BAAANQAECgQICgAAAA==.Ellismom:BAABNQAECn80AAIIAAoKgBktBAADAgAIAAoKgBktBAADAgAAAA==.',
En='Enamorada:BAAANQAECgQIBQABNQAECggIHgAJAOcZAA==.Enchanceurpp:BAAANQADCggIGQAAAA==.End:BAAANQAECgUIBwAAAA==.',
Eo='Eolyndin:BAAANQADCgQIBAAAAA==.Eolyndyn:BAAANQADCgYICQAAAA==.',
Er='Ereithelda:BAACNQAFFH8OAAITAAUK7hZZBACWAQATAAUK7hZZBACWAQA1AAQKfzkAAhMACgrZI5wDAHYDABMACgrZI5wDAHYDAAAA.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAFFAUICgANAKsQAA==.Errutu:BAABNQAECn81AAIjAAoKHQ/WCgCLAQAjAAoKHQ/WCgCLAQAAAA==.',
Ev='Evox:BAABNQAECn8UAAMKAAYKXBKjlQBuAQAKAAUKDBajlQBuAQAeAAUKvQQbGACWAAAAAA==.',
Fa='Falgar:BAAANQAECgQIBAAAAA==.Fann:BAABNQAECn8iAAIgAAcKFgd5QgAWAQAgAAcKFgd5QgAWAQAAAA==.Fargrim:BAAANQADCggIEQAAAA==.Fauna:BAAANQADCggICAAAAA==.',
Fe='Feathiir:BAAANQADCgIIAgAAAA==.Feefifofum:BAAANQADCgUIBQAAAA==.Fewz:BAACNQAFFH8TAAMPAAUKlCN3AAD8AQAPAAUKlCN3AAD8AQAQAAEKAABDZAA/AAA1AAQKfzkAAw8ACgrtJWsAANMDAA8ACgrtJWsAANMDABAAAQoQDwLDATkAAAAA.',
Fl='Flakflap:BAAANQAECgUIBQABNQAFFAIIBQAVADsPAA==.Flakov:BAAANQADCggIDgABNQAFFAIIBQAVADsPAA==.Flaktop:BAACNQAFFH8FAAIVAAIKOw/LIwBvAAAVAAIKOw/LIwBvAAA1AAQKfy8AAhUACQqGHikgALICABUACQqGHikgALICAAAA.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgQIBQAAAA==.Fluffie:BAAANQABCggICwAAAA==.',
Fo='Forbacon:BAABNQAECn8nAAMVAAgKcBlvGgAbAQAVAAgKcBlvGgAbAQAHAAMKrAlWhwCUAAAAAA==.Force:BAABNQAECn8cAAMHAAcKnwS0ZgAGAQAHAAcKnwS0ZgAGAQAIAAEKRwMr9QAiAAAAAA==.Fouris:BAAANQAECgQIBgAAAA==.',
Fr='Fridgie:BAACNQAFFH8PAAIOAAUKghLDCgChAQAOAAUKghLDCgChAQA1AAQKfzQAAg4ACgr2Ii4aADADAA4ACgr2Ii4aADADAAAA.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIEAAAAA==.Frozenturtle:BAABNQAECn8WAAIVAAcKwhw9QQD5AQAVAAcKwhw9QQD5AQAAAA==.',
Ft='Ftwiamtank:BAABNQAECn8cAAIkAAoK+Qs8CgANAQAkAAoK+Qs8CgANAQAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAACNQAFFH8KAAIQAAUKegnUIACBAQAQAAUKegnUIACBAQA1AAQKfzAAAhAACgriHJM1AFQBABAACgriHJM1AFQBAAAA.',
Ge='Geddan:BAAANQAECgEIAQAAAA==.Genericck:BAAANQAFFAIIBAAAAA==.Genericdh:BAAANQAFFAEIAQAAAA==.Generickdk:BAAANQAECgQIBAAAAA==.Genericpal:BAABNQAECn8qAAMCAAkKFSEgCgD5AgACAAgKQSQgCgD5AgAEAAMKUQ/yRgGvAAAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.',
Gn='Gnawbear:BAEBNQAECn8qAAIlAAoKyBbJCwBtAQAlAAoKyBbJCwBtAQAAAA==.',
Go='Goatassassin:BAABNQAECn8lAAMjAAkKFRH/FQAyAgAjAAkKFRH/FQAyAgAlAAIKawr+kABuAAAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECgkJJQAjABURAA==.Gobogoolina:BAAANQADCgYIDgAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQAECgUICQAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Haikuu:BAAANQADCgcIBwAAAA==.Hail:BAAANQAECgQIBAAAAA==.Hamnqueso:BAAANQADCgYIDgABNQAECgQIEQADAAAAAA==.Hardeesdelux:BAAANQAECgQICwAAAA==.Hazis:BAACNQAFFH8GAAIVAAQK5hGVFQAGAQAVAAQK5hGVFQAGAQA1AAQKfzQAAhUACgo4HO8VAP0CABUACgo4HO8VAP0CAAAA.',
Hi='Hinala:BAABNQAECn8qAAIVAAkKSAvGVQCdAQAVAAkKSAvGVQCdAQAAAA==.',
Ho='Holy:BAAANQAECgUIBQABNQAFFAUICgAKAEwLAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybutter:BAACNQAFFH8FAAILAAMK4SMzJADdAAALAAMK4SMzJADdAAA1AAQKf0AAAwsACgpeJA0BAEkDAAsACgpeJA0BAEkDAAwAAQoAAJcxADoAAAAA.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgcIEAAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAABNQAECn81AAIOAAoKLSEeEADvAQAOAAoKLSEeEADvAQAAAA==.',
In='Inanitas:BAAANQADCggICAAAAA==.Innominot:BAAANQAECgUIBwAAAA==.',
Ir='Irukox:BAAANQAECgMIBgAAAA==.',
Ja='Jackoldean:BAAANQADCgUICwAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jalene:BAABNQAECn8WAAIEAAYKcBIuZAD9AAAEAAYKcBIuZAD9AAAAAA==.Jargen:BAAANQADCgYIBwABNQADCggIEQADAAAAAA==.',
Je='Jettabae:BAAANQAECgIIBAABNQAFFAUIDwAEAFgLAA==.Jettadari:BAAANQAECgYICgABNQAFFAUIDwAEAFgLAA==.Jettadin:BAACNQAFFH8PAAIEAAUKWAsFDgBrAQAEAAUKWAsFDgBrAQA1AAQKfywAAgQACgp2IEwQAPkBAAQACgp2IEwQAPkBAAAA.',
Jt='Jt:BAAANQAECgcIDQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAACNQAFFH8PAAIJAAUKDBdMCgCpAQAJAAUKDBdMCgCpAQA1AAQKfy8AAwkACgrYH5wYABADAAkACgrYH5wYABADAB4ABQrCDo0XAJsAAAAA.',
Ka='Kakozaps:BAACNQAFFH8KAAMeAAUKnxhfAgCyAQAeAAUKnxhfAgCyAQAKAAEKmAzFMQBGAAA1AAQKf0sAAx4ACgqMJC0CAI0DAB4ACgqJJC0CAI0DAAoACAo7IJg4AJQCAAAA.Kalid:BAAANQAECgIIAgAAAA==.Kallar:BAAANQAECgcIEgABNQAECgcIHgADAAAAAA==.Kargle:BAAANQABCgEIAgAAAA==.Kathrynne:BAAANQAECgQICQAAAA==.Kayeera:BAAANQAECgYIDQAAAA==.Kaylrandi:BAAANQADCgYIGAAAAA==.Kayna:BAAANQAECgUIBQAAAA==.',
Ke='Kearza:BAAANQAECgYIDAAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgcIHQAEANoZAA==.Kennethv:BAABNQAECn8XAAIfAAYKSRjDGgChAQAfAAYKSRjDGgChAQAAAA==.Keny:BAAANQAECgUJBgABNQAECgYIDwADAAAAAA==.Kero:BAAANQADCgcICgABNQAECgcIHgADAAAAAA==.Kethie:BAAANQADCggIDwAAAA==.Kethra:BAAANQADCgQIBwAAAA==.Kev:BAAANQAECggIBAAAAA==.',
Kh='Khalesie:BAAANQADCgIIBAAAAA==.Khibanee:BAAANQAECgQIDQAAAA==.Khiell:BAABNQAECn8lAAMMAAkK5hlZCQBDAgAMAAgKVhtZCQBDAgALAAIKxw/UNgFmAAAAAA==.Khrominius:BAABNQAECn8aAAIQAAcKAhOJ4wDCAQAQAAcKAhOJ4wDCAQAAAA==.',
Ki='Killthirsty:BAAANQADCgcIBwABNQAECgUIBAADAAAAAA==.Kinigit:BAAANQAECggIDQABNQAFFAUIEwAbAAwbAA==.Kirïtö:BAAANQAECgUIBQAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAACNQAFFH8KAAIQAAQK7QxyEQDSAAAQAAQK7QxyEQDSAAA1AAQKfyoAAhAACgoIF3xzAJcCABAACgoIF3xzAJcCAAAA.',
Ko='Komamura:BAAANQAECgMIAwAAAA==.Konpalitaa:BAAANQAECgMIBAAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.Krátos:BAABNQAECn8mAAILAAoKpRhcCwALAgALAAoKpRhcCwALAgAAAA==.',
Ku='Kungphu:BAAANQADCgcICwAAAA==.Kuranaa:BAAANQAECgQICAAAAA==.Kurulak:BAABNQAECn8sAAIWAAoKfAsfBwCdAQAWAAoKfAsfBwCdAQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.Kynn:BAAANQADCggICwAAAA==.',
La='Lacerveza:BAAANQAECgQIBQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.Laylah:BAAANQAECgEIAQAAAA==.',
Le='Leriope:BAABNQAECn81AAINAAoKsQ72EgCuAQANAAoKsQ72EgCuAQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lickyez:BAAANQABCgEIAQAAAA==.Lihpfu:BAAANQAECgUIDQABNQAECgoKJwALAE0eAA==.Lilem:BAAANQADCgcICwAAAA==.Limboh:BAAANQADCgcIBwAAAA==.',
Lj='Lj:BAABNQAECn8sAAIcAAoKHR25BACZAgAcAAoKHR25BACZAgAAAA==.',
Lo='Lovecrafft:BAAANQADCgQIBAAAAA==.',
Lu='Luminary:BAAANQABCgEIAgAAAA==.Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcIJgAAAA==.Mager:BAAANQAECgIIAwAAAA==.Mageshyte:BAACNQAFFH8IAAIQAAUK8QzlIgBwAQAQAAUK8QzlIgBwAQA1AAQKfzUAAhAACgoLHplEAPoCABAACgoLHplEAPoCAAAA.Magolock:BAAANQAECgYIEAAAAA==.Magus:BAAANQADCggICAAAAA==.Maidrim:BAACNQAFFH8JAAIlAAUKthUvBwCmAQAlAAUKthUvBwCmAQA1AAQKfy8AAiUACQo5IdMSAOYCACUACQo5IdMSAOYCAAAA.Mamajumbo:BAABNQAECn8dAAIOAAgKbxbwLABqAQAOAAgKbxbwLABqAQAAAA==.Mana:BAACNQAFFH8KAAIKAAUKTAuhEQBSAQAKAAUKTAuhEQBSAQA1AAQKfzYAAgoACgoNGzcrANMCAAoACgoNGzcrANMCAAAA.Marellias:BAABNQAECn8aAAMOAAkKSh+5LwDeAgAOAAkKSh+5LwDeAgAUAAEK7wb5kQAuAAABNQAECgoKJgAEAL0lAA==.Marikel:BAAANQAECgUICQAAAA==.Marlea:BAABNQAECn8qAAMLAAkKChSVFwCpAQALAAkKChSVFwCpAQAMAAEKAAAaKwBaAAAAAA==.Maruka:BAABNQAECn8/AAINAAoK2B98AwCjAgANAAoK2B98AwCjAgAAAA==.Matthiias:BAAANQAECgIIAgAAAA==.Mawenzi:BAAANQADCggICAABNQAECggIKgAfAIURAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Meronpan:BAAANQAECgYIBgAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAABNQAECn8dAAIcAAcKIha4OQAAAQAcAAcKIha4OQAAAQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIJAgAAAA==.Migrains:BAABNQAECn80AAICAAoKkBwWAgA/AgACAAoKkBwWAgA/AgAAAA==.Mileyvyrus:BAAANQAFFAEIAQABNQAFFAQIDQAkAAghAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQANAH0gAA==.Miskaabin:BAABNQAECn8fAAMCAAcKoBNwEwDwAAACAAcKoBNwEwDwAAAEAAUKLAeOJwHeAAAAAA==.Missdemon:BAAANQADCggICAAAAA==.Missusgrey:BAAANQADCggICAABNQAECgkJKQAfAIsgAA==.',
Mo='Mogral:BAAANQADCgUICwAAAA==.Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUICwAAAA==.Monsart:BAAANQADCggIGQAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgMJBQAAAA==.Moralizdormi:BAABNQAECn8qAAIdAAkKvwgpDQB9AQAdAAkKvwgpDQB9AQAAAA==.Moregana:BAAANQAECgEIAQAAAA==.Mortiis:BAAANQAECgcICwAAAA==.',
Mp='Mpd:BAAANQAECgYICAAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAAANQAECgYIDAAAAA==.Mytmo:BAAANQADCgMIAwAAAA==.',
['Mí']='Míerín:BAACNQAFFH8NAAIOAAQKrxukBwDtAAAOAAQKrxukBwDtAAA1AAQKfzcAAg4ACgrOJJsFALUDAA4ACgrOJJsFALUDAAAA.',
Na='Naama:BAAANQADCgcIGQAAAA==.Naelih:BAABNQAECn8WAAIUAAgKfwgrPABwAQAUAAgKfwgrPABwAQAAAA==.Natlès:BAAANQAECgYICAABNQAECgcICwADAAAAAA==.Natzu:BAAANQAECgMIBQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAACNQAFFH8HAAIEAAUKMQODFwDtAAAEAAUKMQODFwDtAAA1AAQKfywAAgQACgo6F6eMAAwCAAQACgo6F6eMAAwCAAAA.',
Ne='Necronu:BAAANQADCggICAABNQAFFAUICgANAKsQAA==.',
Ni='Nikkolos:BAAANQAECgEIAQAAAA==.',
No='Nogusta:BAACNQAFFH8MAAILAAUKVQrVFgBuAQALAAUKVQrVFgBuAQA1AAQKfzUAAgsACgoxGghRAJcCAAsACgoxGghRAJcCAAAA.Notdecix:BAACNQAFFH8MAAMFAAQKfxVXDQADAQAFAAMKfxVXDQADAQAfAAIKcAEAMABiAAA1AAQKfycAAwUACgrxHUQOAAoDAAUACgrxHUQOAAoDAB8ACApdFltYABkCAAAA.',
Nu='Nuggets:BAAANQAECgYICgAAAA==.',
Ob='Obyss:BAAANQADCgUIBQAAAA==.',
Od='Odell:BAAANQADCgIIAgABNQADCggIEQADAAAAAA==.Odinsrain:BAAANQAECgUIBgABNQAFFAIIBQAcAAkYAA==.',
On='Onlyshams:BAAANQAECggICgAAAA==.Onubolt:BAAANQADCgMIAwABNQAFFAUICgANAKsQAA==.Onulock:BAACNQAFFH8KAAINAAUKqxDpBwDuAAANAAUKqxDpBwDuAAA1AAQKfxYABA0ACgoyFrRNAGsCAA0ACgoyFrRNAGsCACYAAQoAAFIoAEoAABkAAQr5COx7ADEAAAAA.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAABNQAECn8WAAIEAAYKJRd4PABOAQAEAAYKJRd4PABOAQAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Palinia:BAAANQAECgcICAABNQAECgcIGAAIAHUFAA==.Pallyoop:BAABNQAECn8cAAMcAAkK+AznfQCgAQAcAAkK+AznfQCgAQAEAAYKkgVrGQH1AAAAAA==.Pandarina:BAAANQAECgMIAwAAAA==.Papilock:BAAANQADCgUIBQABNQAECggIHgAJAOcZAA==.Pathalogical:BAAANQADCggIDwABNQAECggIEAADAAAAAA==.Patharok:BAAANQADCgMIAwABNQAECggIEAADAAAAAA==.Pathator:BAAANQAECggIEAAAAA==.Patheros:BAAANQAECggIDAABNQAECggIEAADAAAAAA==.Patholan:BAAANQADCggICAABNQAECggIEAADAAAAAA==.Patholans:BAAANQADCgEIAQABNQAECggIEAADAAAAAA==.Pathsqueek:BAAANQADCgcIBwABNQAECggIEAADAAAAAA==.Paxmansigh:BAAANQAECgQICgAAAA==.',
Pe='Perineumm:BAAANQABCgUIBQAAAA==.',
Ph='Phantöm:BAABNQAECn8vAAIMAAgK2RxoAgC8AQAMAAgK2RxoAgC8AQAAAA==.',
Pi='Pickle:BAAANQADCgYIBgABNQAECgYIHQAcAH0jAA==.Piratesmoke:BAAANQADCgYIAwAAAA==.',
Pl='Placcid:BAABNQAECn8sAAIOAAoKCxBUDQAHAgAOAAoKCxBUDQAHAgAAAA==.Planknstein:BAAANQAECggIDQAAAA==.Plantoor:BAABNQAECn8yAAInAAkKIhTyAAADAgAnAAkKIhTyAAADAgAAAA==.',
Po='Pockett:BAAANQAECgIIAgAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAABNQAECn81AAMJAAoK1w/jCwAJAgAJAAoK1w/jCwAJAgAKAAgKowo/eQC3AQAAAA==.',
Pr='Primøs:BAAANQAECgUICgAAAA==.Prismclaw:BAABNQAECn8kAAIPAAoKsA0MAwCcAQAPAAoKsA0MAwCcAQAAAA==.Processing:BAACNQAFFH8PAAIbAAUK+Q+dCwC3AQAbAAUK+Q+dCwC3AQA1AAQKfzMAAhsACgrxIHcWABMDABsACgrxIHcWABMDAAAA.',
Pu='Puddle:BAAANQAECggIDQAAAA==.Puddleheal:BAAANQAECgEIAQABNQAECgQICwADAAAAAA==.Puffdamagic:BAABNQAECn86AAMhAAoKfwx4BACjAQAhAAoKfwx4BACjAQAdAAgKswf7DQBqAQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQAECgUIBQAAAA==.',
Qi='Qirstbytt:BAAANQADCgUIBQAAAA==.',
Qp='Qplus:BAABNQAECn8iAAIOAAcK1QssYwDkAAAOAAcK1QssYwDkAAAAAA==.',
Qs='Qstorm:BAAANQADCgcIDQAAAA==.',
Qu='Quaenie:BAABNQAECn8hAAIfAAcKKA9uUwDRAAAfAAcKKA9uUwDRAAAAAA==.Quintin:BAAANQAECgYIBgAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgQICAAAAA==.Rayleigh:BAABNQAECn8XAAMPAAYKrxmaBABjAQAPAAYKrxmaBABjAQAQAAEKMwoqwwE5AAABNQAECgUIBQADAAAAAA==.',
Re='Reckligence:BAAANQADCgIIAgAAAA==.Redchord:BAAANQAECgYIDgAAAA==.Regidør:BAABNQAFFH8JAAMEAAQKpxfxFgDzAAAEAAMKpxfxFgDzAAAcAAEKRBUmJwBSAAAAAA==.Regixa:BAAANQAECggIEAAAAA==.Relik:BAABNQAECn8cAAMkAAcKuBBKJAAlAQAkAAYKVw9KJAAlAQALAAUKkgwB9gDyAAAAAA==.',
Rh='Rhaelia:BAAANQADCgUIBQAAAA==.Rhaspus:BAABNQAECn8XAAIBAAcKQREmHQAOAQABAAcKQREmHQAOAQAAAA==.',
Ri='Rillenne:BAAANQAECgQIBAAAAA==.Rilliccine:BAAANQAECgUICAAAAA==.Rillinetti:BAABNQAECn8lAAINAAgKAhEgIABvAQANAAgKAhEgIABvAQAAAA==.Rillini:BAAANQAECgUICgAAAA==.Rilliti:BAAANQAECgMIBAAAAA==.Risky:BAAANQADCgIIAgABNQAECgEIAgADAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAABNQAECn8fAAIOAAgKdiCPCgAjAgAOAAgKdiCPCgAjAgAAAA==.Rookdh:BAACNQAFFH8PAAIBAAUKPxKiCQCPAQABAAUKPxKiCQCPAQA1AAQKfzUAAgEACgqmH4wUAPgCAAEACgqmH4wUAPgCAAAA.Rosey:BAABNQAECn8jAAIEAAgKqw9KOwBRAQAEAAgKqw9KOwBRAQAAAA==.Royale:BAABNQAECn8YAAIOAAkKmhKTiwDzAQAOAAkKmhKTiwDzAQAAAA==.',
Rs='Rsteve:BAAANQABCgIIAgAAAA==.',
Ru='Rudeus:BAAANQAECgQIBgAAAA==.Rudyeightbal:BAAANQADCgYIBgAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECggIDgAAAA==.Sagesse:BAAANQADCggJFAAAAA==.Saisera:BAAANQAECgQIBAAAAA==.Samifleur:BAAANQAECgYICAAAAA==.Sammy:BAABNQAECn8iAAMEAAcK4wvgfADRAAAEAAcK4wvgfADRAAAcAAEKaQH1OQEbAAAAAA==.Santaclaaws:BAACNQAFFH8NAAIWAAUKdh/HBQDPAQAWAAUKdh/HBQDPAQA1AAQKfzsAAxYACgoCI84CAK4DABYACgoCI84CAK4DAAEAAgo/HLJ6AI0AAAAA.Santafuego:BAAANQAECgUICgABNQAFFAUIDQAWAHYfAA==.Santapal:BAABNQAECn8vAAMcAAoKzBwiIgDkAgAcAAoKzBwiIgDkAgAEAAEKBAR7vgEpAAABNQAFFAUIDQAWAHYfAA==.Saphotic:BAAANQAFFAEIAQABNQAFFAQIDAAFAH8VAA==.Saydragon:BAAANQADCgQIBAAAAA==.Sayvil:BAAANQAECgcIHgAAAQ==.',
Se='Selbor:BAAANQAECgUIDgAAAA==.Semmers:BAABNQAECn8VAAITAAgK8Qv8IQB1AQATAAgK8Qv8IQB1AQAAAA==.Sensational:BAAANQAECggIEgAAAA==.Septiria:BAAANQAECgUIDAAAAA==.Sergio:BAAANQADCgcIDwAAAA==.Seyren:BAAANQADCgQIBAAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgADAAAAAA==.Shadwizmoney:BAAANQADCgEIAQAAAA==.Shalash:BAAANQADCgYIBgABNQAFFAQICgAlAOcWAA==.Shamadeano:BAAANQAECgYIEAAAAA==.Shamanshikz:BAABNQAECn8eAAIKAAoKyhquNACmAgAKAAoKyhquNACmAgAAAA==.Shamiska:BAABNQAECn8UAAIeAAgKTARPJQAHAQAeAAgKTARPJQAHAQAAAA==.Shammerdown:BAAANQADCgQIBAAAAA==.Shampooh:BAAANQAECgEIAgAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAABNQAECn8wAAIJAAoKwBkqKQC/AgAJAAoKwBkqKQC/AgAAAA==.Sharazzy:BAAANQAECgIIAgAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shazami:BAAANQADCggICAAAAA==.Shian:BAABNQAECn8fAAIaAAgKchFvDgAhAQAaAAgKchFvDgAhAQAAAA==.Shieldee:BAABNQAECn8nAAIEAAkKsBmRHACwAQAEAAkKsBmRHACwAQAAAA==.Shigaraki:BAAANQAECgcIDQAAAA==.Shikzzs:BAABNQAECn8gAAIoAAkKoiEqBAAMAwAoAAkKoiEqBAAMAwABNQAECgoKHgAKAMoaAA==.Shockeei:BAABNQAECn8rAAIQAAkKHSRQIgBTAwAQAAkKHSRQIgBTAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQAECgQICAAAAA==.',
Si='Siakora:BAAANQAECgMIAwABNQAFFAUIDwAbAPkPAA==.Sighh:BAAANQADCgQIBQAAAA==.Sighhy:BAAANQADCggIDQAAAA==.Sijth:BAABNQAECn9TAAMcAAgK7R5vJwDLAgAcAAgK7R5vJwDLAgAEAAQKbRGZQgG2AAAAAA==.Silvereyes:BAAANQADCgIIAgAAAA==.Silverwar:BAABNQAECn8lAAIkAAkKWRhfDABvAgAkAAkKWRhfDABvAgAAAA==.Simmi:BAEANQAECgUICQABNQAFFAUIDgAcAIkbAA==.Simmune:BAECNQAFFH8OAAIcAAUKiRu0BwDrAQAcAAUKiRu0BwDrAQA1AAQKfy0AAhwACgp1Iu4LAGgDABwACgp1Iu4LAGgDAAAA.Sinarala:BAAANQADCggIEQAAAA==.Sinrei:BAAANQABCgEIAQAAAA==.Sirlavan:BAAANQADCgcIBwAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skanknstein:BAAANQAECgMIBAAAAA==.Skarn:BAAANQABCgEIAQAAAA==.Skepti:BAABNQAECn8hAAIOAAkKPxy3PAC0AgAOAAkKPxy3PAC0AgAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAABNQAECn8kAAIeAAgKigYaHgCAAQAeAAgKigYaHgCAAQAAAA==.',
Sm='Smeeta:BAABNQAECn8yAAIVAAoKUx91BQDyAQAVAAoKUx91BQDyAQAAAA==.Smokesmash:BAAANQADCgcIDgAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Solaace:BAAANQADCgcIDgABNQAECgQIDwADAAAAAA==.Soram:BAAANQADCgYIBgAAAA==.Sosa:BAAANQAECgMIBwABNQAFFAcIHAACAEQlAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBQAAAA==.Soùl:BAAANQAECgYIEAAAAA==.',
Sp='Sparkley:BAAANQAECgUICQABNQAECgoKOgAhAH8MAA==.Spike:BAAANQAECggIDgAAAA==.Spinspinspin:BAAANQAECgYICQAAAA==.',
St='Starlara:BAAANQADCgYIBgAAAA==.Stazz:BAABNQAECn8pAAIOAAgKown3oADEAQAOAAgKown3oADEAQAAAA==.Steelerayne:BAABNQAECn8UAAIOAAYKOBOsLQBoAQAOAAYKOBOsLQBoAQAAAA==.Stian:BAAANQAECgIIAgAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAABNQAECn8bAAIKAAgK+xHFbADaAQAKAAgK+xHFbADaAQAAAA==.Stormii:BAAANQAECgEIAQAAAA==.Stormtotem:BAAANQAECgEIAQAAAA==.Strangerdk:BAABNQAECn8YAAIIAAcKdQWJhgAHAQAIAAcKdQWJhgAHAQAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECn87AAIaAAoKAwtrCgBUAQAaAAoKAwtrCgBUAQAAAA==.Swordfish:BAAANQAECgQIBgAAAA==.',
Sy='Sybrooke:BAAANQAECgEIAQAAAA==.Sydran:BAAANQAECgUIBQAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAABNQAECn81AAIPAAoKOx+4AABoAgAPAAoKOx+4AABoAgAAAA==.Taegia:BAAANQADCgUIBQABNQAFFAUIDgATAO4WAA==.Talanth:BAABNQAECn8cAAIlAAcKSAx+HQDiAAAlAAcKSAx+HQDiAAAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tandisong:BAAANQAECgIIAQAAAA==.Tanitie:BAAANQADCgEIAQAAAA==.Tanknstein:BAAANQAECgUIBQAAAA==.Taro:BAAANQADCggICAABNQAECgoKHQAKAJUIAA==.Tarrisx:BAAANQADCgEJAQABNQAECgoKMgAVAFMfAA==.Tashi:BAAANQADCggIEgAAAA==.Tayon:BAAANQAECgYIDQAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Tearza:BAAANQADCgIIAwAAAA==.Termana:BAACNQAFFH8NAAIkAAQKCCFWAgB+AQAkAAQKCCFWAgB+AQA1AAQKfzMAAiQACgpxJcEAANkDACQACgpxJcEAANkDAAAA.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Thegame:BAAANQADCgQIBAAAAA==.Themage:BAAANQAECgMIAwAAAA==.Theodoró:BAABNQAECn8YAAMOAAgKdRrYUgB4AgAOAAcKJx7YUgB4AgAUAAIKRQMhfgBMAAAAAA==.Thereza:BAAANQAECgUICQAAAA==.Thiccpickle:BAAANQAECgIIAgABNQAECgcICwADAAAAAA==.Thrashzel:BAAANQADCgUIBQAAAA==.Thug:BAAANQADCgcIFQAAAA==.Thuneredor:BAAANQADCgMIAwAAAA==.',
Ti='Tiferet:BAABNQAECn8nAAMfAAkKOCAUKwC9AgAfAAkKOCAUKwC9AgAFAAIK7wXubgBLAAAAAA==.Tigiw:BAABNQAECn8VAAIOAAYKzw5BwgB+AQAOAAYKzw5BwgB+AQAAAA==.Tinysunshine:BAAANQAECgYIEAAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAABNQAECn8iAAIOAAcKWhkuQwAvAQAOAAcKWhkuQwAvAQAAAA==.Tomato:BAACNQAFFH8JAAMZAAQKUgtgEACSAAAZAAIKSgxgEACSAAANAAIKYwm7NACKAAA1AAQKfykAAxkACQrMG3YGAKUCABkACAo5HXYGAKUCAA0ABAqrF+ndAA0BAAAA.Torfelori:BAAANQAECgQICAAAAA==.Torvalar:BAABNQAECn80AAIEAAoKkg+VMQBrAQAEAAoKkg+VMQBrAQAAAA==.Tove:BAABNQAECn8dAAIKAAoKlQhEggCfAQAKAAoKlQhEggCfAQAAAA==.',
Tr='Trûth:BAAANQAECggIDwAAAA==.',
Tu='Turdyl:BAABNQAECn8mAAIEAAoKzw4FogDdAQAEAAoKzw4FogDdAQAAAA==.Tuxxí:BAAANQADCgYIBgABNQAECgoKMgAVAFMfAA==.',
Tw='Twindadlock:BAAANQABCgIIAgABNQAECgQIEQADAAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyraz:BAAANQADCgUIBQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggIEQAAAA==.',
['Tá']='Tárris:BAABNQAECn8eAAINAAgKUh1AQgCLAgANAAgKUh1AQgCLAgABNQAECgoKMgAVAFMfAA==.',
['Tæ']='Tægia:BAAANQAECgUIBgAAAA==.',
['Tô']='Tôx:BAABNQAECn8bAAMKAAgK9h0pQgBtAgAKAAgK9h0pQgBtAgAJAAMKOAl27gCOAAAAAA==.',
Um='Umbranwings:BAABNQAECn8bAAQiAAcKrQg2JAAgAQAiAAcKrQg2JAAgAQAhAAYKAgOnNwDXAAAdAAEKAABZJwAmAAAAAA==.',
Un='Unheardjp:BAAANQAECgEIAQAAAA==.',
Ur='Ursus:BAABNQAECn8eAAIbAAkKwgjzUgCPAQAbAAkKwgjzUgCPAQAAAA==.',
Va='Vaerix:BAAANQAECgYIDQAAAA==.Valydrin:BAABNQAECn8tAAMfAAkK5hamCgA6AgAfAAkK5hamCgA6AgAFAAMKjwXUYgB1AAAAAA==.',
Ve='Veera:BAAANQADCgQIBAAAAA==.Vexadrine:BAACNQAFFH8PAAIYAAUKwBLiAwBxAQAYAAUKwBLiAwBxAQA1AAQKfzQAAhgACgooHjMFABIDABgACgooHjMFABIDAAAA.Vexiana:BAAANQAECgQIBQABNQAFFAUIDwAYAMASAA==.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vu='Vuldrak:BAAANQAECggICAAAAA==.',
Vy='Vysis:BAACNQAFFH8OAAIFAAYKYhCzCACBAQAFAAYKYhCzCACBAQA1AAQKfzgABAUACgpkHcwPAPgCAAUACgpkHcwPAPgCAB8ABwoOISdeAAcCAAYABQrUGuoKAJUBAAAA.',
['Ví']='Ví:BAAANQAECgEIAQAAAA==.',
Wa='Waroby:BAAANQABCgEIAQAAAA==.Warstorm:BAAANQAECgQIBAAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAABNQAECn8oAAQYAAkKLBc6AwB8AQAYAAkKLBc6AwB8AQASAAUKFxBKQgAFAQATAAQKWQgkOwCZAAAAAA==.Widgit:BAAANQADCgcIEwAAAA==.Wieldblade:BAABNQAECn8yAAMEAAoKwhPJhQAcAgAEAAoKwhPJhQAcAgAcAAYKSRMglABjAQAAAA==.',
Wo='Woolverine:BAABNQAECn8WAAMgAAYKIBMfKQCaAAAgAAQKfg4fKQCaAAAbAAQKyBblMgCSAAAAAA==.',
Wu='Wunderbar:BAABNQAECn8fAAIKAAgKeRgjCwC7AQAKAAgKeRgjCwC7AQAAAA==.',
Wy='Wyldfire:BAACNQAFFH8TAAIbAAUKDBvACwC1AQAbAAUKDBvACwC1AQA1AAQKfzYAAhsACgqXIfEIAIcDABsACgqXIfEIAIcDAAAA.',
Xa='Xanith:BAABNQAECn8XAAILAAoKSAucSQAMAQALAAoKSAucSQAMAQAAAA==.Xanyth:BAAANQADCggICAAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Ya='Yardly:BAAANQADCggIEgAAAA==.',
Yi='Yia:BAAANQAECgUIEAABNQAECgYIEAADAAAAAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECn8fAAMSAAoKgSKMBgBnAwASAAoKgSKMBgBnAwATAAIK5AoBQwBjAAAAAA==.',
Za='Zarich:BAABNQAECn8jAAImAAkK1xg5BACfAgAmAAkK1xg5BACfAgAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECggIIgAJAOAeAA==.Zogah:BAEANQAECgQIBAABNQAECggIIgAJAOAeAA==.Zoganian:BAEANQAECgQICQABNQAECggIIgAJAOAeAA==.Zoghog:BAAANQAECgUICAAAAA==.Zogula:BAEANQAECgQIBAABNQAECggIIgAJAOAeAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
Zy='Zyaire:BAAANQABCgQIBQAAAA==.',
['Æb']='Æbony:BAAANQABCgIIAgAAAA==.',
['Æn']='Ænimà:BAAANQAECgMIAwAAAA==.',
['Ço']='Çosmos:BAAANQADCgYIBwAAAA==.',
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
