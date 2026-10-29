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

local lookup = {'DemonHunter-Havoc','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Warlock-Affliction','Warlock-Destruction','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Priest-Holy','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Outlaw','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Paladin-Holy','Evoker-Augmentation','Shaman-Enhancement','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Rogue-Assassination','DemonHunter-Vengeance','Hunter-Survival',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Actualape:BAAANQAECgQIBgAAAA==.',
Ad='Addy:BAABNQAECn8xAAIBAAoKMxg6GwDDAQABAAoKMxg6GwDDAQAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAABNQAECn8bAAICAAcKrwbTLACpAAACAAcKrwbTLACpAAAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQAECgUIBgAAAA==.Aispere:BAAANQAECgEIAgABNQAECgQIDAADAAAAAA==.',
Al='Alerzhulan:BAAANQAECgUIEAAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAABNQAECn8nAAIEAAkKxQ5EpgDUAQAEAAkKxQ5EpgDUAQAAAA==.Alorely:BAABNQAECn8fAAMFAAgKfQ79MgCLAQAFAAgKfQ79MgCLAQAGAAMKWxCwCQCbAAAAAA==.',
Am='Amanara:BAABNQAECn8dAAMHAAYKPwhfTwDZAAAIAAUKyggVkADoAAAHAAYKxAVfTwDZAAAAAA==.Amoonia:BAAANQADCgYIFQAAAA==.',
An='Anciientpaw:BAABNQAECn8eAAMJAAgKux8bLwClAgAJAAgKux8bLwClAgAKAAMKIg3B9QCpAAAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgcIDwAAAA==.Anguirus:BAABNQAECn8oAAIKAAoKowRLqgA/AQAKAAoKowRLqgA/AQAAAA==.Anitax:BAABNQAECn8UAAILAAkKAg0iZAA6AQALAAkKAg0iZAA6AQABNQAECgoKJgAKAAgeAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Ao='Aoman:BAAANQAECgYIBQAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIFAAAAA==.Arcadian:BAABNQAECn9DAAMMAAoKhhFBOgDpAQAMAAoKXhFBOgDpAQANAAIKBRGdJQCCAAAAAA==.Arceeprime:BAAANQAECgMIAgAAAA==.Arextheelder:BAAANQAECgUIDAAAAA==.Argentum:BAAANQADCggICAABNQAECgoKMQABADMYAA==.Armorscales:BAABNQAECn8dAAILAAkKfSD4MwC5AgALAAkKfSD4MwC5AgAAAA==.Arntraz:BAAANQAECgIIBQAAAA==.Arrabbiato:BAABNQAECn8YAAIOAAcKLAo1sQCiAQAOAAcKLAo1sQCiAQAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashnikko:BAAANQAECgEIAQAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAABNQAECn8cAAIFAAoKlAs8HwAOAQAFAAoKlAs8HwAOAQAAAA==.Astayoni:BAAANQAECgQIBgAAAA==.Asterfleur:BAAANQAECgYICgABNQAECggICQADAAAAAA==.Astrine:BAABNQAECn8gAAMPAAkKKxUHHAAQAQAQAAkKOxPsowA5AgAPAAYKng8HHAAQAQAAAA==.',
At='Ataraxya:BAABNQAECn8WAAQRAAkK3g/iGQC3AAALAAYKSQ3+ewD/AAARAAMKaw/iGQC3AAASAAIKTRB0GABnAAAAAA==.',
Au='Auberon:BAABNQAECn8xAAITAAoKSiCyAgDPAgATAAoKSiCyAgDPAgAAAA==.Aufta:BAABNQAECn8iAAMUAAgKbAeaQwD8AAAUAAcKbAeaQwD8AAAVAAYKNgXdMgDTAAAAAA==.Aumer:BAAANQADCggICAAAAA==.Aura:BAAANQADCgcIBwAAAA==.',
Az='Azi:BAACNQAFFH8NAAIWAAUKjRSfCwCEAQAWAAUKjRSfCwCEAQA1AAQKfzoAAhYACgrtIA4HAIwCABYACgrtIA4HAIwCAAAA.Azurite:BAAANQADCgYIFQAAAA==.',
Ba='Backpedal:BAAANQAECgUIBQAAAA==.Badankhadonk:BAACNQAFFH8PAAMJAAUKQB4sCQC9AQAJAAUKQB4sCQC9AQAKAAEK1g6JMABJAAA1AAQKfz4AAwkACQr7JIcFAJsDAAkACQr7JIcFAJsDAAoABAoXHVmqAD8BAAAA.Bakkutteh:BAAANQABCgIIBAAAAA==.Bakuhiko:BAAANQAECgcIDwAAAA==.Balen:BAABNQAECn8WAAMEAAcK0Q72pAALAQAEAAcK2A32pAALAQACAAIKqQxGZQBMAAAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.Bariden:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAACNQAFFH8LAAMIAAcK4Q/KCACLAQAIAAUKNBPKCACLAQAHAAIKlwK8FABKAAA1AAQKfzEAAwgACQqrIwMZAPcCAAgACQoAIgMZAPcCAAcACAqWG1YUADYCAAAA.Beethozart:BAAANQADCggIGQAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAABNQAECn8fAAIXAAgKoB4/JQA/AgAXAAgKoB4/JQA/AgAAAA==.Beliice:BAAANQADCgIIAgABNQAECggIHwAXAKAeAA==.Bellafleur:BAAANQAECgQIEgABNQAECggICQADAAAAAA==.Bellawesome:BAAANQAECgMIAwAAAA==.Bendeekay:BAACNQAFFH8VAAIYAAUK0iPECwCYAQAYAAUK0iPECwCYAQA1AAQKfzYAAxgACgq8IiMJAHADABgACgq8IiMJAHADAAgAAgq4ElZOAH8AAAAA.Benilok:BAABNQAECn8WAAILAAYKjRhikQC7AQALAAYKjRhikQC7AQAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bf='Bfh:BAAANQAECggICAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQAECgEIAQAAAA==.',
Bl='Blackblood:BAABNQAECn8nAAIBAAgKwAu/SACEAQABAAgKwAu/SACEAQAAAA==.Bladestriker:BAAANQAECgMIAwAAAA==.Bloodache:BAABNQAECn8eAAIZAAkKFiEXEADxAgAZAAkKFiEXEADxAgAAAA==.Blux:BAAANQAECgQIBgAAAA==.',
Bo='Boil:BAABNQAECn8uAAIaAAgK8AVoBQDXAAAaAAgK8AVoBQDXAAAAAA==.Bonemarrow:BAAANQAECgUIDAAAAA==.Bordin:BAAANQADCgYIDAAAAA==.Bows:BAAANQAECggICAAAAA==.',
Br='Brakeable:BAAANQAECgYICQAAAA==.Braké:BAABNQAECn8ZAAICAAgKFCDkFABbAgACAAgKFCDkFABbAgAAAA==.Brewskies:BAABNQAECn87AAIbAAoKhiPyAAAtAwAbAAoKhiPyAAAtAwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brioche:BAAANQADCgUIBgAAAA==.Brionthicc:BAAANQAECgUICAABNQAFFAcIEQASAEQRAA==.Brownington:BAABNQAECn8pAAQcAAkK3SPiBwBkAgAcAAgKhCPiBwBkAgAdAAYKwB84PgAHAgATAAIK0yFFKwC3AAAAAA==.Bruhilda:BAAANQAECgYIDQAAAA==.Brìonik:BAACNQAFFH8RAAQSAAcKRBHeCQCnAAALAAQK1Au2JADbAAASAAIKbRneCQCnAAARAAEKAADIDgAAAAA1AAQKf0EABBIACgqiIDUHAJQCABIACArsGzUHAJQCAAsACAoxHrwuAPQBABEAAgqfFAMQAIwAAAAA.',
Bu='Bubbleroundi:BAABNQAECn9EAAIeAAoKNhKbJgAaAgAeAAoKNhKbJgAaAgAAAA==.Bubudder:BAABNQAECn9BAAMIAAoKliNrDABXAwAIAAkKYiJrDABXAwAHAAoKqh8hCADlAgAAAA==.Buffstuff:BAABNQAECn8tAAIfAAoK4w3vBQCHAQAfAAoK4w3vBQCHAQAAAA==.Burgerlock:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAABNQAECn8jAAIFAAoKTQglFwBhAQAFAAoKTQglFwBhAQAAAA==.Canadaishere:BAAANQADCgMIAwAAAA==.Canadaispimp:BAAANQADCgEIAQAAAA==.Cantheartitz:BAAANQAECgYIDAAAAA==.Catdav:BAABNQAECn8iAAIgAAgK5B3iCwDdAQAgAAgK5B3iCwDdAQAAAA==.',
Ch='Charbol:BAAANQADCgQICAABNQADCggIEQADAAAAAA==.Chelraani:BAABNQAECn8nAAIEAAkKNxiXSADeAQAEAAkKNxiXSADeAQAAAA==.Chess:BAAANQAECggIEAAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBgAAAA==.',
Ci='Ciarianna:BAAANQADCgcIBwABNQAECgoKMQABADMYAA==.Cigar:BAAANQADCgUICQABNQAECgYIEAADAAAAAA==.',
Cl='Clazzicola:BAACNQAFFH8KAAIUAAUKgBm/CQAyAQAUAAUKgBm/CQAyAQA1AAQKfycAAhQACgptIf0VAKECABQACgptIf0VAKECAAAA.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgQICwAAAA==.Coogsayer:BAAANQADCgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.Cowgoboom:BAAANQADCgUICQAAAA==.',
Cp='Cptncrush:BAABNQAECn8hAAMJAAcKKxwAVwANAgAJAAcKKxwAVwANAgAKAAMKexMcggCaAAAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.Creature:BAAANQAECgQIBgAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAABNQAECn8jAAIFAAkKaBQ2IAA4AgAFAAkKaBQ2IAA4AgAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAACNQAFFH8RAAINAAcKRBiVAADPAQANAAcKRBiVAADPAQA1AAQKf0EAAg0ACgp0JXEAAF0DAA0ACgp0JXEAAF0DAAAA.',
Da='Dadbodftw:BAAANQAECgQIEQAAAA==.Daddylight:BAABNQAECn8mAAIEAAkKfA4kewBbAQAEAAkKfA4kewBbAQAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Damaclese:BAAANQABCgUIBQAAAA==.Darkdottie:BAAANQAECggIDwAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgQIAwAAAA==.Dayday:BAAANQAECggICAAAAA==.',
De='Deadlight:BAABNQAECn8uAAIHAAkKVxBaOAD0AQAHAAkKVxBaOAD0AQAAAA==.Deadtofall:BAAANQADCggIHAAAAA==.Deathshikzs:BAABNQAECn8mAAMYAAkKBBzLKgBwAgAYAAkKBBzLKgBwAgAIAAEK1QdqcgArAAABNQAECgoKJgAKAAgeAA==.Decix:BAAANQAFFAEIAQABNQAFFAQIDAAFAH8VAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAABNQAECn8fAAMNAAoK5B4yAwAsAwANAAoK5B4yAwAsAwAMAAIK8BIzLQF6AAABNQAECgoKLgAUAD8aAA==.Demonllxll:BAAANQAECgUIDgAAAA==.Demontime:BAAANQADCgcIDAABNQAECgQIBAADAAAAAA==.Desolation:BAABNQAECn83AAIQAAoKkCIAGgCaAgAQAAoKkCIAGgCaAgAAAA==.Despia:BAABNQAECn8nAAMXAAkKdSFyEwDLAgAXAAkKdSFyEwDLAgAFAAQK8wwzUQDMAAAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAABNQAECn8nAAMhAAkKnQ+ZHgBrAQAhAAkKnQ+ZHgBrAQAdAAYKWwOfhAC/AAAAAA==.Diety:BAABNQAECn8uAAIUAAoKPxpYEwC/AgAUAAoKPxpYEwC/AgAAAA==.Dimension:BAAANQAECgEIAQAAAA==.Disconnect:BAAANQABCgYICwAAAA==.',
Dj='Djpallyd:BAABNQAECn8sAAIEAAoKFxrYMgAuAgAEAAoKFxrYMgAuAgAAAA==.',
Do='Dornoll:BAAANQADCgQIBAAAAA==.Dotmami:BAAANQAECgcICwAAAA==.Doughy:BAAANQADCggIEAAAAA==.',
Dr='Dragonu:BAABNQAECn9KAAMiAAoKdCFUAgBaAwAiAAoKdCFUAgBaAwAjAAEKAACGPAA1AAABNQAFFAUIDwALAA8SAA==.Draktyr:BAACNQAFFH8LAAIMAAYKRBFKGwA5AQAMAAYKRBFKGwA5AQA1AAQKfzQAAwwACgp9IvgXAFkDAAwACgp9IvgXAFkDAA0AAQoAABQ2AC4AAAAA.Drlovely:BAAANQADCgQIBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Elianda:BAAANQADCggIDgAAAA==.Ellalais:BAAANQAECgQICgAAAA==.Ellismom:BAABNQAECn86AAIIAAoKFxoKEgAEAgAIAAoKFxoKEgAEAgAAAA==.',
En='Enamorada:BAAANQAECgQICQABNQAECgkJIgAJAIwcAA==.Enchanceurpp:BAAANQADCggIGQAAAA==.End:BAAANQAECgUICAAAAA==.',
Eo='Eolyndin:BAAANQADCgQIBAAAAA==.Eolyndyn:BAAANQADCgYICQAAAA==.',
Ep='Epialos:BAAANQAECggICAAAAA==.',
Er='Ereithelda:BAACNQAFFH8OAAIVAAUK7hZZBACWAQAVAAUK7hZZBACWAQA1AAQKf0QAAhUACgqRJOYBAJoDABUACgqRJOYBAJoDAAAA.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAFFAUIDwALAA8SAA==.Errutu:BAABNQAECn87AAIkAAoKARG+GgABAgAkAAoKARG+GgABAgAAAA==.',
Ev='Evox:BAABNQAECn8aAAMKAAYKShVEVAAQAQAKAAYKShVEVAAQAQAgAAUKvQQHHgC8AAAAAA==.',
Ex='Exodiadruid:BAAANQAECgIIAgAAAA==.',
Fa='Falgar:BAAANQAECgQIBAAAAA==.Fann:BAABNQAECn8jAAIhAAgKzgZ5QgAWAQAhAAgKzgZ5QgAWAQAAAA==.Fargrim:BAAANQADCggIEQAAAA==.Fauna:BAAANQADCggICAAAAA==.Faytl:BAAANQAECgUIBQAAAA==.',
Fe='Feathiir:BAAANQADCgIIAgAAAA==.Feefifofum:BAAANQADCgUIBQAAAA==.Fewz:BAACNQAFFH8YAAMPAAUKlCN3AAD8AQAPAAUKlCN3AAD8AQAQAAEKAABDZAA/AAA1AAQKfz0AAw8ACgoFJmsAANMDAA8ACgoFJmsAANMDABAAAgorDZsiAT4AAAAA.',
Fl='Flakflap:BAAANQAECgUIBQABNQAFFAIIBQAYADsPAA==.Flakov:BAAANQADCggIDgABNQAFFAIIBQAYADsPAA==.Flaktop:BAACNQAFFH8FAAIYAAIKOw/LIwBvAAAYAAIKOw/LIwBvAAA1AAQKfy8AAhgACQqGHikgALICABgACQqGHikgALICAAAA.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgUIBQAAAA==.Fluffie:BAAANQABCgcICgAAAA==.',
Fo='Forbacon:BAABNQAECn8vAAMYAAoKORiHGQDKAQAYAAoKORiHGQDKAQAHAAQKvAlWhwCUAAAAAA==.Force:BAABNQAECn8dAAMHAAgKYgW0ZgAGAQAHAAgKYgW0ZgAGAQAIAAEKRwMr9QAiAAAAAA==.Fouris:BAAANQAECgYICwAAAA==.',
Fr='Fridgie:BAACNQAFFH8RAAIOAAcK+hDDCgChAQAOAAcK+hDDCgChAQA1AAQKfz8AAg4ACgolJEQGACwDAA4ACgolJEQGACwDAAAA.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenruby:BAAANQABCggIDwAAAA==.Frozenturtle:BAABNQAECn8cAAIYAAcKwhw9QQD5AQAYAAcKwhw9QQD5AQAAAA==.',
Ft='Ftwiamtank:BAABNQAECn8kAAIlAAoK4Qw+DAB3AQAlAAoK4Qw+DAB3AQAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAACNQAFFH8MAAIQAAcKQwnUIACBAQAQAAcKQwnUIACBAQA1AAQKfzsAAhAACgofH+MVALMCABAACgofH+MVALMCAAAA.',
Ge='Geddan:BAAANQAECgMIBAAAAA==.Genericck:BAACNQAFFH8HAAMdAAMKVxQ/CwDhAAAdAAMK7RA/CwDhAAAcAAIKPxd3BACKAAA1AAQKfxkAAx0ACQopHhwPAFYCABwACApoHpwOAHoCAB0ACQq9GRwPAFYCAAAA.Genericdh:BAAANQAFFAEIAQAAAA==.Generickdk:BAAANQAECgQIBAAAAA==.Genericpal:BAABNQAECn8qAAMCAAkKFSEgCgD5AgACAAgKQSQgCgD5AgAEAAMKUQ/yRgGvAAAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.',
Gn='Gnawbear:BAEBNQAECn9AAAMmAAoKIB0pBACdAgAmAAoKnRwpBACdAgAkAAgKhxuQJAD/AQAAAA==.',
Go='Goatassassin:BAABNQAECn8sAAMkAAkKKRj/FQAyAgAkAAkKKRj/FQAyAgAmAAIKawr+kABuAAAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECgkJLAAkACkYAA==.Gobogoolina:BAAANQADCgYIDgAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQAECgQIDAAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Haikuu:BAAANQADCgcIBwAAAA==.Hail:BAAANQAECgQIBAAAAA==.Hamnqueso:BAAANQADCgYIDgABNQAECgQIEQADAAAAAA==.Hardeesdelux:BAAANQAECgQICwABNQAECgYICAADAAAAAA==.Hazis:BAACNQAFFH8GAAIYAAQK5hGVFQAGAQAYAAQK5hGVFQAGAQA1AAQKfzQAAhgACgo4HO8VAP0CABgACgo4HO8VAP0CAAAA.',
Hi='Hinala:BAABNQAECn8sAAIYAAkKmwvGVQCdAQAYAAkKmwvGVQCdAQAAAA==.',
Ho='Holy:BAAANQAFFAEIAQABNQAFFAUIDAAKAEwLAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybloom:BAAANQAECgEIAQAAAA==.Honeybutter:BAACNQAFFH8FAAIMAAMK4SMzJADdAAAMAAMK4SMzJADdAAA1AAQKf0MAAwwACgoxJswCAOYDAAwACgoxJswCAOYDAA0AAQoAAJcxADoAAAAA.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAAANQAECgcIEQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAABNQAECn87AAIOAAoKLSE8JAAGAwAOAAoKLSE8JAAGAwAAAA==.',
In='Inanitas:BAAANQAECgQIBAAAAA==.Innominot:BAAANQAECgUIBwAAAA==.',
Ir='Irukox:BAAANQAECgQIBgAAAA==.',
Ja='Jackoldean:BAAANQADCgUICwAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jadefleur:BAAANQAECgEIAQABNQAECggICQADAAAAAA==.Jalene:BAABNQAECn8YAAIEAAYKcBLqugDlAAAEAAYKcBLqugDlAAAAAA==.Jargen:BAAANQADCgYIBwABNQADCggIEQADAAAAAA==.',
Je='Jemma:BAAANQAECgUIBQAAAA==.Jettabae:BAAANQAECgIIBAABNQAFFAcIEQAEAGEKAA==.Jettadari:BAAANQAECgYICgABNQAFFAcIEQAEAGEKAA==.Jettadin:BAACNQAFFH8RAAIEAAcKYQoFDgBrAQAEAAcKYQoFDgBrAQA1AAQKfzcAAgQACgp6Il4dAJ0CAAQACgp6Il4dAJ0CAAAA.',
Jt='Jt:BAABNQAECn8WAAIEAAkKUBi4QAD5AQAEAAkKUBi4QAD5AQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAACNQAFFH8RAAIJAAcKXRVMCgCpAQAJAAcKXRVMCgCpAQA1AAQKfzoAAwkACgrYH5wYABADAAkACgrYH5wYABADACAACAozHlUHAFACAAAA.',
Ka='Kaitllyn:BAAANQADCgYIBgAAAA==.Kakozaps:BAACNQAFFH8KAAMgAAUKnxhfAgCyAQAgAAUKnxhfAgCyAQAKAAEKmAzFMQBGAAA1AAQKf1YAAyAACgraJI0BAC0DACAACgrXJI0BAC0DAAoACAo7IJg4AJQCAAAA.Kaldor:BAAANQADCgUICAAAAA==.Kalid:BAAANQAECgIIAgAAAA==.Kallar:BAAANQAECggIEwAAAA==.Kathrynne:BAAANQAECgcIDAAAAA==.Kayeera:BAABNQAECn8bAAIXAAoKnQe4QACxAQAXAAoKnQe4QACxAQAAAA==.Kaylrandi:BAAANQAECgEIAQAAAA==.Kayna:BAAANQAECgUIBwAAAA==.',
Ke='Kearza:BAAANQAECgUIDwAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgoKJQAEAG4VAA==.Kennethv:BAABNQAECn8dAAIXAAYK6RpQQwCkAQAXAAYK6RpQQwCkAQAAAA==.Keny:BAAANQAECgUJBgABNQAECgYIEAADAAAAAA==.Kero:BAAANQADCgcICgABNQAECggIEwADAAAAAA==.Kethie:BAAANQADCggIDwAAAA==.Kethra:BAAANQADCgQICwAAAA==.Kev:BAAANQAECggIBAAAAA==.Keyalerong:BAAANQABCgQIBAAAAA==.',
Kh='Khalesie:BAAANQADCgIIBAAAAA==.Khibanee:BAAANQAECgQIDQAAAA==.Khiell:BAABNQAECn8qAAMNAAkK4RlZCQBDAgANAAgKwxtZCQBDAgAMAAIKxw/UNgFmAAAAAA==.Khrominius:BAABNQAECn8bAAIQAAgKuxGJ4wDCAQAQAAgKuxGJ4wDCAQAAAA==.',
Ki='Killthirsty:BAAANQADCgcIBwABNQAECgUIBQADAAAAAA==.Kinigit:BAAANQAECgcIDwABNQAFFAUIGAAdAM8bAA==.Kirïtö:BAAANQAECgUIBQAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAACNQAFFH8NAAIQAAQKQw0xGwDWAAAQAAQKQw0xGwDWAAA1AAQKfzUAAhAACgqTHB0cAI4CABAACgqTHB0cAI4CAAAA.',
Ko='Komamura:BAAANQAECgMIAwAAAA==.Konpalitaa:BAAANQAECgUICAAAAA==.',
Kr='Kragon:BAAANQADCggICAAAAA==.Krátos:BAABNQAECn8sAAIMAAoKNhz0KAA+AgAMAAoKNhz0KAA+AgAAAA==.',
Ku='Kungphu:BAAANQADCgcIDwAAAA==.Kuranaa:BAAANQAECgQIDAAAAA==.Kurulak:BAABNQAECn8yAAIZAAoKKAwVFwCDAQAZAAoKKAwVFwCDAQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.Kynn:BAAANQADCggIDwAAAA==.',
La='Lacerveza:BAAANQAECgMIBQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.Laylah:BAAANQAECgIIAQAAAA==.',
Le='Leriope:BAABNQAECn87AAILAAoKtA/LPAC2AQALAAoKtA/LPAC2AQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgUIDQABNQAECgoKLwAMAE0eAA==.Lilem:BAAANQADCgcICwAAAA==.Limboh:BAAANQADCgcIBwAAAA==.',
Lj='Lj:BAABNQAECn8yAAIeAAoKEx58FwCIAgAeAAoKEx58FwCIAgAAAA==.',
Lo='Lovecrafft:BAAANQADCgQIBAAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcILAAAAA==.Mager:BAAANQAECgIIAwAAAA==.Mageshyte:BAACNQAFFH8IAAIQAAUK8QzlIgBwAQAQAAUK8QzlIgBwAQA1AAQKf0AAAhAACgrGH5sbAJECABAACgrGH5sbAJECAAAA.Magolock:BAABNQAECn8VAAILAAYKMBzzkwC0AQALAAYKMBzzkwC0AQAAAA==.Magus:BAAANQAECgUIBQAAAA==.Maidrim:BAACNQAFFH8LAAImAAcKxxIvBwCmAQAmAAcKxxIvBwCmAQA1AAQKfzwAAiYACgrIIjgCAAUDACYACgrIIjgCAAUDAAAA.Mamajumbo:BAABNQAECn8dAAIOAAgKbxZIiwD0AQAOAAgKbxZIiwD0AQAAAA==.Mana:BAACNQAFFH8MAAIKAAUKTAuhEQBSAQAKAAUKTAuhEQBSAQA1AAQKfzoAAgoACgoqHjcrANMCAAoACgoqHjcrANMCAAAA.Marellias:BAABNQAECn8jAAMOAAkKISMXBQA9AwAOAAkKISMXBQA9AwAWAAEK7wb5kQAuAAABNQAECgoKMAAEAHgmAA==.Marikel:BAAANQAECgQIDAAAAA==.Marlea:BAABNQAECn8qAAMMAAkKChRTUgCMAQAMAAkKChRTUgCMAQANAAEKAAAaKwBaAAAAAA==.Maruka:BAABNQAECn9HAAILAAoK5iALEABSAwALAAoK5iALEABSAwAAAA==.Matthiias:BAAANQAECgIIBAAAAA==.Mawenzi:BAAANQADCggICAABNQAECgkJMgAXAEcQAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Meronpan:BAAANQAECggIDAAAAA==.Metahorfasis:BAAANQADCgcIBwAAAA==.',
Mi='Michaelken:BAABNQAECn8eAAIeAAgKUBTlbwDIAQAeAAgKUBTlbwDIAQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIJAgAAAA==.Migrains:BAABNQAECn86AAICAAoKTh4vBwBtAgACAAoKTh4vBwBtAgAAAA==.Mileyvyrus:BAAANQAFFAEIAQABNQAFFAYIDwAlAAEiAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQALAH0gAA==.Miskaabin:BAABNQAECn8gAAMCAAcKoBPQJwCfAQACAAcKoBPQJwCfAQAEAAUKLAeOJwHeAAAAAA==.Missdemon:BAAANQADCggICAAAAA==.Missusgrey:BAAANQADCggICAABNQAECgkJLAAXAEkiAA==.',
Mo='Mogral:BAAANQADCgUICwAAAA==.Mojodaddy:BAAANQABCgQIBgAAAA==.Mojogreens:BAAANQADCgUICwAAAA==.Monsart:BAAANQAECgYIBQAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgMJBQAAAA==.Moralizdormi:BAABNQAECn8xAAIfAAkKTAkpDQB9AQAfAAkKTAkpDQB9AQAAAA==.Moregana:BAAANQAECgIIAQAAAA==.Mortiis:BAABNQAECn8VAAIgAAkKjgepDgCiAQAgAAkKjgepDgCiAQAAAA==.',
Mp='Mpd:BAAANQAECgYICAAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAABNQAECn8UAAInAAgK3wZhEADPAAAnAAgK3wZhEADPAAAAAA==.Mytmo:BAAANQAECgMIAwAAAA==.',
['Mí']='Míerín:BAACNQAFFH8SAAIOAAUKshyBCQAHAQAOAAUKshyBCQAHAQA1AAQKfzwAAg4ACgoQJZsFALUDAA4ACgoQJZsFALUDAAAA.',
Na='Naama:BAAANQADCgcIIAAAAA==.Naelih:BAABNQAECn8XAAIWAAgKxQgrPABwAQAWAAgKxQgrPABwAQAAAA==.Natlès:BAAANQAECgYICAABNQAECgcICwADAAAAAA==.Natzu:BAAANQAECgMIBQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAACNQAFFH8HAAIEAAUKMQODFwDtAAAEAAUKMQODFwDtAAA1AAQKfzwAAgQACgqVGJY9AAQCAAQACgqVGJY9AAQCAAAA.',
Ne='Necronu:BAAANQADCggICAABNQAFFAUIDwALAA8SAA==.',
Ni='Nikkolos:BAAANQAECgMIBAAAAA==.',
No='Nogusta:BAACNQAFFH8OAAIMAAcKUgnVFgBuAQAMAAcKUgnVFgBuAQA1AAQKf0EAAgwACgqSIWgQAOICAAwACgqSIWgQAOICAAAA.Notdecix:BAACNQAFFH8MAAMFAAQKfxVXDQADAQAFAAMKfxVXDQADAQAXAAIKcAEAMABiAAA1AAQKfzAAAwUACgouIeQEAN4CAAUACgouIeQEAN4CABcACApdFltYABkCAAAA.',
Nu='Nuggets:BAAANQAECgYIDwAAAA==.',
Ob='Obyss:BAAANQADCgUIBQAAAA==.',
Od='Odell:BAAANQADCgIIAgABNQADCggIEQADAAAAAA==.Odinsrain:BAAANQAECgUIBgABNQAFFAIIBQAeAAkYAA==.',
On='Onlyshams:BAAANQAECggIEgAAAA==.Onubolt:BAAANQADCgMIAwABNQAFFAUIDwALAA8SAA==.Onulock:BAACNQAFFH8PAAMLAAUKDxKEDQDoAAALAAUKDxKEDQDoAAARAAEKAACrDgAAAAA1AAQKfyEABAsACgqDHV8bAFsCAAsACgqDHV8bAFsCABIAAQr1Ha4fAE8AABEAAQoAAFIoAEoAAAAA.Onux:BAAANQAECgcICAABNQAFFAUIDwALAA8SAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAABNQAECn8cAAIEAAYKJRc7jAA5AQAEAAYKJRc7jAA5AQAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Palinia:BAAANQAECgcICgABNQAECgcIGAAIAHUFAA==.Pallyoop:BAABNQAECn8eAAMeAAkK+AznfQCgAQAeAAkK+AznfQCgAQAEAAYKkgVrGQH1AAAAAA==.Pandarina:BAAANQAECgQIBAAAAA==.Papilock:BAAANQADCgUIBQABNQAECgkJIgAJAIwcAA==.Pathalogical:BAAANQADCggIDwABNQAECgkJFgAOAE4bAA==.Patharok:BAAANQADCgMIAwABNQAECgkJFgAOAE4bAA==.Pathator:BAABNQAECn8WAAMOAAkKThs3XwCBAQAOAAgKThs3XwCBAQAWAAEKAAA5kQAvAAAAAA==.Patheros:BAAANQAECggIDwABNQAECgkJFgAOAE4bAA==.Patholan:BAAANQAECgQIBAABNQAECgkJFgAOAE4bAA==.Patholans:BAAANQADCgEIAQABNQAECgkJFgAOAE4bAA==.Pathsqueek:BAAANQADCggICAABNQAECgkJFgAOAE4bAA==.Paxmansigh:BAAANQAECgUICgAAAA==.',
Pe='Perineumm:BAAANQABCgUIBQAAAA==.',
Ph='Phantöm:BAABNQAECn8xAAINAAkKOh37BQDoAQANAAkKOh37BQDoAQAAAA==.',
Pi='Pickle:BAAANQADCgYIBgABNQAECggIJAAeAMciAA==.Piratesmoke:BAAANQADCgYIAwAAAA==.',
Pl='Placcid:BAABNQAECn8yAAIOAAoK7BAxPADwAQAOAAoK7BAxPADwAQAAAA==.Planknstein:BAABNQAECn8ZAAIEAAkKYwo5cgBvAQAEAAkKYwo5cgBvAQAAAA==.Plantoor:BAABNQAECn86AAIoAAkKbBZCAwABAgAoAAkKbBZCAwABAgAAAA==.',
Po='Pockett:BAAANQAECgIIAgAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAABNQAECn87AAMJAAoKQxA8LQDyAQAJAAoKQxA8LQDyAQAKAAkKtQo/eQC3AQAAAA==.',
Pr='Preedo:BAAANQADCgMIAwAAAA==.Primøs:BAAANQAECgYIDQAAAA==.Prismclaw:BAABNQAECn8qAAIPAAoKxQ+sBwCuAQAPAAoKxQ+sBwCuAQAAAA==.Processing:BAACNQAFFH8RAAIdAAcKWw6dCwC3AQAdAAcKWw6dCwC3AQA1AAQKfz4AAh0ACgpWIv0HANkCAB0ACgpWIv0HANkCAAAA.',
Pu='Puddle:BAAANQAECggIDQAAAA==.Puddleheal:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.Puffdamagic:BAABNQAECn8+AAMiAAoKIA0wDgCTAQAiAAoKIA0wDgCTAQAfAAgKswf7DQBqAQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQAECgUIBQAAAA==.',
Qi='Qirstbytt:BAAANQADCgUIBQAAAA==.',
Qp='Qplus:BAABNQAECn8kAAIOAAgKVQs6rwCmAQAOAAgKVQs6rwCmAQAAAA==.',
Qs='Qstorm:BAAANQADCgcIDQAAAA==.',
Qu='Quaenie:BAABNQAECn8iAAIXAAgKQA57iQB6AQAXAAgKQA57iQB6AQAAAA==.Quintin:BAAANQAECgYIBgAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgQICAAAAA==.Rayleigh:BAABNQAECn8dAAMPAAYK4RqCEACfAQAPAAYK4RqCEACfAQAQAAEKMwoqwwE5AAABNQAECgUIBQADAAAAAA==.',
Re='Reckligence:BAAANQADCgIIAgAAAA==.Redchord:BAAANQAECgYIEgAAAA==.Regidør:BAABNQAFFH8JAAMEAAQKpxfxFgDzAAAEAAMKpxfxFgDzAAAeAAEKRBU+GgBRAAAAAA==.Regixa:BAABNQAECn8YAAIQAAoK4ghPmgAQAQAQAAoK4ghPmgAQAQAAAA==.Relik:BAABNQAECn8dAAMlAAgKmRBKJAAlAQAlAAcKcw9KJAAlAQAMAAUKkgwB9gDyAAAAAA==.',
Rh='Rhaelia:BAAANQADCgUIBQAAAA==.Rhaspus:BAABNQAECn8cAAIBAAcKYxGzMgAUAQABAAcKYxGzMgAUAQAAAA==.',
Ri='Rillenne:BAAANQAECgQICAAAAA==.Rilliccine:BAAANQAECgcIDAAAAA==.Rilliguine:BAAANQAECgIIAgAAAA==.Rillinetti:BAABNQAECn8sAAILAAgKFBInUABzAQALAAgKFBInUABzAQAAAA==.Rillini:BAAANQAECgUICgAAAA==.Rilliti:BAAANQAECgIIBgAAAA==.Risky:BAAANQADCgIIAgABNQAECgQIBgADAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAABNQAECn8nAAIOAAkKeSIQFQCqAgAOAAkKeSIQFQCqAgAAAA==.Rookdh:BAACNQAFFH8RAAIBAAcK/Q6iCQCPAQABAAcK/Q6iCQCPAQA1AAQKf0AAAgEACgraIRsHAOgCAAEACgraIRsHAOgCAAAA.Rosey:BAABNQAECn8pAAIEAAgKqw+WggBMAQAEAAgKqw+WggBMAQAAAA==.Royale:BAABNQAECn8bAAIOAAkKQxaTiwDzAQAOAAkKQxaTiwDzAQAAAA==.',
Ru='Rudeus:BAAANQAECgQIBgAAAA==.Rudyeightbal:BAAANQADCgYIBgAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECggIDgAAAA==.Sagesse:BAAANQAECgQIBAAAAA==.Saisera:BAAANQAECgcICgAAAA==.Samifleur:BAAANQAECggICQAAAA==.Sammy:BAABNQAECn8jAAMEAAgKSwup2wBkAQAEAAgKSwup2wBkAQAeAAEKaQH1OQEbAAAAAA==.Santaclaaws:BAACNQAFFH8PAAIZAAUKsyLHBQDPAQAZAAUKsyLHBQDPAQA1AAQKf0AAAxkACgobI84CAK4DABkACgobI84CAK4DAAEAAgo/HLJ6AI0AAAAA.Santafuego:BAAANQAECgUICgABNQAFFAUIDwAZALMiAA==.Santapal:BAABNQAECn8yAAMeAAoKMB0iIgDkAgAeAAoKMB0iIgDkAgAEAAEKBAR7vgEpAAABNQAFFAUIDwAZALMiAA==.Saphotic:BAAANQAFFAIIAQABNQAFFAQIDAAFAH8VAA==.Saydragon:BAAANQADCgQIBAAAAA==.Sayvil:BAAANQAECgcIIgABNQAECggIEwADAAAAAQ==.',
Se='Selbor:BAABNQAECn8WAAIEAAcKYAZCvgDfAAAEAAcKYAZCvgDfAAAAAA==.Semmers:BAABNQAECn8YAAIVAAkKvwz8IQB1AQAVAAkKvwz8IQB1AQAAAA==.Sensational:BAAANQAECggIEgAAAA==.Septiria:BAAANQAECgUIEAAAAA==.Sergio:BAAANQADCgcIDwAAAA==.Seyren:BAAANQAECgYIBQAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgADAAAAAA==.Shadwizmoney:BAAANQADCgEIAQAAAA==.Shalash:BAAANQADCgYIBgABNQAFFAUIDwAmAO0WAA==.Shamadeano:BAABNQAECn8WAAMgAAYK4xN8FABAAQAgAAYK4xN8FABAAQAJAAEKUgLgKwEjAAAAAA==.Shamanshikz:BAABNQAECn8mAAIKAAoKCB61GAA5AgAKAAoKCB61GAA5AgAAAA==.Shamiska:BAABNQAECn8UAAIgAAgKTARPJQAHAQAgAAgKTARPJQAHAQAAAA==.Shammerdown:BAAANQADCgQIBAAAAA==.Shampooh:BAAANQAECgQIBgAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAABNQAECn82AAIJAAoKIxwqKQC/AgAJAAoKIxwqKQC/AgAAAA==.Sharazzy:BAAANQAECgIIAgAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shazami:BAAANQADCggIDwAAAA==.Shian:BAABNQAECn8nAAIcAAkKyRJJFwBWAQAcAAkKyRJJFwBWAQAAAA==.Shieldee:BAABNQAECn8rAAIEAAoKbRo3QQD3AQAEAAoKbRo3QQD3AQAAAA==.Shigaraki:BAABNQAECn8VAAMlAAgKchTICgCWAQAlAAgKyhPICgCWAQAMAAQK3A6b8gD6AAAAAA==.Shikzzs:BAABNQAECn8jAAInAAkKbiIqBAAMAwAnAAkKbiIqBAAMAwABNQAECgoKJgAKAAgeAA==.Shockeei:BAABNQAECn8rAAIQAAkKHSRQIgBTAwAQAAkKHSRQIgBTAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQAECgcICwAAAA==.',
Si='Siakora:BAAANQAECgMIAwABNQAFFAcIEQAdAFsOAA==.Sickwitit:BAABNQAECn8YAAMQAAgKFwRK9QBzAAAQAAgKjAJK9QBzAAAPAAgKBALJKwA6AAAAAA==.Sighh:BAAANQADCgQIBQAAAA==.Sighhy:BAAANQADCggIDQAAAA==.Sijth:BAABNQAECn9TAAMeAAgK7R5vJwDLAgAeAAgK7R5vJwDLAgAEAAQKbRGZQgG2AAAAAA==.Silvereyes:BAAANQADCgIIAgAAAA==.Silverwar:BAABNQAECn8pAAMlAAkKfxlfDABvAgAlAAkKfxlfDABvAgANAAEKkQeZIgA3AAAAAA==.Simmi:BAEANQAECgYICwABNQAFFAcIEAAeADYZAA==.Simmune:BAECNQAFFH8QAAIeAAcKNhm0BwDrAQAeAAcKNhm0BwDrAQA1AAQKfzUAAh4ACgoQI0gGAGkDAB4ACgoQI0gGAGkDAAAA.Sinarala:BAAANQADCggIEQAAAA==.Sirlavan:BAAANQAECgYIBQAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skanknstein:BAAANQAECgUICgAAAA==.Skepti:BAABNQAECn8lAAIOAAkKYR23PAC0AgAOAAkKYR23PAC0AgAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAABNQAECn8qAAIgAAkKTAbeFQArAQAgAAkKTAbeFQArAQAAAA==.',
Sm='Smeeta:BAABNQAECn85AAIYAAoKqR+bFgD4AgAYAAoKqR+bFgD4AgAAAA==.Smokesmash:BAAANQADCgcIDgAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Solaace:BAAANQADCgcIDgABNQAECgQIEwADAAAAAA==.Soram:BAAANQADCgYIBgAAAA==.Sosa:BAAANQAECgMIBwABNQAFFAcIHAACAEQlAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBAAAAA==.Soùl:BAAANQAECgYIEAAAAA==.',
Sp='Sparkley:BAAANQAECgUICQABNQAECgoKPgAiACANAA==.Spike:BAAANQAECggIDwAAAA==.Spinspinspin:BAAANQAECggIEQABNQAECggICQADAAAAAA==.',
St='Starlara:BAAANQADCgYIBgAAAA==.Stazz:BAABNQAECn8vAAIOAAoK7gj3oADEAQAOAAoK7gj3oADEAQAAAA==.Steelerayne:BAABNQAECn8aAAIOAAYKVxMucABWAQAOAAYKVxMucABWAQAAAA==.Stian:BAAANQAECgIIAgAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAABNQAECn8bAAIKAAgK+xHFbADaAQAKAAgK+xHFbADaAQAAAA==.Stormii:BAAANQAECgEIAQAAAA==.Stormtotem:BAAANQAECgEIAQAAAA==.Strangerdk:BAABNQAECn8YAAIIAAcKdQWJhgAHAQAIAAcKdQWJhgAHAQAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECn9FAAIcAAoKggunGABJAQAcAAoKggunGABJAQAAAA==.Swordfish:BAAANQAECgUIBgAAAA==.',
Sy='Sybrooke:BAAANQAECgEIAQAAAA==.Sydran:BAAANQAECgYICwAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAABNQAECn87AAIPAAoK3CAhAwAdAwAPAAoK3CAhAwAdAwAAAA==.Taegia:BAAANQADCgUIBQABNQAFFAUIDgAVAO4WAA==.Talanth:BAABNQAECn8dAAImAAgK3AulHgANAQAmAAgK3AulHgANAQAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tandisong:BAAANQAECgIIAQAAAA==.Tanitie:BAAANQADCgEIAQAAAA==.Tanknstein:BAAANQAECgUIBwAAAA==.Tarma:BAAANQADCgMIAwAAAA==.Taro:BAAANQADCggICAABNQAECgoKIAAKAAgJAA==.Tarrisx:BAAANQADCgEJAQABNQAECgoKOQAYAKkfAA==.Tashi:BAAANQAECgMIAwAAAA==.Tayon:BAAANQAECgYIDQAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Tearza:BAAANQADCggICwAAAA==.Tempest:BAAANQAECgUIBQAAAA==.Termana:BAACNQAFFH8PAAIlAAYKASJWAgB+AQAlAAYKASJWAgB+AQA1AAQKfzwAAiUACgobJsEAANkDACUACgobJsEAANkDAAAA.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Thegame:BAAANQADCgQIBAAAAA==.Themage:BAAANQAECgMIAwAAAA==.Theodoró:BAABNQAECn8eAAMOAAkKiBp/MgAWAgAOAAkKiBp/MgAWAgAWAAIKRQMhfgBMAAAAAA==.Thereza:BAAANQAECgUICwAAAA==.Therynn:BAAANQADCgUIBQAAAA==.Thiccpickle:BAAANQAECgIIBAABNQAECgcICwADAAAAAA==.Thrashzel:BAAANQADCggIDQAAAA==.Thug:BAAANQADCgcIFQAAAA==.Thundersylph:BAAANQADCgYIBgAAAA==.Thuneredor:BAAANQADCgMIAwAAAA==.',
Ti='Tiferet:BAABNQAECn8rAAMXAAoKIyAUKwC9AgAXAAoKIyAUKwC9AgAFAAIKIwjubgBLAAAAAA==.Tigiw:BAABNQAECn8ZAAIOAAYKAQ9BwgB+AQAOAAYKAQ9BwgB+AQAAAA==.Tinysunshine:BAABNQAECn8UAAMUAAcKBRiQKwC/AQAUAAcKBRiQKwC/AQAbAAMKgQppJwCOAAAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAABNQAECn8iAAIOAAcKWhn4kADnAQAOAAcKWhn4kADnAQAAAA==.Tomato:BAACNQAFFH8LAAQSAAYKywhgEACSAAASAAIKSgxgEACSAAALAAMKTAW7NACKAAARAAEKAACKDgAAAAA1AAQKfzQAAxIACgoLIHYGAKUCABIACAq9IHYGAKUCAAsACArlG/E1ANIBAAAA.Torfelori:BAAANQAECgQICAAAAA==.Torvalar:BAABNQAECn86AAIEAAoKBRFzYQCXAQAEAAoKBRFzYQCXAQAAAA==.Tove:BAABNQAECn8gAAIKAAoKCAlEggCfAQAKAAoKCAlEggCfAQAAAA==.',
Tr='Trûth:BAAANQAECggIEQAAAA==.',
Tu='Turdyl:BAABNQAECn8mAAIEAAoKzw4FogDdAQAEAAoKzw4FogDdAQAAAA==.Tuxxí:BAAANQADCgYIBgABNQAECgoKOQAYAKkfAA==.',
Tw='Twindadlock:BAAANQABCgIIAgABNQAECgQIEQADAAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyraz:BAAANQADCgUIBQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggIEQAAAA==.',
['Tá']='Tárris:BAABNQAECn8iAAILAAkKixxAQgCLAgALAAkKixxAQgCLAgABNQAECgoKOQAYAKkfAA==.',
['Tæ']='Tægia:BAAANQAECgUIBgAAAA==.',
['Tô']='Tôx:BAABNQAECn8bAAMKAAgK9h0pQgBtAgAKAAgK9h0pQgBtAgAJAAMKOAl27gCOAAAAAA==.',
Um='Umbranwings:BAABNQAECn8cAAQjAAgKCwg2JAAgAQAjAAgKCwg2JAAgAQAiAAYKAgOnNwDXAAAfAAEKAABZJwAmAAAAAA==.',
Un='Unheardjp:BAAANQAECgIIAwAAAA==.',
Ur='Ursus:BAABNQAECn8hAAIdAAkKPgnzUgCPAQAdAAkKPgnzUgCPAQAAAA==.',
Us='Usdaprime:BAAANQAECgIIAgAAAA==.',
Va='Vaerix:BAAANQAECgYIDQAAAA==.Valydrin:BAABNQAECn8zAAMXAAoKyBVzIwBMAgAXAAoKyBVzIwBMAgAFAAMKjwXUYgB1AAAAAA==.',
Ve='Veera:BAAANQADCgQIBAAAAA==.Vexadrine:BAACNQAFFH8RAAIbAAcKLRPiAwBxAQAbAAcKLRPiAwBxAQA1AAQKfz0AAhsACgrmINIBANACABsACgrmINIBANACAAAA.Vexiana:BAAANQAECgQIBwABNQAFFAcIEQAbAC0TAA==.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vu='Vuldrak:BAAANQAECggIEAAAAA==.',
Vy='Vysis:BAACNQAFFH8OAAIFAAYKYhCzCACBAQAFAAYKYhCzCACBAQA1AAQKfzgABAUACgpkHcwPAPgCAAUACgpkHcwPAPgCABcABwoOISdeAAcCAAYABQrUGuoKAJUBAAAA.',
['Ví']='Ví:BAAANQAECgEIAQAAAA==.',
Wa='Warstorm:BAAANQAECgQIBAAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAABNQAECn8pAAQbAAkKRBjtBwBvAQAbAAkKRBjtBwBvAQAUAAUKFxBKQgAFAQAVAAQKWQgkOwCZAAAAAA==.Widgit:BAAANQADCgcIFAAAAA==.Wieldblade:BAABNQAECn88AAMEAAoKOxSEUwC7AQAEAAoKOxSEUwC7AQAeAAYKiRUglABjAQAAAA==.',
Wo='Woolverine:BAABNQAECn8cAAMhAAYKqBAgJgAsAQAhAAYKqBAgJgAsAQAdAAQKyBbTawAcAQAAAA==.',
Wu='Wunderbar:BAABNQAECn8nAAIKAAkKYBe0JQDVAQAKAAkKYBe0JQDVAQAAAA==.',
Wy='Wyldfire:BAACNQAFFH8YAAIdAAUKzxvACwC1AQAdAAUKzxvACwC1AQA1AAQKfzgAAh0ACgqXIfEIAIcDAB0ACgqXIfEIAIcDAAAA.',
Xa='Xanith:BAABNQAECn8dAAIMAAoKCQxJWAB5AQAMAAoKCQxJWAB5AQAAAA==.Xanyth:BAAANQADCggICAAAAA==.',
Xe='Xenoviaquart:BAAANQAECgUIAwAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Ya='Yardly:BAAANQADCggIEwAAAA==.',
Yi='Yia:BAAANQAECgUIEgABNQAECgYIFQALADAcAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECn8mAAMUAAoKgSKMBgBnAwAUAAoKgSKMBgBnAwAVAAcK9xOUDQCwAQAAAA==.',
Za='Zalerodora:BAAANQAECgQIBAABNQAECgcIHAABAGMRAA==.Zarich:BAABNQAECn8kAAIRAAoKvxc5BACfAgARAAoKvxc5BACfAgAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.Zepheria:BAAANQAECgEIAQABNQAECggIEwADAAAAAQ==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECggIJAAJAHkgAA==.Zogah:BAEANQAECgQIBAABNQAECggIJAAJAHkgAA==.Zoganian:BAEANQAECgQIDgABNQAECggIJAAJAHkgAA==.Zoghog:BAAANQAECgYIDAAAAA==.Zogula:BAEANQAECgQIBAABNQAECggIJAAJAHkgAA==.',
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
