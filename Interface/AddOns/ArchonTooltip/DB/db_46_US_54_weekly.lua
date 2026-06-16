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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Shaman-Enhancement','Warrior-Protection','Paladin-Retribution','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Blood','Mage-Fire','Warrior-Arms','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-06-13',data={Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgMJBAABLgAECgYJDAABAAAAAA==.',
Ap='Apollo:BAAALgADCgEJAgAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn82AAMCAAkJqCCeIABIAgACAAgJ4x+eIABIAgADAAIJEBlLcACUAAAAAA==.Argorok:BAABLgAECn8dAAIEAAkJgRc3GQAjAgAEAAkJgRc3GQAjAgAAAA==.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9NAAMFAAkJXyV0BgBMAwAFAAkJXyV0BgBMAwAGAAMJ7SGkBwArAQAAAA==.',
Az='Azmodeus:BAAALgAECgUJBgABLgAECgkJIwAHAMETAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAEAEofAA==.Bartholdson:BAABLgAECn8lAAIHAAkJqhnyIQBZAgAHAAkJqhnyIQBZAgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgkJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIIAAkJfxxPDADHAgAIAAkJfxxPDADHAgAAAA==.',
Bo='Bonfire:BAACLgAFFH8JAAIJAAcJuBlqEAD0AQAJAAcJuBlqEAD0AQAuAAQKfyYABAkACQlvI+ALAJoCAAkACQntIuALAJoCAAoABgluITwQAAMBAAsAAglKAoZEAEsAAAAA.Boochili:BAABLgAECn9JAAIMAAkJ7yYXAACRAwAMAAkJ7yYXAACRAwAAAA==.',
Br='Bravebeard:BAABLgAFFH8IAAIEAAMJThWLLgDwAAAEAAMJThWLLgDwAAAAAA==.Braveling:BAABLgAECn8fAAINAAkJ9A6zRgDFAQANAAkJ9A6zRgDFAQAAAA==.',
Bu='Bubblës:BAAALgAECgQJCQABLgAFFAQJCAAOAB0PAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Chad:BAABLgAFFH8FAAIPAAUJLxKYFQDrAAAPAAUJLxKYFQDrAAAAAA==.Charlie:BAACLgAFFH8gAAMQAAcJnCBiCgAiAgAQAAcJnCBiCgAiAgAMAAEJQCPzEgBdAAAuAAQKfzgAAxAACQnOJR8IAFMDABAACQnOJR8IAFMDAAwABQnOGfYkAOkAAAAA.Chicken:BAACLgAFFH8KAAMRAAQJbwx7GAC/AAARAAQJbwx7GAC/AAASAAEJMwMjIQAvAAAuAAQKfxUAAhEACQnrGPUKADACABEACQnrGPUKADACAAEuAAUUBQkFAA8ALxIA.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8LAAICAAUJdhMtIwBYAQACAAUJdhMtIwBYAQAuAAQKf2UAAwIACQn5IYQFAFcDAAIACQn5IYQFAFcDAAMABgl3DplVAN8AAAAA.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn83AAITAAkJoBKHTgDVAQATAAkJoBKHTgDVAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAABLgAECn8eAAMCAAcJHAlybQAOAQACAAcJHAlybQAOAQADAAIJPACjwwACAAAAAA==.Darksabbath:BAAALgADCgUJBQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMTAAMJPhwxpwDKAAATAAMJPhwxpwDKAAAUAAIJSRD+HgCDAAAuAAQKfxsAAxMACAlJI6g0ACoCABMACAnKIqg0ACoCABQAAQkSHbU1AEAAAAAA.Devona:BAABLgAECn8kAAMIAAkJZR04IwDoAQAIAAcJtBw4IwDoAQAQAAgJ0w/IcgCGAQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingdangler:BAAALgAECgQJBwAAAA==.Dingledangle:BAABLgAECn8vAAISAAkJMxcxCQAuAgASAAkJMxcxCQAuAgAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgcJIQAHAAgjAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8TAAIVAAUJWBjBAwBZAQAVAAUJWBjBAwBZAQAuAAQKf0UAAhUACQkUHLsEAD8CABUACQkUHLsEAD8CAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAgABLgAFFAYJFwAWAKcTAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAACLgAFFH8NAAINAAQJyw8XVAAaAQANAAQJyw8XVAAaAQAuAAQKfygAAg0ACQksErZKALkBAA0ACQksErZKALkBAAAA.',
Ey='Eyekicku:BAABLgAECn8iAAIXAAkJrx+zCAC4AgAXAAkJrx+zCAC4AgAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCQAAAA==.',
Fl='Flow:BAAALgAECgQJBAABLgAFFAUJBQAPAC8SAA==.',
Fu='Fuyu:BAAALgAFFAMJBAAAAA==.Fuyuhex:BAABLgAFFH8HAAICAAMJ5RG9WgCRAAACAAMJ5RG9WgCRAAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAgAAAA==.',
Gr='Graycieden:BAABLgAECn8WAAIYAAcJqw/7MwBHAQAYAAcJqw/7MwBHAQAAAA==.',
Gu='Guldangit:BAACLgAFFH8lAAMNAAgJ4B22AQAmAgANAAgJNBy2AQAmAgAZAAUJCyDKAgBxAQAuAAQKfzIABBkACQn/JYUAAD8DABkACQkSJYUAAD8DAA0ACQkBI2oIAD4DABoABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9KAAIbAAkJeBDwGgCjAQAbAAkJeBDwGgCjAQAAAA==.',
Hh='Hhounow:BAAALgAECgEJAgAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECggJDgAAAA==.Holygrim:BAACLgAFFH8uAAIcAAgJGSQaAABvAgAcAAgJGSQaAABvAgAuAAQKfx0AAxwACAljJuABAFcDABwACAljJuABAFcDABgAAQk+CT2NACsAAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9OAAQdAAkJkB8BBgAiAwAdAAkJkB8BBgAiAwAYAAcJZBs6HQDaAQAcAAQJrQuVXQC8AAAAAA==.Howii:BAABLgAECn9PAAIeAAkJryVuAQBMAwAeAAkJryVuAQBMAwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIHAAkJZBUfMwALAgAHAAkJZBUfMwALAgAAAA==.',
Je='Jellyfîsh:BAABLgAECn8VAAMZAAcJcxm8FwACAQANAAYJkxRulwANAQAZAAYJJBK8FwACAQAAAA==.Jeraziah:BAAALgAECgUJEQABLgAECgkJNgACAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8sAAIEAAkJkiFsBgD3AgAEAAkJkiFsBgD3AgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
Ky='Kynna:BAAALgAECgMJAwAAAA==.',
La='Laggers:BAABLgAECn8jAAIRAAgJdxZFHgBVAQARAAgJdxZFHgBVAQAAAA==.',
Le='Lean:BAAALgAFFAIJAwABLgAFFAcJCQAJALgZAA==.',
Li='Litbit:BAABLgAECn8qAAIFAAkJQgWllABMAQAFAAkJQgWllABMAQAAAA==.Litbitonme:BAAALgAECgQJDgAAAA==.Litllit:BAAALgAECgUJDAAAAA==.Litt:BAAALgADCgkJCwAAAA==.Liuye:BAAALgAECgYJCgAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8sAAITAAkJ3CIxCQAlAwATAAkJ3CIxCQAlAwAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.Lustypablo:BAAALgAECgIJAwAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMFAAgJIxA2cACWAQAFAAgJIxA2cACWAQAfAAEJCAz8FAApAAAAAA==.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgAECgUJBQAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAwABLgAFFAYJFwATAPwWAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMbAAkJWxugEQBRAgAbAAkJWxugEQBRAgAWAAQJ6gQD6QBjAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJTgAdAJAfAA==.',
Pe='Periodic:BAACLgAFFH8RAAICAAQJKCNCHQB7AQACAAQJKCNCHQB7AQAuAAQKfy8AAgIACQnkI/QAAJkDAAIACQnkI/QAAJkDAAAA.',
Pl='Platen:BAABLgAECn8jAAIHAAkJQRJBPgDkAQAHAAkJQRJBPgDkAQAAAA==.',
Po='Potter:BAABLgAECn9FAAIFAAkJbB8OHACxAgAFAAkJbB8OHACxAgAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIXAAcJiB7IGADoAQAXAAcJiB7IGADoAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8JAAIFAAUJGRzfSQBTAQAFAAUJGRzfSQBTAQABLgAFFAcJCQAJALgZAA==.Rapunzel:BAAALgAECgkJDwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMEAAkJ4QTqXQDaAAAEAAgJ/wPqXQDaAAAgAAgJqwPqRgCpAAAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8jAAISAAcJ5CCjAABYAgASAAcJ5CCjAABYAgAuAAQKfy0AAhIACQkQJakBACQDABIACQkQJakBACQDAAAA.',
Ro='Rovintis:BAABLgAECn9HAAIgAAkJIhvLBgCMAgAgAAkJIhvLBgCMAgAAAA==.',
Ry='Rynne:BAABLgAECn8eAAQCAAkJeBR/JwAdAgACAAkJeBR/JwAdAgAOAAcJ8AcBHAAKAQADAAEJZwMnvQAdAAAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAILAAkJsSJ+AgBJAwALAAkJsSJ+AgBJAwAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgcJCwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn80AAIeAAkJLxeVDgAgAgAeAAkJLxeVDgAgAgAAAA==.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8KAAICAAMJ1hHsSwC7AAACAAMJ1hHsSwC7AAAuAAQKfxoAAgIACQkNFQ9FAJUBAAIACQkNFQ9FAJUBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJCwAAAA==.',
Si='Silvertiger:BAABLgAECn9MAAMhAAkJ3h9ABgC9AgAhAAkJ3h9ABgC9AgAiAAcJgg+dPABsAQAAAA==.',
Sl='Slabbydabby:BAABLgAFFH8FAAIEAAMJAhgDLgDzAAAEAAMJAhgDLgDzAAAAAA==.Slabdab:BAAALgAECgIJAgAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgUJBwABLgAECgkJTgAdAJAfAA==.Sneaki:BAABLgAECn9IAAQjAAkJdyVJBQDeAgAjAAkJ+SNJBQDeAgAkAAgJ/RyEBAA0AgAVAAEJsSNKHgBoAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQcAAYJbRfiLACTAQAcAAYJbRfiLACTAQAYAAQJ5gMhTQChAAAdAAIJkQhZTQBdAAAAAA==.',
So='Sorynia:BAABLgAECn8kAAIHAAkJ1QdWYgB8AQAHAAkJ1QdWYgB8AQAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIWAAMJ5xljWgDZAAAWAAMJ5xljWgDZAAAuAAQKfxsAAhYACAmNISsiAIQCABYACAmNISsiAIQCAAAA.Startawar:BAACLgAFFH8FAAIQAAIJxhIKlQCFAAAQAAIJxhIKlQCFAAAuAAQKfyQAAhAACAnHIywWAOQCABAACAnHIywWAOQCAAAA.Stormbeard:BAAALgAECgUJBQABLgAFFAcJIAAQAJwgAA==.Stripteased:BAAALgAECgUJCAAAAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgcJCwAAAA==.',
Th='Thelandrius:BAAALgADCgIJAgAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAACLgAFFH8GAAMlAAMJPBxkLwDtAAAlAAMJPBxkLwDtAAAmAAEJHgWiUAAxAAAuAAQKfzcAAyUACQnKJe4AANYDACUACQnKJe4AANYDACYAAQmCHhJ2AFYAAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgADCgMJAwABAAAAAA==.Valkyrïe:BAAALgADCgMJAwAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAYJFwAPAGQhAA==.',
Ve='Vendetta:BAAALgAECgEJAQABLgAFFAUJBQAPAC8SAA==.Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAITAAMJABnMkgDjAAATAAMJABnMkgDjAAAuAAQKfzAAAhMACQkzH60QAOUCABMACQkzH60QAOUCAAAA.Vishlock:BAABLgAECn8xAAMZAAkJhBmvBwDvAQAZAAkJhBmvBwDvAQANAAgJ8w4OlAAwAQAAAA==.',
Vo='Voddie:BAABLgAECn8gAAIDAAkJPgxLNABmAQADAAkJPgxLNABmAQAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAABLgAECn8YAAITAAgJxhQVTQDZAQATAAgJxhQVTQDZAQABLgAECgkJHgAJAEkUAA==.Wapta:BAAALgAFFAEJAQABLgAFFAcJCQAJALgZAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8dAAInAAgJOxBiKQBmAQAnAAgJOxBiKQBmAQABLgAFFAUJBQAPAC8SAA==.Woof:BAAALgAECgIJAgAAAA==.',
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
