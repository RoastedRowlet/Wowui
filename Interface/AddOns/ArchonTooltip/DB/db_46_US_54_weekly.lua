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

local lookup = {'Unknown-Unknown','Warrior-Fury','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Mage-Fire','Paladin-Protection','Warlock-Demonology','Shaman-Enhancement','DeathKnight-Blood','Warrior-Protection','Paladin-Retribution','Druid-Guardian','Druid-Feral','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Warrior-Arms','Rogue-Outlaw','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-08-18',data={Ab='Abfu:BAAALgADCgEJAQAAAA==.',
Ae='Aendean:BAAALgAECgUJBQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgMJBAABLgAECgYJEAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Argorok:BAABLgAECn8fAAICAAkJ+xmiGQAhAgACAAkJ+xmiGQAhAgAAAA==.',
As='Asayis:BAAALgAECgEJAQAAAA==.Asmadeus:BAAALgAECgcJCAAAAA==.',
Ay='Ayda:BAABLgAECn9NAAMDAAkJXyXHBgBKAwADAAkJXyXHBgBKAwAEAAMJ7SHPBwArAQAAAA==.',
Az='Azmodeus:BAAALgAECgUJBgABLgAFFAIJBgAFAFwMAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgACAEofAA==.Bartholdson:BAABLgAECn8mAAIFAAkJqhniIgBYAgAFAAkJqhniIgBYAgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgkJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIGAAkJfxyDDADGAgAGAAkJfxyDDADGAgAAAA==.Bloodidit:BAAALgADCgEJAQAAAA==.',
Bo='Bonfire:BAACLgAFFH8WAAMHAAkJHhrXEQDuAQAHAAkJIhnXEQDuAQAIAAQJch7EAQBGAQAuAAQKfyYABAcACQlvIwIMAJoCAAcACQntIgIMAJoCAAgABgluIYUQAAMBAAkAAglKAoZEAEsAAAEuAAUUCQknAAoAFRsA.Boochili:BAABLgAECn9JAAILAAkJ7yYYAACRAwALAAkJ7yYYAACRAwAAAA==.',
Br='Bravebeard:BAABLgAFFH8JAAICAAMJjhU0MADvAAACAAMJjhU0MADvAAAAAA==.Braveling:BAABLgAECn8fAAIMAAkJ9A5ZSADBAQAMAAkJ9A5ZSADBAQAAAA==.',
Bu='Bubblës:BAAALgAECgQJCQABLgAFFAcJHQANAMkaAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.Carmella:BAAALgAECgQJBgAAAA==.Cattle:BAABLgAFFH8NAAIOAAYJ6RDgDAAqAQAOAAYJ6RDgDAAqAQABLgAFFAkJMgAPAN8VAA==.',
Ch='Chad:BAABLgAFFH8yAAIPAAkJ3xUZAwA7AgAPAAkJ3xUZAwA7AgAAAA==.Charlie:BAACLgAFFH8nAAMQAAkJWhzACwAgAgAQAAkJWhzACwAgAgALAAEJQCOeEwBdAAAuAAQKfzgAAxAACQnOJR8IAFMDABAACQnOJR8IAFMDAAsABQnOGXwlAOkAAAAA.Chicken:BAACLgAFFH8LAAMRAAQJ0w3NGQC7AAARAAQJ0w3NGQC7AAASAAEJMwPKIgAvAAAuAAQKfxUAAhEACQnrGDALADECABEACQnrGDALADECAAEuAAUUCQkyAA8A3xUA.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
Cu='Cupid:BAAALgADCgMJBAAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8MAAITAAYJtBT9FgCuAQATAAYJtBT9FgCuAQAuAAQKf2UAAxMACQn5IbkFAFYDABMACQn5IbkFAFYDABQABgl3DghXAN8AAAAA.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn9SAAIVAAkJXhZPBwDtAQAVAAkJXhZPBwDtAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAABLgAECn8nAAMTAAkJ+gnzHACoAAATAAkJ+gnzHACoAAAUAAIJPADcxwACAAAAAA==.Darksabbath:BAAALgADCgUJBQAAAA==.',
De='Deadcontent:BAAALgAFFAMJAwAAAA==.Deathtouch:BAACLgAFFH8HAAMVAAMJPhyZrADHAAAVAAMJPhyZrADHAAAWAAIJSRCYIACDAAAuAAQKfxsAAxUACAlJI7c1ACgCABUACAnKIrc1ACgCABYAAQkSHUo3AEAAAAAA.Demonshard:BAAALgAECgQJBwAAAA==.Devona:BAABLgAECn8kAAMGAAkJZR34IwDlAQAGAAcJtBz4IwDlAQAQAAgJ0w/UdQCCAQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingdangler:BAAALgAECgQJBwAAAA==.Dingledangle:BAABLgAECn9VAAISAAkJKh+4AADAAgASAAkJKh+4AADAAgAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgcJIgAFAHgjAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8YAAIXAAUJWBjRAwBXAQAXAAUJWBjRAwBXAQAuAAQKf0UAAhcACQkUHMkEAD8CABcACQkUHMkEAD8CAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAgABLgAFFAkJNwAYAIsXAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAACLgAFFH8QAAIMAAQJZRRbVgAaAQAMAAQJZRRbVgAaAQAuAAQKfygAAgwACQksEjlMALYBAAwACQksEjlMALYBAAAA.',
Ey='Eyekicku:BAACLgAFFH8JAAIZAAUJvxiTCQAIAQAZAAUJvxiTCQAIAQAuAAQKfyIAAhkACQmvH+cIALcCABkACQmvH+cIALcCAAAA.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCQAAAA==.',
Fl='Flexicus:BAAALgAFFAEJAQABLgAFFAkJJwAKABUbAA==.Flow:BAAALgAECgQJBAABLgAFFAkJMgAPAN8VAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAgAAAA==.',
Go='Goontime:BAAALgAFFAMJBAAAAA==.',
Gr='Graycieden:BAABLgAECn8wAAIaAAkJpxlUAgBSAgAaAAkJpxlUAgBSAgAAAA==.',
Gu='Guldangit:BAACLgAFFH89AAMMAAkJLCK2AQAmAgAMAAkJFiG2AQAmAgAbAAcJCiOeAQCvAQAuAAQKfzIABBsACQn/JYoAAD0DAAwACQkBI2oIAD4DABsACQkSJYoAAD0DABwABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9KAAIdAAkJeBDEGwCfAQAdAAkJeBDEGwCfAQAAAA==.',
Hh='Hhounow:BAAALgAECgEJAgAAAA==.',
Ho='Hod:BAAALgAECgEJAQAAAA==.Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECggJDgAAAA==.Holygrim:BAACLgAFFH9SAAMeAAkJXyYUAADNAwAeAAkJXyYUAADNAwAfAAUJHxUMDgBvAQAuAAQKfx0AAx4ACAljJuABAFcDAB4ACAljJuABAFcDABoAAQk+Cd2PACsAAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9RAAQfAAkJwR/yBQAlAwAfAAkJwR/yBQAlAwAaAAcJ0BtpHQDaAQAeAAQJrQuVXQC8AAAAAA==.Holyshizer:BAAALgADCgUJAgAAAA==.Howii:BAABLgAECn9PAAIOAAkJryWCAQBJAwAOAAkJryWCAQBJAwAAAA==.',
Ig='Igoon:BAABLgAFFH8JAAITAAMJ5xGLXQCRAAATAAMJ5xGLXQCRAAAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIFAAkJZBVeNAALAgAFAAkJZBVeNAALAgAAAA==.',
Je='Jellyfîsh:BAACLgAFFH8GAAMbAAUJGg7vHwBRAAAMAAMJzQbmTgBkAAAbAAIJaBXvHwBRAAAuAAQKfxYAAxsABwnvGkMYAAIBAAwABglbFgmYAAwBABsABgkkEkMYAAIBAAAA.Jeraziah:BAAALgAECgUJEQAAAA==.',
Jo='Johnnyjr:BAABLgAECn8sAAICAAkJkiGXBgD1AgACAAkJkiGXBgD1AgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
Ky='Kynna:BAAALgAECgUJBwAAAA==.',
La='Laggers:BAABLgAECn8jAAIRAAgJdxb7HgBVAQARAAgJdxb7HgBVAQAAAA==.',
Le='Lean:BAAALgAFFAIJAwABLgAFFAkJJwAKABUbAA==.',
Li='Litbit:BAABLgAECn8qAAIDAAkJQgXKlgBLAQADAAkJQgXKlgBLAQAAAA==.Litbitonme:BAAALgAECgQJDgAAAA==.Litllit:BAABLgAECn8WAAMMAAYJyQSaHgCHAAAMAAYJyQSaHgCHAAAbAAMJ/wAuQgAtAAAAAA==.Litt:BAAALgADCgkJCwAAAA==.Liuye:BAAALgAECgYJEgAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8sAAIVAAkJ3CKFCQAjAwAVAAkJ3CKFCQAjAwAAAA==.Lotsofdots:BAAALgAECgEJAQAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.Lustypablo:BAAALgAECgIJAwAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMDAAgJIxC4cQCWAQADAAgJIxC4cQCWAQAKAAEJCAyuFQApAAAAAA==.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgAECgUJBQAAAA==.',
['Mâ']='Mâchine:BAABLgAFFH8OAAMTAAUJMhmEDgBuAQATAAUJMhmEDgBuAQANAAEJJhq2EgBQAAABLgAFFAcJGwAVAIEWAA==.',
['Mò']='Mòjo:BAAALgAECgEJAQAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
No='Noobntrainin:BAAALgADCgYJBgAAAA==.',
Of='Of:BAAALgAECgEJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMdAAkJWxugEQBRAgAdAAkJWxugEQBRAgAYAAQJ6gTj7ABjAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJUQAfAMEfAA==.',
Pe='Pelletpusher:BAAALgAECgEJAQAAAA==.Pendragon:BAAALgAECgQJBgAAAA==.Periodic:BAACLgAFFH8WAAITAAQJwiNrHACJAQATAAQJwiNrHACJAQAuAAQKfy8AAhMACQnkI/QAAJkDABMACQnkI/QAAJkDAAAA.',
Ph='Phatbeatz:BAAALgADCgQJBAAAAA==.',
Pl='Platen:BAABLgAECn8jAAIFAAkJQRK9PwDjAQAFAAkJQRK9PwDjAQAAAA==.',
Po='Potter:BAABLgAECn9FAAIDAAkJbB+qHACwAgADAAkJbB+qHACwAgAAAA==.',
Ra='Raffa:BAABLgAECn8lAAIZAAgJPh1aGQDnAQAZAAgJPh1aGQDnAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8nAAMKAAkJFRt0AABqAgADAAkJFRYxBwChAgAKAAkJVhZ0AABqAgAAAA==.Rapunzel:BAAALgAECgkJDwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMCAAkJ4QSOXwDXAAACAAgJ/wOOXwDXAAAgAAgJqwO0SACpAAAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH80AAISAAkJviFWAADvAgASAAkJviFWAADvAgAuAAQKfy4AAhIACQkQJbYBACQDABIACQkQJbYBACQDAAAA.',
Ro='Rovintis:BAABLgAECn9HAAIgAAkJIhv1BgCLAgAgAAkJIhv1BgCLAgAAAA==.',
Ry='Rynne:BAABLgAECn8tAAQTAAkJeBrZBQAQAgATAAkJeBrZBQAQAgANAAcJ8AcBHAAKAQAUAAEJZwMSwQAdAAAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIJAAkJsSJ+AgBJAwAJAAkJsSJ+AgBJAwAAAA==.Sargeràs:BAAALgAECgIJAgABLgAECggJGQAhAB8bAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn80AAIOAAkJLxfrDgAdAgAOAAkJLxfrDgAdAgAAAA==.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8OAAITAAMJ1hFILQCUAAATAAMJ1hFILQCUAAAuAAQKfxoAAhMACQkNFTVGAJUBABMACQkNFTVGAJUBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJCwAAAA==.',
Si='Silvertiger:BAABLgAECn9MAAMiAAkJ3h9uBgC6AgAiAAkJ3h9uBgC6AgAjAAcJgg+dPABsAQAAAA==.',
Sl='Slabbydabby:BAABLgAFFH8JAAICAAMJ6h97FQDxAAACAAMJ6h97FQDxAAAAAA==.Slabdab:BAAALgAFFAQJBAAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgUJCQABLgAECgkJUQAfAMEfAA==.Sneaki:BAABLgAECn9IAAQkAAkJdyVpBQDcAgAkAAkJ+SNpBQDcAgAhAAgJ/RySBAAzAgAXAAEJsSO5HgBoAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQeAAYJbRfiLACTAQAeAAYJbRfiLACTAQAaAAQJ5gMhTQChAAAfAAIJkQhZTQBdAAAAAA==.',
So='Sorynia:BAABLgAECn9IAAIFAAkJzg/ACwC2AQAFAAkJzg/ACwC2AQAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIYAAMJ5xkPXQDYAAAYAAMJ5xkPXQDYAAAuAAQKfxsAAhgACAmNISsiAIQCABgACAmNISsiAIQCAAAA.Startawar:BAACLgAFFH8FAAIQAAIJxhIQmgCFAAAQAAIJxhIQmgCFAAAuAAQKfyQAAhAACAnHIywWAOQCABAACAnHIywWAOQCAAAA.Stormbeard:BAAALgAECgUJBQABLgAFFAkJJwAQAFocAA==.Stripteased:BAAALgAECgUJCQAAAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAABLgAECn8ZAAMhAAgJHxvWAADLAQAhAAgJHxvWAADLAQAXAAMJfQOTHQBvAAAAAA==.',
Th='Thelandrius:BAAALgAECgQJBAAAAA==.Thurdead:BAAALgAECgUJBQAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAACLgAFFH8JAAMlAAQJUBf1JwAeAQAlAAQJUBf1JwAeAQAmAAEJHgUWUwAxAAAuAAQKfzcAAyUACQnKJf4AANUDACUACQnKJf4AANUDACYAAQmCHgp4AFYAAAAA.',
Va='Valkyrïe:BAAALgAECgkJAQAAAA==.Vauntdk:BAAALgADCgEJAQABLgAFFAYJGQAPAGQhAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAYJGQAPAGQhAA==.',
Ve='Vendetta:BAAALgAECgEJAQABLgAFFAkJMgAPAN8VAA==.Vercyv:BAAALgADCgkJEQAAAA==.Verymelon:BAACLgAFFH8FAAMUAAEJlx57UgBMAAAUAAEJlx57UgBMAAATAAEJBwtjhgAtAAAuAAQKfzcAAxMACQmoIEchAEgCABMACAnjH0chAEgCABQAAgkQGUlyAJQAAAAA.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAIVAAMJABmVlwDfAAAVAAMJABmVlwDfAAAuAAQKfzAAAhUACQkzHxcRAOQCABUACQkzHxcRAOQCAAAA.Vishlock:BAABLgAECn8xAAMbAAkJhBn8BwDsAQAbAAkJhBn8BwDsAQAMAAgJ8w4OlAAwAQAAAA==.',
Vo='Voddie:BAABLgAECn8gAAIUAAkJPgxnNQBlAQAUAAkJPgxnNQBlAQAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAABLgAFFH8PAAITAAUJ2RwUCwCeAQATAAUJ2RwUCwCeAQAAAA==.Walmarthas:BAABLgAECn8YAAIVAAgJxhROTgDYAQAVAAgJxhROTgDYAQAAAA==.Wapta:BAAALgAFFAEJAQABLgAFFAkJJwAKABUbAA==.',
Wi='Winhee:BAAALgADCgYJBgAAAA==.Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAACLgAFFH8IAAInAAMJ3AQAFwCQAAAnAAMJ3AQAFwCQAAAuAAQKfx0AAicACAk7ENwpAGYBACcACAk7ENwpAGYBAAEuAAUUCQkyAA8A3xUA.Woof:BAAALgAECgIJAgAAAA==.',
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
