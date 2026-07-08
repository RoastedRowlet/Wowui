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

local lookup = {'Unknown-Unknown','Warrior-Fury','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Shaman-Enhancement','Warrior-Protection','Paladin-Retribution','Druid-Guardian','Druid-Feral','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Blood','Mage-Fire','Warrior-Arms','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abfu:BAAALgADCgEJAQAAAA==.',
Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgMJBAABLgAECgYJDQABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Argorok:BAABLgAECn8fAAICAAkJ+xmiGQAhAgACAAkJ+xmiGQAhAgAAAA==.',
As='Asmadeus:BAAALgAECgcJCAAAAA==.',
Ay='Ayda:BAABLgAECn9NAAMDAAkJXyXHBgBKAwADAAkJXyXHBgBKAwAEAAMJ7SHPBwArAQAAAA==.',
Az='Azmodeus:BAAALgAECgUJBgABLgAECgkJJwAFAOQTAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgACAEofAA==.Bartholdson:BAABLgAECn8mAAIFAAkJqhniIgBYAgAFAAkJqhniIgBYAgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgkJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIGAAkJfxyDDADGAgAGAAkJfxyDDADGAgAAAA==.Bloodidit:BAAALgADCgEJAQAAAA==.',
Bo='Bonfire:BAACLgAFFH8RAAMHAAkJ9RmXAAB3AQAIAAkJ+RjXEQDuAQAHAAQJch6XAAB3AQAuAAQKfyYABAgACQlvIwIMAJoCAAgACQntIgIMAJoCAAcABgluIYUQAAMBAAkAAglKAoZEAEsAAAEuAAUUCQkWAAMAqBMA.Boochili:BAABLgAECn9JAAIKAAkJ7yYYAACRAwAKAAkJ7yYYAACRAwAAAA==.',
Br='Bravebeard:BAABLgAFFH8JAAICAAMJjhU0MADvAAACAAMJjhU0MADvAAAAAA==.Braveling:BAABLgAECn8fAAILAAkJ9A5ZSADBAQALAAkJ9A5ZSADBAQAAAA==.',
Bu='Bubblës:BAAALgAECgQJCQABLgAFFAUJEQAMAFwRAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Chad:BAABLgAFFH8aAAINAAkJmxHpAQAqAgANAAkJmxHpAQAqAgAAAA==.Charlie:BAACLgAFFH8mAAMOAAgJ5hzACwAgAgAOAAgJ5hzACwAgAgAKAAEJQCOeEwBdAAAuAAQKfzgAAw4ACQnOJR8IAFMDAA4ACQnOJR8IAFMDAAoABQnOGXwlAOkAAAAA.Chicken:BAACLgAFFH8KAAMPAAQJbwzNGQC7AAAPAAQJbwzNGQC7AAAQAAEJMwPKIgAvAAAuAAQKfxUAAg8ACQnrGDALADECAA8ACQnrGDALADECAAEuAAUUCQkaAA0AmxEA.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
Cu='Cupid:BAAALgADCgEJAgAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8MAAIRAAYJtBT9FgCuAQARAAYJtBT9FgCuAQAuAAQKf2UAAxEACQn5IbkFAFYDABEACQn5IbkFAFYDABIABgl3DghXAN8AAAAA.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn9DAAITAAkJCxRDBgCBAQATAAkJCxRDBgCBAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAABLgAECn8lAAMRAAgJKwq+EgCDAAARAAgJKwq+EgCDAAASAAIJPADcxwACAAAAAA==.Darksabbath:BAAALgADCgUJBQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMTAAMJPhyZrADHAAATAAMJPhyZrADHAAAUAAIJSRCYIACDAAAuAAQKfxsAAxMACAlJI7c1ACgCABMACAnKIrc1ACgCABQAAQkSHUo3AEAAAAAA.Demonshard:BAAALgADCgUJCgAAAA==.Devona:BAABLgAECn8kAAMGAAkJZR34IwDlAQAGAAcJtBz4IwDlAQAOAAgJ0w/UdQCCAQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingdangler:BAAALgAECgQJBwAAAA==.Dingledangle:BAABLgAECn9GAAIQAAkJiR2AAABtAgAQAAkJiR2AAABtAgAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgcJIgAFAHgjAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8YAAIVAAUJWBj6AAA6AQAVAAUJWBj6AAA6AQAuAAQKf0UAAhUACQkUHMkEAD8CABUACQkUHMkEAD8CAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAgABLgAFFAcJGAAWANMSAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAACLgAFFH8QAAILAAQJZRTHIADVAAALAAQJZRTHIADVAAAuAAQKfygAAgsACQksEjlMALYBAAsACQksEjlMALYBAAAA.',
Ey='Eyekicku:BAACLgAFFH8JAAIXAAUJvxjnBAAeAQAXAAUJvxjnBAAeAQAuAAQKfyIAAhcACQmvH+cIALcCABcACQmvH+cIALcCAAAA.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCQAAAA==.',
Fl='Flow:BAAALgAECgQJBAABLgAFFAkJGgANAJsRAA==.',
Fu='Fuyu:BAAALgAFFAMJBAAAAA==.Fuyuhex:BAABLgAFFH8JAAIRAAMJ5xGLXQCRAAARAAMJ5xGLXQCRAAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAgAAAA==.',
Gr='Graycieden:BAABLgAECn8jAAIYAAgJyxUSAgDIAQAYAAgJyxUSAgDIAQAAAA==.',
Gu='Guldangit:BAACLgAFFH8xAAMLAAkJLCK2AQAmAgALAAkJFiG2AQAmAgAZAAUJkiSeAQCvAQAuAAQKfzIABBkACQn/JYoAAD0DAAsACQkBI2oIAD4DABkACQkSJYoAAD0DABoABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9KAAIbAAkJeBDEGwCfAQAbAAkJeBDEGwCfAQAAAA==.',
Hh='Hhounow:BAAALgAECgEJAgAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECggJDgAAAA==.Holygrim:BAACLgAFFH82AAIcAAkJ3iQaAABvAgAcAAkJ3iQaAABvAgAuAAQKfx0AAxwACAljJuABAFcDABwACAljJuABAFcDABgAAQk+Cd2PACsAAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9RAAQdAAkJwR/yBQAlAwAdAAkJwR/yBQAlAwAYAAcJ0BtpHQDaAQAcAAQJrQuVXQC8AAAAAA==.Howii:BAABLgAECn9PAAIeAAkJryWCAQBJAwAeAAkJryWCAQBJAwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIFAAkJZBVeNAALAgAFAAkJZBVeNAALAgAAAA==.',
Je='Jellyfîsh:BAABLgAECn8VAAMZAAcJcxlDGAACAQALAAYJkxQJmAAMAQAZAAYJJBJDGAACAQAAAA==.Jeraziah:BAAALgAECgUJEQABLgAECgkJNgARAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8sAAICAAkJkiGXBgD1AgACAAkJkiGXBgD1AgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
Ky='Kynna:BAAALgAECgUJBwAAAA==.',
La='Laggers:BAABLgAECn8jAAIPAAgJdxb7HgBVAQAPAAgJdxb7HgBVAQAAAA==.',
Le='Lean:BAAALgAFFAIJAwABLgAFFAkJFgADAKgTAA==.',
Li='Litbit:BAABLgAECn8qAAIDAAkJQgXKlgBLAQADAAkJQgXKlgBLAQAAAA==.Litbitonme:BAAALgAECgQJDgAAAA==.Litllit:BAAALgAECgUJDAAAAA==.Litt:BAAALgADCgkJCwAAAA==.Liuye:BAAALgAECgYJEQAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8sAAITAAkJ3CKFCQAjAwATAAkJ3CKFCQAjAwAAAA==.Lotsofdots:BAAALgAECgEJAQAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.Lustypablo:BAAALgAECgIJAwAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMDAAgJIxC4cQCWAQADAAgJIxC4cQCWAQAfAAEJCAyuFQApAAAAAA==.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgAECgUJBQAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAwABLgAFFAYJGgATABkYAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMbAAkJWxugEQBRAgAbAAkJWxugEQBRAgAWAAQJ6gTj7ABjAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJUQAdAMEfAA==.',
Pe='Periodic:BAACLgAFFH8WAAIRAAQJwiNrHACJAQARAAQJwiNrHACJAQAuAAQKfy8AAhEACQnkI/QAAJkDABEACQnkI/QAAJkDAAAA.',
Pl='Platen:BAABLgAECn8jAAIFAAkJQRK9PwDjAQAFAAkJQRK9PwDjAQAAAA==.',
Po='Potter:BAABLgAECn9FAAIDAAkJbB+qHACwAgADAAkJbB+qHACwAgAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIXAAcJiB5aGQDnAQAXAAcJiB5aGQDnAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8WAAMDAAkJqBOvBACRAgADAAkJdxOvBACRAgAfAAQJKxO4AQDpAAAAAA==.Rapunzel:BAAALgAECgkJDwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMCAAkJ4QSOXwDXAAACAAgJ/wOOXwDXAAAgAAgJqwO0SACpAAAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8mAAIQAAcJ5CC/AABXAgAQAAcJ5CC/AABXAgAuAAQKfy0AAhAACQkQJbYBACQDABAACQkQJbYBACQDAAAA.',
Ro='Rovintis:BAABLgAECn9HAAIgAAkJIhv1BgCLAgAgAAkJIhv1BgCLAgAAAA==.',
Ry='Rynne:BAABLgAECn8gAAQRAAkJeBREKAAeAgARAAkJeBREKAAeAgAMAAcJ8AcBHAAKAQASAAEJZwMSwQAdAAAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIJAAkJsSJ+AgBJAwAJAAkJsSJ+AgBJAwAAAA==.Sargeràs:BAAALgAECgIJAgABLgAECgcJDAABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn80AAIeAAkJLxfrDgAdAgAeAAkJLxfrDgAdAgAAAA==.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8KAAIRAAMJ1hFrTgC7AAARAAMJ1hFrTgC7AAAuAAQKfxoAAhEACQkNFTVGAJUBABEACQkNFTVGAJUBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJCwAAAA==.',
Si='Silvertiger:BAABLgAECn9MAAMhAAkJ3h9uBgC6AgAhAAkJ3h9uBgC6AgAiAAcJgg+dPABsAQAAAA==.',
Sl='Slabbydabby:BAABLgAFFH8IAAICAAMJaBzUDQD1AAACAAMJaBzUDQD1AAAAAA==.Slabdab:BAAALgAFFAQJBAAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgUJCAABLgAECgkJUQAdAMEfAA==.Sneaki:BAABLgAECn9IAAQjAAkJdyVpBQDcAgAjAAkJ+SNpBQDcAgAkAAgJ/RySBAAzAgAVAAEJsSO5HgBoAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQcAAYJbRfiLACTAQAcAAYJbRfiLACTAQAYAAQJ5gMhTQChAAAdAAIJkQhZTQBdAAAAAA==.',
So='Sorynia:BAABLgAECn85AAIFAAkJOg4gCAB9AQAFAAkJOg4gCAB9AQAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIWAAMJ5xkPXQDYAAAWAAMJ5xkPXQDYAAAuAAQKfxsAAhYACAmNISsiAIQCABYACAmNISsiAIQCAAAA.Startawar:BAACLgAFFH8FAAIOAAIJxhIQmgCFAAAOAAIJxhIQmgCFAAAuAAQKfyQAAg4ACAnHIywWAOQCAA4ACAnHIywWAOQCAAAA.Stormbeard:BAAALgAECgUJBQABLgAFFAgJJgAOAOYcAA==.Stripteased:BAAALgAECgUJCQAAAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgcJDAAAAA==.',
Th='Thelandrius:BAAALgAECgQJBAAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAACLgAFFH8JAAMlAAQJUBf1JwAeAQAlAAQJUBf1JwAeAQAmAAEJHgUWUwAxAAAuAAQKfzcAAyUACQnKJf4AANUDACUACQnKJf4AANUDACYAAQmCHgp4AFYAAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgkJAQABAAAAAA==.Valkyrïe:BAAALgAECgkJAQAAAA==.Vauntdk:BAAALgADCgEJAQABLgAFFAYJGQANAGQhAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAYJGQANAGQhAA==.',
Ve='Vendetta:BAAALgAECgEJAQABLgAFFAkJGgANAJsRAA==.Vercyv:BAAALgADCgkJEQAAAA==.Verymelon:BAABLgAECn82AAMRAAkJqCBHIQBIAgARAAgJ4x9HIQBIAgASAAIJEBlJcgCUAAAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAITAAMJABmVlwDfAAATAAMJABmVlwDfAAAuAAQKfzAAAhMACQkzHxcRAOQCABMACQkzHxcRAOQCAAAA.Vishlock:BAABLgAECn8xAAMZAAkJhBn8BwDsAQAZAAkJhBn8BwDsAQALAAgJ8w4OlAAwAQAAAA==.',
Vo='Voddie:BAABLgAECn8gAAISAAkJPgxnNQBlAQASAAkJPgxnNQBlAQAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAFFAEJAQAAAA==.Walmarthas:BAABLgAECn8YAAITAAgJxhROTgDYAQATAAgJxhROTgDYAQABLgAFFAMJBQAIAI8IAA==.Wapta:BAAALgAFFAEJAQABLgAFFAkJFgADAKgTAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8dAAInAAgJOxDcKQBmAQAnAAgJOxDcKQBmAQABLgAFFAkJGgANAJsRAA==.Woof:BAAALgAECgIJAgAAAA==.',
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
