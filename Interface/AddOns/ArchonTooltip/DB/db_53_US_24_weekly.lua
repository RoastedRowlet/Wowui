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

local lookup = {'DemonHunter-Havoc','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Warlock-Destruction','Unknown-Unknown','Mage-Frost','Mage-Arcane','Warlock-Affliction','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Priest-Holy','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Outlaw','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Paladin-Holy','Evoker-Augmentation','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','Rogue-Assassination','DemonHunter-Vengeance','Hunter-Survival',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Actualape:BAAANQAECgQIBgAAAA==.',
Ad='Addy:BAABNQAECn83AAIBAAoKChrGGAAXAgABAAoKChrGGAAXAgAAAA==.Adelethe:BAAANQADCgYIBgAAAA==.Aditu:BAAANQADCgMIAwAAAA==.',
Ae='Aestian:BAABNQAECn8fAAICAAcKwAYkNAC1AAACAAcKwAYkNAC1AAAAAA==.',
Ah='Ahhotep:BAAANQADCgEIAQAAAA==.',
Ai='Ailysely:BAAANQAECgUICQAAAA==.Aispere:BAAANQAECgIIBAABNQAECgYIFAADAAEDAA==.',
Al='Alerzhulan:BAAANQAECgUIEAAAAA==.Aletheia:BAAANQADCggICAAAAA==.Alfurn:BAAANQADCgIIAgAAAA==.Aliveknightt:BAAANQADCggICAAAAA==.Alledria:BAABNQAECn8nAAIEAAkKxQ5EpgDUAQAEAAkKxQ5EpgDUAQAAAA==.Alorely:BAABNQAECn8fAAMFAAgKfQ79MgCLAQAFAAgKfQ79MgCLAQAGAAMKWxBVDACbAAAAAA==.',
Am='Amanara:BAABNQAECn8iAAMHAAYKPwipYADXAAAIAAUKyggVkADoAAAHAAYK1QWpYADXAAAAAA==.Amoonia:BAAANQADCgcIFwAAAA==.',
An='Anciientpaw:BAABNQAECn8eAAMJAAgKux8bLwClAgAJAAgKux8bLwClAgAKAAMKIg3B9QCpAAAAAA==.Andrasomnius:BAAANQAECgQIBAAAAA==.Angbar:BAAANQAECgcIDwAAAA==.Anguirus:BAABNQAECn8sAAMKAAoKowRLqgA/AQAKAAoKowRLqgA/AQALAAQK+wLjJwCAAAAAAA==.Anitax:BAABNQAECn8fAAIMAAkKqxrLHACAAgAMAAkKqxrLHACAAgABNQAECgoKKgAKAGIfAA==.Anuksunàmun:BAAANQADCgYIDAAAAA==.',
Ao='Aoman:BAAANQAECgYIBQAAAA==.',
Aq='Aqulenas:BAAANQAECgEIAQAAAA==.',
Ar='Arakhan:BAAANQADCggIFAAAAA==.Arcadian:BAABNQAECn9MAAMNAAoKpRJORQABAgANAAoKfRJORQABAgAOAAIKBRGdJQCCAAAAAA==.Arceeprime:BAAANQAECgMIAgAAAA==.Arextheelder:BAABNQAECn8WAAIPAAcKbAuXKwAhAQAPAAcKbAuXKwAhAQAAAA==.Argentum:BAAANQADCggICAABNQAECgoKNwABAAoaAA==.Arisemysummo:BAAANQAECgcIBAAAAA==.Armorscales:BAABNQAECn8dAAIMAAkKfSD4MwC5AgAMAAkKfSD4MwC5AgAAAA==.Arntraz:BAAANQAECgUICQAAAA==.Arrabbiato:BAABNQAECn8eAAIDAAgKJQs1sQCiAQADAAgKJQs1sQCiAQAAAA==.Arrikat:BAAANQADCgEIAQAAAA==.Arronaxx:BAAANQADCgYIEAAAAA==.Arçadia:BAAANQAECgIIAgAAAA==.',
As='Ashherdonn:BAAANQAECgQIAwAAAA==.Ashnikko:BAAANQAECgEIAQAAAA==.Ashtori:BAAANQABCgQIBgAAAA==.Asprika:BAABNQAECn8hAAIFAAoKlAyEHwBRAQAFAAoKlAyEHwBRAQAAAA==.Astayoni:BAAANQAECgYICgAAAA==.Asterfleur:BAAANQAECgQICwABNQAECggICQAQAAAAAA==.Astrine:BAABNQAECn8gAAMRAAkKKxUHHAAQAQASAAkKOxPsowA5AgARAAYKng8HHAAQAQAAAA==.',
At='Ataraxya:BAABNQAECn8aAAQTAAkK/xDiGQC3AAAMAAYK3g5+kwD8AAATAAMKaw/iGQC3AAAPAAIKTRDXHgBlAAAAAA==.',
Au='Auberon:BAABNQAECn87AAIUAAoKmCEZAwDwAgAUAAoKmCEZAwDwAgAAAA==.Aufta:BAABNQAECn8iAAMVAAgKcgeaQwD8AAAVAAcKcgeaQwD8AAAWAAYKNgXdMgDTAAAAAA==.Aumer:BAAANQAECgEIAQAAAA==.Aura:BAAANQADCgcIBwAAAA==.',
Az='Azi:BAACNQAFFH8NAAIXAAUKjRSfCwCEAQAXAAUKjRSfCwCEAQA1AAQKf0IAAhcACgqBI8YCACcDABcACgqBI8YCACcDAAAA.Azurite:BAAANQADCgYIFQAAAA==.',
Ba='Backpedal:BAAANQAECgUIBQAAAA==.Badankhadonk:BAACNQAFFH8UAAMJAAYKzhwsCQC9AQAJAAYKzhwsCQC9AQAKAAEK1g6JMABJAAA1AAQKf0IAAwkACgpqIocFAJsDAAkACgpqIocFAJsDAAoABAoXHVmqAD8BAAAA.Bakkutteh:BAAANQABCgIIBAAAAA==.Bakuhiko:BAABNQAECn8YAAMMAAkK5gNWlwDzAAAMAAkK5gNWlwDzAAAPAAMKJQG7bABGAAAAAA==.Balen:BAABNQAECn8cAAMEAAkKqAyFmQBZAQAEAAkK9guFmQBZAQACAAIKqQxGZQBMAAAAAA==.Bandersin:BAAANQADCgUIBQAAAA==.Bansheex:BAAANQADCgQIBAAAAA==.Bariden:BAAANQADCgQIBAAAAA==.',
Be='Beefmuffinz:BAACNQAFFH8LAAMIAAcK4Q/KCACLAQAIAAUKNBPKCACLAQAHAAIKlwJdGQBJAAA1AAQKfzoAAwcACQoXJGALAOQCAAgACQoAIgMZAPcCAAcACQqaIGALAOQCAAAA.Beethozart:BAAANQADCggIGQAAAA==.Belcebu:BAAANQABCggIDgAAAA==.Belholy:BAABNQAECn8mAAIYAAgK/R68LABeAgAYAAgK/R68LABeAgAAAA==.Beliice:BAAANQADCgIIAgABNQAECggIJgAYAP0eAA==.Bellafleur:BAAANQAECgQIEgABNQAECggICQAQAAAAAA==.Bellawesome:BAAANQAECgMIAwAAAA==.Bendeekay:BAACNQAFFH8aAAIZAAYK2yLyBQB+AQAZAAYK2yLyBQB+AQA1AAQKfzoAAxkACgpAIyMJAHADABkACgpAIyMJAHADAAgAAgq4EsFaAHoAAAAA.Benilok:BAABNQAECn8WAAIMAAYKjRhikQC7AQAMAAYKjRhikQC7AQAAAA==.Bethgibbons:BAAANQADCgUJCAAAAA==.',
Bf='Bfh:BAAANQAECggIEAAAAA==.',
Bg='Bgpocalypse:BAAANQADCgYIBgAAAA==.',
Bi='Bigsuccubus:BAAANQAECgEIAQAAAA==.',
Bl='Blackblood:BAABNQAECn8nAAIBAAgKwAu/SACEAQABAAgKwAu/SACEAQAAAA==.Bladestriker:BAAANQAECgMIAwAAAA==.Bloodache:BAABNQAECn8eAAIaAAkKFiEXEADxAgAaAAkKFiEXEADxAgAAAA==.Bluesaphire:BAAANQADCgMIBAABNQAECgkJIwAJAIwcAA==.Blux:BAAANQAECgQIBgAAAA==.',
Bo='Boil:BAABNQAECn8xAAIbAAkKrQZHBQAGAQAbAAkKrQZHBQAGAQAAAA==.Bonemarrow:BAABNQAECn8VAAMEAAUKUAfOIQGCAAAEAAUKUAfOIQGCAAACAAEKAAAoaQBBAAAAAA==.Bordin:BAAANQADCgYIDAAAAA==.Bows:BAAANQAECggICAAAAA==.',
Br='Brakeable:BAAANQAECgYICQAAAA==.Braké:BAABNQAECn8ZAAICAAgKFCDkFABbAgACAAgKFCDkFABbAgAAAA==.Brewskies:BAABNQAECn8/AAIcAAoKCiRPAQApAwAcAAoKCiRPAQApAwAAAA==.Brightstar:BAAANQADCgUIBQAAAA==.Brioche:BAAANQADCgUIBgAAAA==.Brionthicc:BAAANQAECgUICAABNQAFFAcIEQAPAEQRAA==.Brownington:BAABNQAECn8pAAQdAAkK3SP9CgBaAgAdAAgKhCP9CgBaAgAeAAYKwB84PgAHAgAUAAIK0yFFKwC3AAAAAA==.Bruhilda:BAAANQAECgUIDQAAAA==.Brìonik:BAACNQAFFH8RAAQPAAcKRBHeCQCnAAAMAAQK1Au2JADbAAAPAAIKbRneCQCnAAATAAEKAAC3FAAAAAA1AAQKf0oABA8ACgrbIDUHAJQCAA8ACArsGzUHAJQCAAwACAp8Hh4/AOYBABMABgrzGiMJAHcBAAAA.',
Bu='Bubbleroundi:BAABNQAECn9KAAIfAAoKNhLaNwAHAgAfAAoKNhLaNwAHAgAAAA==.Bubudder:BAABNQAECn9HAAMIAAoKZyRrDABXAwAIAAkKYiJrDABXAwAHAAoK/CD3CQD2AgAAAA==.Buffstuff:BAABNQAECn8wAAIgAAoKIQ6gCgDEAQAgAAoKIQ6gCgDEAQAAAA==.Burgerlock:BAAANQAECgEIAQAAAA==.',
Ca='Caeviro:BAABNQAECn8jAAIFAAoKTQiIHgBaAQAFAAoKTQiIHgBaAQAAAA==.Canadaishere:BAAANQADCgMIAwAAAA==.Canadaispimp:BAAANQADCgEIAQAAAA==.Cantheartitz:BAAANQAECgYIDwAAAA==.Catdav:BAABNQAECn8pAAILAAgK5B2yEADMAQALAAgK5B2yEADMAQAAAA==.',
Ch='Charbol:BAAANQADCgQICAABNQADCggIEQAQAAAAAA==.Chelraani:BAABNQAECn8vAAIEAAkKgRhSXgDdAQAEAAkKgRhSXgDdAQAAAA==.Chess:BAABNQAECn8WAAIKAAkKsxcgbADcAQAKAAkKsxcgbADcAQAAAA==.Chiichard:BAAANQADCgYICAAAAA==.Chunkamonk:BAAANQADCgQIBgAAAA==.',
Ci='Ciarianna:BAAANQADCgcIBwABNQAECgoKNwABAAoaAA==.Cigar:BAAANQADCgUICQABNQAECgYIEAAQAAAAAA==.',
Cl='Clazzicola:BAACNQAFFH8KAAIVAAUKgBm/CQAyAQAVAAUKgBm/CQAyAQA1AAQKfygAAhUACgr0If0VAKECABUACgr0If0VAKECAAAA.',
Co='Combatwombat:BAAANQABCgEIAQAAAA==.Conjredcukee:BAAANQAECgQICwAAAA==.Coogsayer:BAAANQADCgIIAgAAAA==.Cowdeer:BAAANQAECgQIBgAAAA==.Cowgoboom:BAAANQADCgUICQAAAA==.',
Cp='Cptncrush:BAABNQAECn8hAAMJAAcKKxwAVwANAgAJAAcKKxwAVwANAgAKAAMKexMGnQCaAAAAAA==.',
Cr='Creamsickle:BAAANQABCgIIBAAAAA==.Creature:BAAANQAECgQIBgAAAA==.',
Cu='Cupcakes:BAAANQADCgcIEwAAAA==.Cutethulu:BAABNQAECn8jAAIFAAkKaBQ2IAA4AgAFAAkKaBQ2IAA4AgAAAA==.',
Cy='Cydarr:BAAANQADCgQIBAAAAA==.Cyther:BAACNQAFFH8RAAIOAAcKRBiVAADPAQAOAAcKRBiVAADPAQA1AAQKf0oAAg4ACgpbJkIAAIEDAA4ACgpbJkIAAIEDAAAA.',
Da='Dadbodftw:BAAANQAECgQIEQAAAA==.Daddylight:BAABNQAECn8sAAIEAAoKeA4EiAB8AQAEAAoKeA4EiAB8AQAAAA==.Daelyn:BAAANQADCgYIAgAAAA==.Dakk:BAAANQADCggICAAAAA==.Damaclese:BAAANQABCgUIBQAAAA==.Darkdottie:BAAANQAECggIDwAAAA==.Darkenstormy:BAAANQAECgEIAQAAAA==.Darkmage:BAAANQADCgQIAwAAAA==.Dayday:BAAANQAECggICAAAAA==.',
De='Deadlight:BAABNQAECn8uAAIHAAkKVxBaOAD0AQAHAAkKVxBaOAD0AQAAAA==.Deadtofall:BAAANQADCggIHAAAAA==.Deathshikzs:BAABNQAECn8nAAMZAAkKDxzLKgBwAgAZAAkKDxzLKgBwAgAIAAEK1QdBgwApAAABNQAECgoKKgAKAGIfAA==.Decix:BAAANQAFFAEIAQABNQAFFAQIDAAFAH8VAA==.Deet:BAAANQADCgMJAwAAAA==.Deity:BAABNQAECn8iAAMOAAoK6h8yAwAsAwAOAAoK6h8yAwAsAwANAAIK8BIzLQF6AAABNQAECgoKNgAVAF4cAA==.Demonllxll:BAAANQAECgYIDgAAAA==.Demontime:BAAANQADCgcIDAABNQAECgQIBAAQAAAAAA==.Desolation:BAABNQAECn87AAISAAoKgiMaIQCgAgASAAoKgiMaIQCgAgAAAA==.Despia:BAABNQAECn8vAAMYAAkKvCJeEwASAwAYAAkKvCJeEwASAwAFAAQK8wwzUQDMAAAAAA==.Devastacia:BAAANQADCggICAAAAA==.',
Di='Dicot:BAABNQAECn8vAAMhAAkK+hIyHwC0AQAhAAkK+hIyHwC0AQAeAAYKWwOfhAC/AAAAAA==.Diety:BAABNQAECn82AAIVAAoKXhxbDQBaAgAVAAoKXhxbDQBaAgAAAA==.Dimension:BAAANQAECgIIAQAAAA==.Disconnect:BAAANQABCgYICwAAAA==.',
Dj='Djpallyd:BAABNQAECn8wAAIEAAoKFxrPSwASAgAEAAoKFxrPSwASAgAAAA==.',
Do='Dornoll:BAAANQADCgQIBAAAAA==.Dotmami:BAAANQAECgcICwABNQAECggICwAQAAAAAA==.Doughy:BAAANQAECgUIBAAAAA==.',
Dr='Dragonu:BAABNQAECn9UAAMiAAoKnSLdAQCqAwAiAAoKnSLdAQCqAwAjAAEKAACGPAA1AAABNQAFFAUIDwAMAA8SAA==.Draktyr:BAACNQAFFH8LAAINAAYKRBFKGwA5AQANAAYKRBFKGwA5AQA1AAQKfzUAAw0ACgqeIvgXAFkDAA0ACgqeIvgXAFkDAA4AAQoAABQ2AC4AAAAA.Drlovely:BAAANQADCgQIBAAAAA==.Droody:BAAANQABCgIIAgAAAA==.',
El='Elianda:BAAANQADCggIDgABNQAECgkJJwABAHwNAA==.Ellalais:BAAANQAECgQICgAAAA==.Ellismom:BAABNQAECn8+AAIIAAoKBBudFgALAgAIAAoKBBudFgALAgAAAA==.',
En='Enamorada:BAAANQAECgQICQABNQAECgkJIwAJAIwcAA==.Enchanceurpp:BAAANQADCggIGQAAAA==.End:BAAANQAECgUICAAAAA==.',
Eo='Eolyndin:BAAANQADCgQIBAAAAA==.Eolyndyn:BAAANQADCgYICQAAAA==.',
Ep='Epialos:BAAANQAECggICAAAAA==.',
Er='Ereithelda:BAACNQAFFH8OAAIWAAUK7hZZBACWAQAWAAUK7hZZBACWAQA1AAQKf00AAhYACgqRJJwDAHYDABYACgqRJJwDAHYDAAAA.Ericka:BAAANQADCgYIBwAAAA==.Erina:BAAANQABCggIDwAAAA==.Erowid:BAAANQADCggICwABNQAFFAUIDwAMAA8SAA==.Errutu:BAABNQAECn8/AAIkAAoKMxG+GgABAgAkAAoKMxG+GgABAgAAAA==.',
Ev='Evox:BAABNQAECn8fAAMKAAYKShXiawAKAQAKAAYKShXiawAKAQALAAUKzgWlIQDPAAAAAA==.',
Ex='Exodiadruid:BAAANQAECgMIAwAAAA==.',
Fa='Falgar:BAAANQAECgQIBAAAAA==.Fann:BAABNQAECn8jAAIhAAgKzgZ5QgAWAQAhAAgKzgZ5QgAWAQAAAA==.Fargrim:BAAANQADCggIEQAAAA==.Fauna:BAAANQADCggICAAAAA==.Faytl:BAAANQAECgUIBQAAAA==.',
Fe='Feathiir:BAAANQADCgIIAgAAAA==.Feefifofum:BAAANQADCgUIBQAAAA==.Fewz:BAACNQAFFH8dAAMRAAYKzh13AAD8AQARAAYKzh13AAD8AQASAAEKAABDZAA/AAA1AAQKf0EAAxEACgoFJmsAANMDABEACgoFJmsAANMDABIAAgorDU4+AT0AAAAA.',
Fl='Flakflap:BAAANQAECgUIBQABNQAFFAIIBQAZADsPAA==.Flakov:BAAANQADCggIDgABNQAFFAIIBQAZADsPAA==.Flaktop:BAACNQAFFH8FAAIZAAIKOw/LIwBvAAAZAAIKOw/LIwBvAAA1AAQKfy8AAhkACQqGHikgALICABkACQqGHikgALICAAAA.Flatplate:BAAANQADCgUIBQAAAA==.Fler:BAAANQAECgUIBQAAAA==.Fluffie:BAAANQABCgcICgAAAA==.',
Fo='Forbacon:BAABNQAECn82AAMZAAoKCRmjGgAAAgAZAAoKCRmjGgAAAgAHAAQKvAlWhwCUAAAAAA==.Force:BAABNQAECn8dAAMHAAgKYgW0ZgAGAQAHAAgKYgW0ZgAGAQAIAAEKRwMr9QAiAAAAAA==.Fourdragon:BAAANQAECgQIAgABNQAECgcIDQAQAAAAAA==.Fouris:BAAANQAECgcIDQAAAA==.',
Fr='Fridgie:BAACNQAFFH8RAAIDAAcK+hDDCgChAQADAAcK+hDDCgChAQA1AAQKfz8AAgMACgolJBoOAAUDAAMACgolJBoOAAUDAAAA.Friggenmage:BAAANQAECgYICgAAAA==.Frostbitte:BAAANQADCgEIAQAAAA==.Frozenturtle:BAABNQAECn8dAAIZAAcKwhw9QQD5AQAZAAcKwhw9QQD5AQAAAA==.',
Ft='Ftwiamtank:BAABNQAECn8vAAIlAAoKKxTYCQD4AQAlAAoKKxTYCQD4AQAAAA==.',
Fu='Fuerte:BAAANQABCgQIAwAAAA==.',
Ga='Garcutt:BAACNQAFFH8MAAISAAcKQwnUIACBAQASAAcKQwnUIACBAQA1AAQKf0QAAhIACgozICITAOoCABIACgozICITAOoCAAAA.',
Ge='Geddan:BAAANQAECgQICAAAAA==.Genericck:BAACNQAFFH8KAAMeAAMKdxZ/DQDlAAAeAAMKKxR/DQDlAAAdAAIKPxehBQCGAAA1AAQKfx8AAx4ACQqdIPYMALQCAB4ACQrqHfYMALQCAB0ACApoHpwOAHoCAAAA.Genericdh:BAAANQAFFAEIAQAAAA==.Generickdk:BAAANQAECgQIBAAAAA==.Genericpal:BAABNQAECn8qAAMCAAkKFSEgCgD5AgACAAgKQSQgCgD5AgAEAAMKUQ/yRgGvAAAAAA==.Geritol:BAAANQADCggICAAAAA==.',
Gi='Gichio:BAAANQAECgUIBQAAAA==.Ginrai:BAAANQADCgUIBQAAAA==.',
Gl='Gladstone:BAAANQAECgMIBQAAAA==.Glasscanon:BAAANQAECgMIAwAAAA==.',
Gn='Gnawbear:BAABNQAECn9aAAMmAAoKEyMjAgAtAwAmAAoKEyMjAgAtAwAkAAgKhxsfLwAGAgAAAA==.',
Go='Goatassassin:BAABNQAECn8vAAMkAAkKGxn/FQAyAgAkAAkKGxn/FQAyAgAmAAIKawr+kABuAAAAAA==.Goatshifter:BAAANQAECgMIBAABNQAECgkJLwAkABsZAA==.Gobogoolina:BAAANQADCgYIDgAAAA==.',
Gr='Grayeyes:BAAANQADCgMIAwAAAA==.Greenngoblin:BAAANQAECgQIBQAAAA==.Grämps:BAAANQADCgYIBgAAAA==.',
Gu='Guino:BAAANQAECgQIDgAAAA==.',
Gw='Gwenelly:BAAANQADCgYICQAAAA==.',
Ha='Haikuu:BAAANQADCgcIBwAAAA==.Hail:BAAANQAECgQIBAAAAA==.Hamnqueso:BAAANQADCgYIDgABNQAECgQIEQAQAAAAAA==.Hardeesdelux:BAAANQAECgQICwABNQAECgYICgAQAAAAAA==.Hazis:BAACNQAFFH8GAAIZAAQK5hGVFQAGAQAZAAQK5hGVFQAGAQA1AAQKfzQAAhkACgo4HO8VAP0CABkACgo4HO8VAP0CAAAA.',
Hi='Hinala:BAABNQAECn8vAAIZAAkKmwvGVQCdAQAZAAkKmwvGVQCdAQAAAA==.',
Ho='Holy:BAAANQAFFAEIAQABNQAFFAYIDQAKAGcKAA==.Holydad:BAAANQADCgcIBwAAAA==.Honeybloom:BAAANQAECgEIAQAAAA==.Honeybutter:BAACNQAFFH8FAAINAAMK4SMzJADdAAANAAMK4SMzJADdAAA1AAQKf0YAAw0ACgoxJswCAOYDAA0ACgoxJswCAOYDAA4AAQoAAJcxADoAAAAA.Hordebreaker:BAAANQABCgIIAgAAAA==.',
Hu='Huesitos:BAABNQAECn8VAAISAAgK7RCcFAFqAQASAAgK7RCcFAFqAQAAAA==.Huntzilla:BAAANQADCgYICwAAAA==.Huukend:BAABNQAECn8/AAIDAAoKhCI8JAAGAwADAAoKhCI8JAAGAwAAAA==.',
In='Inanitas:BAAANQAECgQIBAAAAA==.Innominot:BAAANQAECgQICQAAAA==.',
Ir='Irukox:BAAANQAECgUIBgAAAA==.',
Ja='Jackoldean:BAAANQADCgUICwAAAA==.Jacques:BAAANQADCggICAAAAA==.Jadaveon:BAAANQAECgUIBQAAAA==.Jadefleur:BAAANQAECgYIBQABNQAECggICQAQAAAAAA==.Jalene:BAABNQAECn8aAAIEAAcKEhFIuQAgAQAEAAcKEhFIuQAgAQAAAA==.Jargen:BAAANQADCgYIBwABNQADCggIEQAQAAAAAA==.',
Je='Jemma:BAAANQAECgUIBQAAAA==.Jettabae:BAAANQAECgIIBAABNQAFFAcIEQAEAGEKAA==.Jettadari:BAAANQAECgYICgABNQAFFAcIEQAEAGEKAA==.Jettadin:BAACNQAFFH8RAAIEAAcKYQoFDgBrAQAEAAcKYQoFDgBrAQA1AAQKf0AAAgQACgoUI2ETAAIDAAQACgoUI2ETAAIDAAAA.Jettagos:BAAANQAECgQIBgABNQAFFAcIEQAEAGEKAA==.',
Jt='Jt:BAABNQAECn8dAAIEAAoKUBgNXQDhAQAEAAoKUBgNXQDhAQAAAA==.',
Jw='Jwalker:BAAANQADCgQIBQAAAA==.',
['Jë']='Jëks:BAACNQAFFH8RAAIJAAcKXRVMCgCpAQAJAAcKXRVMCgCpAQA1AAQKf0MAAwkACgrYH5wYABADAAkACgrYH5wYABADAAsACAozHjkLADMCAAAA.',
Ka='Kaelvryn:BAAANQABCgIIAgAAAA==.Kaitllyn:BAAANQADCgYIBgAAAA==.Kakozaps:BAACNQAFFH8KAAMLAAUKnxhfAgCyAQALAAUKnxhfAgCyAQAKAAEKmAzFMQBGAAA1AAQKf10AAwsACgrQJZ0BAEQDAAsACgrQJZ0BAEQDAAoACAo7IJg4AJQCAAAA.Kaldor:BAAANQADCgUICAAAAA==.Kalid:BAAANQAECgIIAgAAAA==.Kallar:BAABNQAECn8WAAIYAAoKxg8mbgDTAQAYAAoKxg8mbgDTAQAAAA==.Kathrynne:BAAANQAECggIDwAAAA==.Kayeera:BAABNQAECn8fAAIYAAoKTQlgUAC/AQAYAAoKTQlgUAC/AQAAAA==.Kaylrandi:BAAANQAECgMIBAAAAA==.Kayna:BAAANQAECgUIBwAAAA==.',
Ke='Kearza:BAAANQAECgUIEQAAAA==.Keiyona:BAAANQADCgIIAgABNQAECgoKLAAEAJ4XAA==.Keladas:BAAANQAECggIAgAAAA==.Kennethv:BAABNQAECn8iAAIYAAYK6RpAVgCoAQAYAAYK6RpAVgCoAQAAAA==.Keny:BAAANQAECgUJBgABNQAECgcIEgAQAAAAAA==.Kero:BAAANQADCgcICgABNQAECgoKFgAYAMYPAA==.Kethie:BAAANQADCggIEwAAAA==.Kev:BAAANQAECggIBAAAAA==.Keyalerong:BAAANQABCgQIBAAAAA==.',
Kh='Khalesie:BAAANQADCgIIBAAAAA==.Khibanee:BAAANQAECgQIDQAAAA==.Khiell:BAABNQAECn8sAAMOAAkK4RlZCQBDAgAOAAgKwxtZCQBDAgANAAIKxw/UNgFmAAAAAA==.Khrominius:BAABNQAECn8bAAISAAgKuxGJ4wDCAQASAAgKuxGJ4wDCAQAAAA==.',
Ki='Killthirsty:BAAANQADCgcIBwABNQAECgUIBQAQAAAAAA==.Kinigit:BAAANQAECgcIEgABNQAFFAYIHQAeAJoWAA==.Kirïtö:BAAANQAECgYIBgAAAA==.Kitaradin:BAAANQAECgUIDgAAAA==.',
Kn='Knghtmre:BAACNQAFFH8NAAISAAQKQw2uIgDPAAASAAQKQw2uIgDPAAA1AAQKfzUAAhIACgqTHDctAGwCABIACgqTHDctAGwCAAAA.',
Ko='Komamura:BAAANQAECgMIAwAAAA==.Konpalitaa:BAAANQAECgYICgAAAA==.',
Kr='Kragon:BAAANQAECgIIAgAAAA==.Krátos:BAABNQAECn8vAAINAAoKNxyGOQAwAgANAAoKNxyGOQAwAgAAAA==.',
Ku='Kungphu:BAAANQADCgcIDwAAAA==.Kuranaa:BAABNQAECn8UAAIDAAYKAQMJ7QCXAAADAAYKAQMJ7QCXAAAAAA==.Kurulak:BAABNQAECn82AAIaAAoKhwwwHQCGAQAaAAoKhwwwHQCGAQAAAA==.',
Ky='Kymru:BAAANQADCgYICQAAAA==.Kynn:BAAANQADCggIDwAAAA==.',
La='Lacerveza:BAAANQAECgMIBQAAAA==.Lahyanhou:BAAANQAECgEIAQAAAA==.Lawanorder:BAAANQADCggIBwAAAA==.Laylah:BAAANQAECgEIAQAAAA==.',
Le='Leriope:BAABNQAECn8/AAIMAAoKtA+bUwCgAQAMAAoKtA+bUwCgAQAAAA==.',
Li='Lichfiend:BAAANQADCgYICgAAAA==.Lihpfu:BAAANQAECgUIDQABNQAECgoKMwANAE0eAA==.Lilem:BAAANQADCgcICwAAAA==.Limboh:BAAANQADCgcIBwAAAA==.',
Lj='Lj:BAABNQAECn8yAAIfAAoKEx6cJABxAgAfAAoKEx6cJABxAgAAAA==.',
Lo='Lorethy:BAAANQADCgQIBAAAAA==.Lothozbq:BAAANQAECgIIAQAAAA==.Lovecrafft:BAAANQAECgQIAwAAAA==.',
Lu='Luxure:BAAANQAECgEIAQAAAA==.',
Ma='Maegan:BAAANQADCgcILAAAAA==.Mager:BAAANQAECgUIBgAAAA==.Mageshyte:BAACNQAFFH8IAAISAAUK8QzlIgBwAQASAAUK8QzlIgBwAQA1AAQKf0kAAhIACgq/IFQeAK4CABIACgq/IFQeAK4CAAAA.Magolock:BAABNQAECn8VAAIMAAYKMBzzkwC0AQAMAAYKMBzzkwC0AQAAAA==.Magus:BAAANQAECgUIBQAAAA==.Maidrim:BAACNQAFFH8LAAImAAcKxxIvBwCmAQAmAAcKxxIvBwCmAQA1AAQKf0UAAiYACgqXI0ICACcDACYACgqXI0ICACcDAAAA.Mamajumbo:BAABNQAECn8dAAIDAAgKbxZIiwD0AQADAAgKbxZIiwD0AQAAAA==.Mana:BAACNQAFFH8NAAIKAAYKZwpbCgAHAQAKAAYKZwpbCgAHAQA1AAQKfz4AAgoACgpdHjcrANMCAAoACgpdHjcrANMCAAAA.Marellias:BAABNQAECn8qAAMDAAkKIiRTBgBIAwADAAkKIiRTBgBIAwAXAAEK7wb5kQAuAAABNQAECgoKMQAEAHgmAA==.Marikel:BAAANQAECgUIDAAAAA==.Marlea:BAABNQAECn8qAAMNAAkKChQugAAaAgANAAkKChQugAAaAgAOAAEKAAAaKwBaAAAAAA==.Maruka:BAABNQAECn9IAAIMAAoKGiELEABSAwAMAAoKGiELEABSAwAAAA==.Matthiias:BAAANQAECgMIBQAAAA==.Mawenzi:BAAANQADCggICAABNQAECgoKOQAYAD0PAA==.',
Me='Meletha:BAAANQADCggICAAAAA==.Meronpan:BAAANQAECggIDAAAAA==.',
Mi='Michaelken:BAABNQAECn8eAAIfAAgKUBTlbwDIAQAfAAgKUBTlbwDIAQAAAA==.Midari:BAAANQADCgEIAQAAAA==.Mierin:BAAANQADCgUIBQAAAA==.Mierín:BAAANQAECgIIAgAAAA==.Migrains:BAABNQAECn8+AAICAAoKCh/nCACGAgACAAoKCh/nCACGAgAAAA==.Mileyvyrus:BAAANQAFFAEIAQABNQAFFAYIDwAlAAEiAA==.Milkmesloppy:BAAANQADCgYIBgABNQAECgkJHQAMAH0gAA==.Miskaabin:BAABNQAECn8hAAMCAAgKFxPQJwCfAQACAAgKFxPQJwCfAQAEAAUKLAeOJwHeAAAAAA==.Missdemon:BAAANQADCggICAAAAA==.Missusgrey:BAAANQADCggICAABNQAECgkJNAAYAFUiAA==.',
Mo='Mogral:BAAANQADCgUICwAAAA==.Mojodaddy:BAAANQADCgYIAQAAAA==.Mojogreens:BAAANQADCgUICwAAAA==.Monsart:BAAANQAECgYIBwAAAA==.Montura:BAAANQADCgQIBAAAAA==.Moonblades:BAAANQADCgUIBQAAAA==.Moonie:BAAANQADCgYICwAAAA==.Moonpetals:BAAANQADCgQIBgAAAA==.Moralizdormi:BAABNQAECn85AAIgAAkKqgopDQB9AQAgAAkKqgopDQB9AQAAAA==.Moregana:BAAANQAECgIIAQAAAA==.Mortiis:BAABNQAECn8dAAILAAkK8AujDwDgAQALAAkK8AujDwDgAQAAAA==.',
Mp='Mpd:BAAANQAECgYIDgAAAA==.',
My='Mylendria:BAAANQABCgYIBwAAAA==.Mystique:BAABNQAECn8WAAInAAgKPQd8FADTAAAnAAgKPQd8FADTAAAAAA==.Mytmo:BAAANQAECgMIAwAAAA==.',
['Mí']='Míerín:BAACNQAFFH8VAAIDAAYK6xndBQBhAQADAAYK6xndBQBhAQA1AAQKf0AAAgMACgpiJZsFALUDAAMACgpiJZsFALUDAAAA.',
Na='Naama:BAAANQADCgcIJwAAAA==.Naelih:BAABNQAECn8aAAIXAAkKHgkrPABwAQAXAAkKHgkrPABwAQAAAA==.Natlès:BAAANQAECgYICAABNQAECggICwAQAAAAAA==.Natzu:BAAANQAECgMIBQAAAA==.Naushan:BAAANQADCgIIAgAAAA==.Nazari:BAACNQAFFH8HAAIEAAUKMQODFwDtAAAEAAUKMQODFwDtAAA1AAQKf0UAAgQACgqiGC5XAPEBAAQACgqiGC5XAPEBAAAA.',
Ne='Necronu:BAAANQADCggICAABNQAFFAUIDwAMAA8SAA==.',
Ni='Nikkolos:BAAANQAECgMIBAAAAA==.',
No='Nogusta:BAACNQAFFH8OAAINAAcKUgnVFgBuAQANAAcKUgnVFgBuAQA1AAQKf0oAAg0ACgrPIlgOABQDAA0ACgrPIlgOABQDAAAA.Notdecix:BAACNQAFFH8MAAMFAAQKfxVXDQADAQAFAAMKfxVXDQADAQAYAAIKcAEAMABiAAA1AAQKfzgAAwUACgqFIoQFAAIDAAUACgqFIoQFAAIDABgACApdFltYABkCAAAA.',
Nu='Nuggets:BAAANQAECgYIDwAAAA==.',
Od='Odell:BAAANQADCgIIAgABNQADCggIEQAQAAAAAA==.Odinsrain:BAAANQAECgUIBgABNQAFFAIIBQAfAAkYAA==.',
On='Onlyshams:BAAANQAECggIEgAAAA==.Onubolt:BAAANQADCgMIAwABNQAFFAUIDwAMAA8SAA==.Onulite:BAAANQAECggICQABNQAFFAUIDwAMAA8SAA==.Onulock:BAACNQAFFH8PAAMMAAUKDxKLEgDmAAAMAAUKDxKLEgDmAAATAAEKAACRFAAAAAA1AAQKfywABAwACgpJIVoZAJQCAAwACgo6IVoZAJQCAA8AAgq4H/YQALUAABMAAQoAAFIoAEoAAAAA.Onux:BAABNQAECn8UAAMaAAoKxxJYEwD7AQAaAAoKxxJYEwD7AQAnAAEKAAArMwAAAAABNQAFFAUIDwAMAA8SAA==.',
Oo='Oorggtejedor:BAAANQADCgUIBQAAAA==.',
Or='Orondo:BAABNQAECn8hAAIEAAcKgxVHjwBtAQAEAAcKgxVHjwBtAQAAAA==.',
Os='Ospfiend:BAAANQADCgYIBgAAAA==.',
Ou='Oumura:BAAANQAECgQIBAAAAA==.',
Pa='Palinia:BAAANQAECggIDQAAAA==.Pallyoop:BAABNQAECn8nAAMfAAkKAhSROgD6AQAfAAkKAhSROgD6AQAEAAYKkgVrGQH1AAAAAA==.Pandarina:BAAANQAECgQIBAAAAA==.Papilock:BAAANQADCgUIBQABNQAECgkJIwAJAIwcAA==.Pathalogical:BAAANQAECggICAABNQAECgoKHAADAMMaAA==.Patharok:BAAANQADCgMIAwABNQAECgoKHAADAMMaAA==.Pathator:BAABNQAECn8cAAMDAAoKwxpzZwCtAQADAAkKwxpzZwCtAQAXAAEKAAA5kQAvAAAAAA==.Patheros:BAAANQAECggIDwABNQAECgoKHAADAMMaAA==.Patholan:BAAANQAECgUICQABNQAECgoKHAADAMMaAA==.Patholans:BAAANQADCgEIAQABNQAECgoKHAADAMMaAA==.Pathsqueek:BAAANQADCggICAABNQAECgoKHAADAMMaAA==.Paxmansigh:BAAANQAECgQICgAAAA==.',
Pe='Perfectdart:BAAANQAECggICAAAAA==.Perineumm:BAAANQABCgUIBQAAAA==.',
Ph='Phantöm:BAABNQAECn83AAIOAAkKXB2cBQBDAgAOAAkKXB2cBQBDAgAAAA==.Phragon:BAAANQADCgQIBAAAAA==.',
Pi='Pickle:BAAANQADCgYIBgABNQAECggIKgAfAJghAA==.Piratesmoke:BAAANQADCgYIAwAAAA==.',
Pl='Placcid:BAABNQAECn82AAIDAAoKkRJ3UgDnAQADAAoKkRJ3UgDnAQAAAA==.Planknstein:BAABNQAECn8aAAIEAAkKYwqZmQBZAQAEAAkKYwqZmQBZAQAAAA==.Plantoor:BAABNQAECn9AAAIoAAoKPxV+AwBCAgAoAAoKPxV+AwBCAgAAAA==.',
Po='Pockett:BAAANQAECggICgAAAA==.Ponarp:BAAANQAECgQJCgAAAA==.Porkchop:BAABNQAECn8/AAMJAAoKQxCdPwDlAQAJAAoKQxCdPwDlAQAKAAkKtQo/eQC3AQAAAA==.',
Pr='Preedo:BAAANQADCgMIAwAAAA==.Primøs:BAABNQAECn8XAAMlAAgKJAO4KQB+AAAlAAUKsAK4KQB+AAANAAgKVgL4MwFsAAAAAA==.Prismclaw:BAABNQAECn8qAAIRAAoKxQ9XCwCiAQARAAoKxQ9XCwCiAQAAAA==.Processing:BAACNQAFFH8RAAIeAAcKWw6dCwC3AQAeAAcKWw6dCwC3AQA1AAQKf0cAAh4ACgpTI2MGAB0DAB4ACgpTI2MGAB0DAAAA.',
Pu='Puddle:BAABNQAECn8VAAIKAAgK3gz2WgA6AQAKAAgK3gz2WgA6AQAAAA==.Puddleheal:BAAANQAECgEIAQABNQAECgYICgAQAAAAAA==.Puffdamagic:BAABNQAECn9CAAMiAAoKfA1PEgCUAQAiAAoKfA1PEgCUAQAgAAgKswf7DQBqAQAAAA==.',
Pw='Pwnstarz:BAAANQADCgYIEQAAAA==.',
Py='Pyous:BAAANQAECgUIBQAAAA==.',
Qi='Qirstbytt:BAAANQADCgUIBQAAAA==.',
Qp='Qplus:BAABNQAECn8lAAIDAAgKVQs6rwCmAQADAAgKVQs6rwCmAQAAAA==.',
Qs='Qstorm:BAAANQADCgcIDQAAAA==.',
Qu='Quaenie:BAABNQAECn8iAAIYAAgKQA57iQB6AQAYAAgKQA57iQB6AQAAAA==.Quintin:BAAANQAECgcIBgAAAA==.',
Ra='Ragetotem:BAAANQADCgIIAgAAAA==.Ragewarg:BAAANQAECgEIAQAAAA==.Raginsteel:BAAANQADCgYICwAAAA==.Ralvarr:BAAANQAECgQICAAAAA==.Rayleigh:BAABNQAECn8iAAMRAAcKwhh7CwCeAQARAAcKwhh7CwCeAQASAAEKMwoqwwE5AAABNQAECgYIBgAQAAAAAA==.',
Re='Reckligence:BAAANQAECgIIAQAAAA==.Redchord:BAABNQAECn8WAAIDAAYKCBFukwBHAQADAAYKCBFukwBHAQAAAA==.Regidør:BAABNQAFFH8KAAMEAAUK9xPxFgDzAAAEAAQK9xPxFgDzAAAfAAEKRBUmJwBSAAAAAA==.Regixa:BAABNQAECn8ZAAISAAoKRQmiswATAQASAAoKRQmiswATAQABNQAECgUIBQAQAAAAAA==.Relik:BAABNQAECn8lAAMlAAkKzA9KJAAlAQANAAkKIgnfjAAyAQAlAAcKcw9KJAAlAQAAAA==.Renfoe:BAAANQADCgMIAwAAAA==.Rethan:BAAANQADCgMIAwAAAA==.',
Rh='Rhaelia:BAAANQADCgUIBQAAAA==.Rhaspus:BAABNQAECn8cAAIBAAcKYxFpPQAIAQABAAcKYxFpPQAIAQAAAA==.',
Ri='Rillenne:BAAANQAECgcIDwAAAA==.Rilliccine:BAAANQAECgcIDAAAAA==.Rilliguine:BAAANQAECgMIAgAAAA==.Rillinetti:BAABNQAECn8uAAIMAAgKlBJLZwBmAQAMAAgKlBJLZwBmAQAAAA==.Rillini:BAAANQAECgUICgAAAA==.Rilliti:BAAANQAECgIICAAAAA==.Risky:BAAANQADCgIIAgABNQAECgYICwAQAAAAAA==.Rivertam:BAAANQADCggICAAAAA==.',
Ro='Robotnik:BAAANQAECgIIAQAAAA==.Rogu:BAAANQADCgYIEAAAAA==.Rondon:BAABNQAECn8vAAIDAAkK7SLWIACVAgADAAkK7SLWIACVAgAAAA==.Rookdh:BAACNQAFFH8RAAIBAAcK/Q6iCQCPAQABAAcK/Q6iCQCPAQA1AAQKf0kAAwEACgraIV0LAMkCAAEACgraIV0LAMkCABoACQpOEnISAAcCAAAA.Rosey:BAABNQAECn8sAAIEAAgKQxHHpABEAQAEAAgKQxHHpABEAQAAAA==.Royale:BAABNQAECn8eAAIDAAkKwBaTiwDzAQADAAkKwBaTiwDzAQAAAA==.',
Ru='Rudeus:BAAANQAECgQIBgAAAA==.Rudyeightbal:BAAANQADCgYIBgAAAA==.Rustedbarrel:BAAANQAECgUIBwAAAA==.',
Sa='Saelyres:BAAANQAECggIDwAAAA==.Sagesse:BAAANQAECgQIBAAAAA==.Saisera:BAAANQAECgcICgAAAA==.Samifleur:BAAANQAECggICQAAAA==.Sammy:BAABNQAECn8jAAMEAAgKSwup2wBkAQAEAAgKSwup2wBkAQAfAAEKaQH1OQEbAAAAAA==.Santaclaaws:BAACNQAFFH8SAAIaAAYKMR/HBQDPAQAaAAYKMR/HBQDPAQA1AAQKf0QAAxoACgobI84CAK4DABoACgobI84CAK4DAAEAAgo/HLJ6AI0AAAAA.Santafuego:BAAANQAECgUICgABNQAFFAYIEgAaADEfAA==.Santapal:BAABNQAECn80AAMfAAoKMB0iIgDkAgAfAAoKMB0iIgDkAgAEAAEKBAR7vgEpAAABNQAFFAYIEgAaADEfAA==.Saphotic:BAAANQAFFAIIAQABNQAFFAQIDAAFAH8VAA==.Saydragon:BAAANQADCgQIBAAAAA==.Sayvil:BAAANQAECgcIIgABNQAECgoKFgAYAMYPAQ==.',
Se='Selbor:BAABNQAECn8aAAIEAAgKnwVc2ADsAAAEAAgKnwVc2ADsAAAAAA==.Semmers:BAABNQAECn8YAAIWAAkKvwz8IQB1AQAWAAkKvwz8IQB1AQAAAA==.Sensational:BAAANQAECggIEgAAAA==.Septiria:BAAANQAECgUIEAAAAA==.Sergio:BAAANQADCgcIDwAAAA==.Seyren:BAAANQAECggIEAAAAA==.',
Sh='Shabelly:BAAANQADCgYJBgABNQADCgYIBgAQAAAAAA==.Shadwizmoney:BAAANQADCgEIAQAAAA==.Shalash:BAAANQADCgYIBgABNQAFFAUIDwAmAO0WAA==.Shamadeano:BAABNQAECn8bAAMLAAcKHxKoFQBzAQALAAcKHxKoFQBzAQAJAAEKUgLgKwEjAAAAAA==.Shamanshikz:BAABNQAECn8qAAIKAAoKYh9fHwBKAgAKAAoKYh9fHwBKAgAAAA==.Shamiska:BAABNQAECn8UAAILAAgKTARPJQAHAQALAAgKTARPJQAHAQAAAA==.Shammerdown:BAAANQADCgQIBAAAAA==.Shampooh:BAAANQAECgYICwAAAA==.Shamrockk:BAAANQADCggICAAAAA==.Shaokhan:BAABNQAECn82AAIJAAoKIxwqKQC/AgAJAAoKIxwqKQC/AgAAAA==.Sharazzy:BAAANQAECgIIAgAAAA==.Sharpcukuee:BAAANQAECgEIAQAAAA==.Shazami:BAAANQADCggIDwAAAA==.Shian:BAABNQAECn8vAAIdAAkKyRK/HwBLAQAdAAkKyRK/HwBLAQAAAA==.Shieldee:BAABNQAECn8tAAIEAAoKbRoKYQDWAQAEAAoKbRoKYQDWAQAAAA==.Shigaraki:BAABNQAECn8YAAQlAAkKkRd0DwCGAQAlAAgKLRR0DwCGAQANAAQK3A6b8gD6AAAOAAIK2BqEGgCiAAAAAA==.Shikzzs:BAABNQAECn8sAAMnAAkKTSQqBAAMAwAnAAkKTSQqBAAMAwABAAEKFBn/awBJAAABNQAECgoKKgAKAGIfAA==.Shockeei:BAABNQAECn8rAAISAAkKHSRQIgBTAwASAAkKHSRQIgBTAwAAAA==.Shortdon:BAAANQADCgEIAQAAAA==.Shortebus:BAAANQAECgcICwAAAA==.',
Si='Siakora:BAAANQAECgMIAwABNQAFFAcIEQAeAFsOAA==.Sickwitit:BAABNQAECn8ZAAMSAAkK+wOk9gCdAAASAAkKoQKk9gCdAAARAAgKBAJpNgA2AAAAAA==.Sighh:BAAANQADCgQIBQAAAA==.Sighhi:BAAANQADCgcIBwAAAA==.Sighhy:BAAANQAECgEIAQAAAA==.Sijth:BAABNQAECn9TAAMfAAgK7R5vJwDLAgAfAAgK7R5vJwDLAgAEAAQKbRGZQgG2AAAAAA==.Silvereyes:BAAANQADCgIIAgAAAA==.Silverwar:BAABNQAECn8rAAMlAAkKfxlfDABvAgAlAAkKfxlfDABvAgAOAAEKkQe8KwA0AAAAAA==.Simmi:BAEANQAECggIEwABNQAFFAcIEAAfADYZAA==.Simmune:BAECNQAFFH8QAAIfAAcKNhm0BwDrAQAfAAcKNhm0BwDrAQA1AAQKfzUAAh8ACgoQI+4LAGgDAB8ACgoQI+4LAGgDAAAA.Sinarala:BAAANQAECgMIAgAAAA==.Sirlavan:BAAANQAECgYIBwAAAA==.Sixpath:BAAANQADCgQIAgAAAA==.',
Sk='Skanknstein:BAAANQAECgYICgAAAA==.Skepti:BAABNQAECn8sAAIDAAoK8hu3PAC0AgADAAoK8hu3PAC0AgAAAA==.Skreep:BAAANQADCgUIBQAAAA==.',
Sl='Slybiscuit:BAABNQAECn8wAAILAAkKZAaCGgArAQALAAkKZAaCGgArAQAAAA==.',
Sm='Smeeta:BAABNQAECn86AAIZAAoK6h+bFgD4AgAZAAoK6h+bFgD4AgAAAA==.Smokesmash:BAAANQADCgcIDgAAAA==.',
Sn='Sneakerbaby:BAAANQADCgYIBgAAAA==.',
So='Solaace:BAAANQADCgcIDgABNQAECgQIEwAQAAAAAA==.Soram:BAAANQADCgYIBgAAAA==.Sosa:BAAANQAECgMIBwAAAA==.Soulreaver:BAAANQADCgQIBAAAAA==.Sourdevil:BAAANQABCgIJBAAAAA==.Soùl:BAAANQAECgYIEAAAAA==.',
Sp='Sparkley:BAAANQAECgUICQABNQAECgoKQgAiAHwNAA==.Spike:BAAANQAECggIDwAAAA==.Spinspinspin:BAABNQAECn8WAAINAAoKPgtFmgAUAQANAAoKPgtFmgAUAQABNQAECggICQAQAAAAAA==.',
St='Starlara:BAAANQADCgYIBgAAAA==.Stazz:BAABNQAECn8xAAIDAAoKDwn3oADEAQADAAoKDwn3oADEAQAAAA==.Steelerayne:BAABNQAECn8hAAIDAAgKERFjXQDIAQADAAgKERFjXQDIAQAAAA==.Stian:BAAANQAECgIIAgAAAA==.Stonecrab:BAAANQAECgcIDQAAAA==.Stormcontrol:BAABNQAECn8bAAIKAAgK+xHFbADaAQAKAAgK+xHFbADaAQAAAA==.Stormii:BAAANQAECgEIAQAAAA==.Stormtotem:BAAANQAECgEIAQAAAA==.Strangerdk:BAABNQAECn8YAAIIAAcKdQWJhgAHAQAIAAcKdQWJhgAHAQABNQAECggIDQAQAAAAAA==.Styless:BAAANQABCgYIBwAAAA==.Stðne:BAAANQADCgMIAwAAAA==.',
Sw='Swagboyxx:BAAANQADCgQIBAAAAA==.Swishersweet:BAABNQAECn9JAAIdAAoKsQt6IQA9AQAdAAoKsQt6IQA9AQAAAA==.Swordfish:BAAANQAECgQICgAAAA==.',
Sy='Sybrooke:BAAANQAECgEIAQAAAA==.Sydran:BAAANQAECgYIEAAAAA==.Syrinne:BAAANQADCgEIAQAAAA==.',
Ta='Tabrieus:BAABNQAECn8/AAIRAAoK3CAhAwAdAwARAAoK3CAhAwAdAwAAAA==.Taegia:BAAANQADCgUIBQABNQAFFAUIDgAWAO4WAA==.Talanth:BAABNQAECn8dAAImAAgK3AtvIwD/AAAmAAgK3AtvIwD/AAAAAA==.Talbott:BAAANQADCgEIAQAAAA==.Tandisong:BAAANQAECgIIAQAAAA==.Tanitie:BAAANQADCgEIAQAAAA==.Tanknstein:BAAANQAECgUIBwAAAA==.Tarma:BAAANQADCgMIAwAAAA==.Taro:BAAANQADCggICAABNQAECgoKJgAKANwKAA==.Tarrisx:BAAANQADCgEJAQABNQAECgoKOgAZAOofAA==.Tashi:BAAANQAECgMIAwAAAA==.Tayon:BAAANQAECgYIDQAAAA==.Tayvin:BAAANQADCgEIAQAAAA==.',
Te='Tearza:BAAANQADCggIDwAAAA==.Tempest:BAAANQAECgUIBQAAAA==.Termana:BAACNQAFFH8PAAIlAAYKASJWAgB+AQAlAAYKASJWAgB+AQA1AAQKf0UAAiUACgogJsEAANkDACUACgogJsEAANkDAAAA.',
Th='Thar:BAAANQADCgUJBQAAAA==.Thassa:BAAANQADCgEIAQAAAA==.Thegame:BAAANQADCgQIBAAAAA==.Theodoró:BAABNQAECn8fAAMDAAkKlRrYUgB4AgADAAkKlRrYUgB4AgAXAAIKRQMhfgBMAAAAAA==.Thereza:BAAANQAECgUICwAAAA==.Therynn:BAAANQADCgUIBQAAAA==.Thiccpickle:BAAANQAECggICwAAAA==.Thrashzel:BAAANQADCggIDQAAAA==.Thug:BAAANQADCgcIFQAAAA==.Thundersylph:BAAANQADCgYIBgAAAA==.Thuneredor:BAAANQADCgMIAwAAAA==.',
Ti='Tiferet:BAABNQAECn8zAAMYAAoKdSAUKwC9AgAYAAoKdSAUKwC9AgAFAAMKRQeCRgBhAAAAAA==.Tigiw:BAABNQAECn8bAAIDAAYKAQ9BwgB+AQADAAYKAQ9BwgB+AQAAAA==.Tinysunshine:BAABNQAECn8UAAMVAAcKBRiQKwC/AQAVAAcKBRiQKwC/AQAcAAMKgQppJwCOAAAAAA==.Tinyt:BAAANQADCgMIAwAAAA==.Titonatty:BAAANQABCgQIBAAAAA==.',
To='Tolenkar:BAABNQAECn8iAAIDAAcKWhn4kADnAQADAAcKWhn4kADnAQAAAA==.Tomato:BAACNQAFFH8LAAQPAAYKywhgEACSAAAPAAIKSgxgEACSAAAMAAMKTAW7NACKAAATAAEKAABrFAAAAAA1AAQKfz0AAw8ACgr1IL8CAPwBAA8ACArtIb8CAPwBAAwACArtG2VGAMwBAAAA.Torfelori:BAAANQAECgQICAAAAA==.Torvalar:BAABNQAECn8+AAIEAAoKXRGnfwCNAQAEAAoKXRGnfwCNAQAAAA==.Tove:BAABNQAECn8mAAIKAAoK3ApEggCfAQAKAAoK3ApEggCfAQAAAA==.',
Tr='Trûth:BAABNQAECn8ZAAIFAAgKWQWeOACgAAAFAAgKWQWeOACgAAAAAA==.',
Ts='Tsukimiyoki:BAAANQADCgcIBwAAAA==.',
Tu='Turdyl:BAABNQAECn8mAAIEAAoKzw4FogDdAQAEAAoKzw4FogDdAQAAAA==.Tuxxí:BAAANQADCgYIBgABNQAECgoKOgAZAOofAA==.',
Tw='Twindadlock:BAAANQABCgIIAgABNQAECgQIEQAQAAAAAA==.',
Ty='Tyfelsion:BAAANQAECgEIAQAAAA==.Tyraz:BAAANQADCgUIBQAAAA==.Tyrelline:BAAANQAECgIJAgAAAA==.Tystrolf:BAAANQADCggIEQAAAA==.',
['Tá']='Tárris:BAABNQAECn8lAAIMAAkKDh5AQgCLAgAMAAkKDh5AQgCLAgABNQAECgoKOgAZAOofAA==.',
['Tæ']='Tægia:BAAANQAECgQICAAAAA==.',
['Tô']='Tôx:BAABNQAECn8bAAMKAAgK9h0pQgBtAgAKAAgK9h0pQgBtAgAJAAMKOAl27gCOAAAAAA==.',
Um='Umbranwings:BAABNQAECn8cAAQjAAgKCwg2JAAgAQAjAAgKCwg2JAAgAQAiAAYKAgOnNwDXAAAgAAEKAABZJwAmAAAAAA==.',
Un='Unheardjp:BAAANQAECgUICQAAAA==.',
Ur='Ursus:BAABNQAECn8kAAIeAAkKPgnzUgCPAQAeAAkKPgnzUgCPAQAAAA==.',
Us='Usdaprime:BAAANQAECgIIAgAAAA==.',
Va='Vaerix:BAAANQAECgYIDQAAAA==.Valydrin:BAABNQAECn83AAMYAAoKCxZ5MwA8AgAYAAoKCxZ5MwA8AgAFAAMKjwXUYgB1AAAAAA==.',
Ve='Veera:BAAANQADCgQIBAAAAA==.Vexadrine:BAACNQAFFH8RAAIcAAcKLRPiAwBxAQAcAAcKLRPiAwBxAQA1AAQKf0YAAhwACgp4IRECAOcCABwACgp4IRECAOcCAAAA.Vexiana:BAAANQAECggIDQABNQAFFAcIEQAcAC0TAA==.',
Vo='Vorkhan:BAAANQADCgEIAQAAAA==.',
Vu='Vuldrak:BAABNQAECn8aAAIDAAkKzxwGHwCdAgADAAkKzxwGHwCdAgAAAA==.',
Vy='Vysis:BAACNQAFFH8OAAIFAAYKYhCzCACBAQAFAAYKYhCzCACBAQA1AAQKfzgABAUACgpkHcwPAPgCAAUACgpkHcwPAPgCABgABwoOISdeAAcCAAYABQrUGuoKAJUBAAAA.',
['Ví']='Ví:BAAANQAECgEIAQAAAA==.',
Wa='Warstorm:BAAANQAECgQIBAAAAA==.',
We='Weebdestroya:BAAANQADCgIIAgAAAA==.',
Wh='Whisperfål:BAAANQADCgIIAgAAAA==.',
Wi='Wickèr:BAABNQAECn8rAAQcAAkKbRoFBwDKAQAcAAkKbRoFBwDKAQAVAAUKFxBKQgAFAQAWAAQKWQgkOwCZAAAAAA==.Widgit:BAAANQADCgcIGAAAAA==.Wieldblade:BAABNQAECn9GAAQEAAoKaxbzbwCwAQAEAAoKVRTzbwCwAQAfAAcKixSEbwA1AQACAAYKdxNAKAD7AAAAAA==.',
Wo='Woolverine:BAABNQAECn8hAAMhAAYKqBCJMQAfAQAhAAYKqBCJMQAfAQAeAAQK9hf4SwDBAAAAAA==.',
Wu='Wunderbar:BAABNQAECn8vAAIKAAkKjxcOMgDYAQAKAAkKjxcOMgDYAQAAAA==.',
Wy='Wyldfire:BAACNQAFFH8dAAIeAAYKmhYZCABKAQAeAAYKmhYZCABKAQA1AAQKfzkAAh4ACgqXIfEIAIcDAB4ACgqXIfEIAIcDAAAA.',
Xa='Xanith:BAABNQAECn8iAAINAAoKjAy7awCEAQANAAoKjAy7awCEAQAAAA==.Xanyth:BAAANQADCggICAAAAA==.',
Xe='Xenoviaquart:BAAANQAECgcICQAAAA==.',
Xi='Xia:BAAANQADCgYIBgAAAA==.',
Ya='Yardly:BAAANQAECgEIAQAAAA==.',
Yi='Yia:BAAANQAECgUIEgABNQAECgYIFQAMADAcAA==.Yilnara:BAAANQAECgEIAQAAAA==.',
Ys='Ysa:BAABNQAECn8oAAMVAAoKXyOMBgBnAwAVAAoKXyOMBgBnAwAWAAcK9xNUEgCiAQAAAA==.',
Za='Zalerodora:BAAANQAECgQICAABNQAECgcIHAABAGMRAA==.Zarich:BAABNQAECn8kAAITAAoKvxc5BACfAgATAAoKvxc5BACfAgAAAA==.',
Ze='Zekkun:BAAANQADCggICAAAAA==.Zepheria:BAAANQAECgEIAQABNQAECgoKFgAYAMYPAQ==.',
Zo='Zoga:BAEANQADCgUIBQABNQAECggICAAQAAAAAA==.Zogah:BAEANQAECgQIBAABNQAECggICAAQAAAAAA==.Zoganian:BAEBNQAECn8VAAINAAcKnBcCWwC2AQANAAcKnBcCWwC2AQABNQAECggICAAQAAAAAA==.Zoghog:BAAANQAECgcIDAAAAA==.Zogula:BAEANQAECgQIBQABNQAECggICAAQAAAAAA==.',
Zu='Zullthornp:BAAANQADCgUICQAAAA==.',
Zy='Zyaire:BAAANQABCgYICwAAAA==.',
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
