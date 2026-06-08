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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Druid-Guardian','Paladin-Retribution','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Blood','Mage-Fire','Warrior-Arms','Shaman-Enhancement','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-06-06',data={Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgMJBAABLgAECgYJCwABAAAAAA==.',
Ap='Apollo:BAAALgADCgEJAgAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn82AAMCAAkJqCAeHwBJAgACAAgJ4x8eHwBJAgADAAIJEBmDawCVAAAAAA==.Argorok:BAABLgAECn8dAAIEAAkJgRftFwAoAgAEAAkJgRftFwAoAgAAAA==.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9NAAMFAAkJXyXYBQBRAwAFAAkJXyXYBQBRAwAGAAMJ7SFABwAtAQAAAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAEAEofAA==.Bartholdson:BAABLgAECn8hAAIHAAkJ3hieJQA/AgAHAAkJ3hieJQA/AgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgkJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIIAAkJfxyfCwDJAgAIAAkJfxyfCwDJAgAAAA==.',
Bo='Bonfire:BAACLgAFFH8JAAIJAAcJuBm2DQD+AQAJAAcJuBm2DQD+AQAuAAQKfyYABAkACQlvI2QLAJsCAAkACQntImQLAJsCAAoABgluIbQPAAQBAAsAAglKAoZEAEsAAAAA.Boochili:BAABLgAECn9JAAIMAAkJ7yYOAACSAwAMAAkJ7yYOAACSAwAAAA==.',
Br='Bravebeard:BAABLgAFFH8IAAIEAAMJThXmKgDyAAAEAAMJThXmKgDyAAAAAA==.Braveling:BAABLgAECn8fAAINAAkJ9A7TQwDKAQANAAkJ9A7TQwDKAQAAAA==.',
Bu='Bubblës:BAAALgAECgQJCQABLgAFFAQJBAABAAAAAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Chad:BAAALgAECgEJAQABLgAFFAQJCAAOAHcKAA==.Charlie:BAACLgAFFH8ZAAMPAAcJOx9gCAAjAgAPAAcJOx9gCAAjAgAMAAEJQCMFEgBeAAAuAAQKfzgAAw8ACQnOJR8IAFMDAA8ACQnOJR8IAFMDAAwABQnOGZEjAOoAAAAA.Chicken:BAABLgAFFH8IAAMOAAQJdwr7FgC5AAAOAAQJdwr7FgC5AAAQAAEJMwOoHQAvAAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8LAAICAAUJdhMlHwBcAQACAAUJdhMlHwBcAQAuAAQKf2UAAwIACQn5IQoFAFkDAAIACQn5IQoFAFkDAAMABgl3DuZRAN8AAAAA.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn8zAAIRAAgJvhPqZQCTAQARAAgJvhPqZQCTAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAABLgAECn8aAAMCAAcJHAl/aQAPAQACAAcJHAl/aQAPAQADAAEJAAATvAAAAAAAAA==.Darksabbath:BAAALgADCgUJBQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMRAAMJPhzBmgDPAAARAAMJPhzBmgDPAAASAAIJSRBYGwCDAAAuAAQKfxsAAxEACAlJI74xADACABEACAnKIr4xADACABIAAQkSHTEyAEEAAAAA.Devona:BAABLgAECn8kAAMIAAkJZR3pIQDqAQAIAAcJtBzpIQDqAQAPAAgJ0w8QbgCHAQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingdangler:BAAALgAECgQJBwAAAA==.Dingledangle:BAABLgAECn8rAAIQAAgJaBcFDADmAQAQAAgJaBcFDADmAQAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgcJIQAHAAgjAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8SAAITAAUJnxdUAwBiAQATAAUJnxdUAwBiAQAuAAQKf0UAAhMACQkUHH8EAEACABMACQkUHH8EAEACAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAgABLgAFFAYJFwAUAKcTAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAACLgAFFH8JAAINAAQJLwzAVwAKAQANAAQJLwzAVwAKAQAuAAQKfygAAg0ACQksEglIAL4BAA0ACQksEglIAL4BAAAA.',
Ey='Eyekicku:BAABLgAECn8iAAIVAAkJrx8vCAC6AgAVAAkJrx8vCAC6AgAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCQAAAA==.',
Fl='Flow:BAAALgAECgQJBAABLgAFFAQJCAAOAHcKAA==.',
Fu='Fuyu:BAAALgAFFAIJAwAAAA==.Fuyuhex:BAABLgAFFH8GAAICAAMJ5RHQVACUAAACAAMJ5RHQVACUAAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAQAAAA==.',
Gr='Graycieden:BAABLgAECn8UAAIWAAcJqw+YOwAbAQAWAAcJqw+YOwAbAQAAAA==.',
Gu='Guldangit:BAACLgAFFH8kAAMNAAgJcR22AQAmAgANAAgJNBy2AQAmAgAXAAUJSR+lAgBtAQAuAAQKfzIABBcACQn/JXIAAEIDABcACQkSJXIAAEIDAA0ACQkBI2oIAD4DABgABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9KAAIZAAkJeBB6GQCkAQAZAAkJeBB6GQCkAQAAAA==.',
Hh='Hhounow:BAAALgAECgEJAQAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECggJDgAAAA==.Holygrim:BAACLgAFFH8pAAIaAAgJGSQaAABvAgAaAAgJGSQaAABvAgAuAAQKfx0AAxoACAljJuABAFcDABoACAljJuABAFcDABYAAQk+CeWDAC4AAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9OAAQbAAkJkB+tBQAiAwAbAAkJkB+tBQAiAwAWAAcJZBsbHADdAQAaAAQJrQuVXQC8AAAAAA==.Howii:BAABLgAECn9PAAIcAAkJryVFAQBRAwAcAAkJryVFAQBRAwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIHAAkJZBV8LwATAgAHAAkJZBV8LwATAgAAAA==.',
Je='Jellyfîsh:BAABLgAECn8VAAMXAAcJcxlAFgADAQANAAYJkxR/lAAOAQAXAAYJJBJAFgADAQAAAA==.Jeraziah:BAAALgAECgUJEQABLgAECgkJNgACAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8sAAIEAAkJkiHPBQD8AgAEAAkJkiHPBQD8AgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIOAAgJdxaTHABWAQAOAAgJdxaTHABWAQAAAA==.',
Le='Lean:BAAALgAFFAIJAwABLgAFFAcJCQAJALgZAA==.',
Li='Litbit:BAABLgAECn8oAAIFAAgJdAUxrAAjAQAFAAgJdAUxrAAjAQAAAA==.Litbitonme:BAAALgAECgQJDgAAAA==.Litllit:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Liuye:BAAALgAECgQJBQAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8nAAIRAAkJTiKaCwAKAwARAAkJTiKaCwAKAwAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMFAAgJIxC3awCdAQAFAAgJIxC3awCdAQAdAAEJCAxLEwAsAAAAAA==.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgAECgUJBQAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAwABLgAFFAUJFQARAMgWAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMZAAkJWxugEQBRAgAZAAkJWxugEQBRAgAUAAQJ6gR14ABjAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJTgAbAJAfAA==.',
Pe='Periodic:BAACLgAFFH8RAAICAAQJKCObGQCAAQACAAQJKCObGQCAAQAuAAQKfy8AAgIACQnkI/QAAJkDAAIACQnkI/QAAJkDAAAA.',
Pl='Platen:BAABLgAECn8jAAIHAAkJQRJzOgDqAQAHAAkJQRJzOgDqAQAAAA==.',
Po='Potter:BAABLgAECn9FAAIFAAkJbB9EGgC2AgAFAAkJbB9EGgC2AgAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIVAAcJiB6oFwDqAQAVAAcJiB6oFwDqAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8JAAIFAAUJGRzjQgBXAQAFAAUJGRzjQgBXAQABLgAFFAcJCQAJALgZAA==.Rapunzel:BAAALgAECgkJDwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMEAAkJ4QQ/WgDcAAAEAAgJ/wM/WgDcAAAeAAgJqwOOQwCtAAAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8jAAIQAAcJ5CBvAABoAgAQAAcJ5CBvAABoAgAuAAQKfy0AAhAACQkQJYEBACgDABAACQkQJYEBACgDAAAA.',
Ro='Rovintis:BAABLgAECn9HAAIeAAkJIhtuBgCNAgAeAAkJIhtuBgCNAgAAAA==.',
Ry='Rynne:BAABLgAECn8eAAQCAAkJeBTEJQAeAgACAAkJeBTEJQAeAgAfAAcJ8AcBHAAKAQADAAEJZwNmtAAdAAAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAILAAkJsSJ+AgBJAwALAAkJsSJ+AgBJAwAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgUJBgABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn80AAIcAAkJLxeXDQAmAgAcAAkJLxeXDQAmAgAAAA==.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8IAAICAAMJ9BBRRwC7AAACAAMJ9BBRRwC7AAAuAAQKfxoAAgIACQkNFVNCAJYBAAIACQkNFVNCAJYBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJCwAAAA==.',
Si='Silvertiger:BAABLgAECn9MAAMgAAkJ3h/QBQDCAgAgAAkJ3h/QBQDCAgAhAAcJgg+dPABsAQAAAA==.',
Sl='Slabbydabby:BAAALgAFFAMJAwAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgUJBwABLgAECgkJTgAbAJAfAA==.Sneaki:BAABLgAECn9IAAQiAAkJdyXSBADgAgAiAAkJ+SPSBADgAgAjAAgJ/RxiBAAyAgATAAEJsSMwHQBoAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQaAAYJbRfiLACTAQAaAAYJbRfiLACTAQAWAAQJ5gMhTQChAAAbAAIJkQhZTQBdAAAAAA==.',
So='Sorynia:BAABLgAECn8gAAIHAAgJjQe9ewA6AQAHAAgJjQe9ewA6AQAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIUAAMJ5xksVADfAAAUAAMJ5xksVADfAAAuAAQKfxsAAhQACAmNISsiAIQCABQACAmNISsiAIQCAAAA.Startawar:BAACLgAFFH8FAAIPAAIJxhLXiACJAAAPAAIJxhLXiACJAAAuAAQKfyQAAg8ACAnHIywWAOQCAA8ACAnHIywWAOQCAAAA.Stormbeard:BAAALgAECgUJBQABLgAFFAcJGQAPADsfAA==.Stripteased:BAAALgAECgMJAwAAAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgUJBgAAAA==.',
Th='Thelandrius:BAAALgADCgIJAgAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAACLgAFFH8GAAMkAAMJPByGLgDyAAAkAAMJPByGLgDyAAAlAAEJHgW4SwAxAAAuAAQKfzEAAyQACQnGI28CAKIDACQACQnGI28CAKIDACUAAQmCHvlxAFYAAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgADCgMJAwABAAAAAA==.Valkyrïe:BAAALgADCgMJAwAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAYJEwAmADQhAA==.',
Ve='Vendetta:BAAALgAECgEJAQABLgAFFAQJCAAOAHcKAA==.Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAIRAAMJABkthwDnAAARAAMJABkthwDnAAAuAAQKfzAAAhEACQkzHxgPAOsCABEACQkzHxgPAOsCAAAA.Vishlock:BAABLgAECn8xAAMXAAkJhBkrBwDwAQAXAAkJhBkrBwDwAQANAAgJ8w4OlAAwAQAAAA==.',
Vo='Voddie:BAABLgAECn8gAAIDAAkJPgwUMgBnAQADAAkJPgwUMgBnAQAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAABLgAECn8YAAIRAAgJxhS2SgDbAQARAAgJxhS2SgDbAQABLgAECgkJHgAJAEkUAA==.Wapta:BAAALgAFFAEJAQABLgAFFAcJCQAJALgZAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8dAAInAAgJOxBRKABnAQAnAAgJOxBRKABnAQABLgAFFAQJCAAOAHcKAA==.Woof:BAAALgAECgIJAgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgcJEwAAAA==.',
Ze='Zenithmage:BAAALgAECgcJDQAAAA==.',
['Ár']='Ártémes:BAAALgADCggJAgAAAA==.',
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
