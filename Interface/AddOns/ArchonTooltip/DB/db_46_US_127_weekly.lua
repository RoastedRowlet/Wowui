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

local lookup = {'Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aamon:BAAALgAECgEJAgAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgYJDwAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8dAAIBAAYJIQIaOgBAAAABAAYJIQIaOgBAAAAAAA==.',
Bi='Biller:BAAALgADCggJEQAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh0XMgDnAAACAAMJzh0XMgDnAAAuAAQKfx0AAgIACAnWIgIbABUCAAIACAnWIgIbABUCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCggJEQAAAA==.',
Bo='Bootybleaps:BAABLgAFFH8JAAMCAAMJYhVkCgDuAAACAAMJvBRkCgDuAAADAAMJcBKKJgDTAAAAAA==.Bootybsneaks:BAACLgAFFH8kAAIEAAcJuCJFCwDlAQAEAAcJuCJFCwDlAQAuAAQKfzYAAwQACQn5I9wDAAQDAAQACQn5I9wDAAQDAAUAAQl8FkkmADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIGAAYJ5AsmJwDTAAAGAAYJ5AsmJwDTAAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMHAAYJUBqMLQDIAQAHAAYJUBqMLQDIAQAIAAQJORaQTgDGAAABLgAECggJJAAJABocAA==.Bullievit:BAACLgAFFH8QAAIKAAUJMxS8IQATAQAKAAUJMxS8IQATAQAuAAQKfyQAAwoACQleHY0bAO4BAAoACQleHY0bAO4BAAsABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMMAAkJRBEwCwDHAQAMAAkJRBEwCwDHAQANAAUJ7QB8WgA4AAAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAIOAAYJXyIQPwD4AQAOAAYJXyIQPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgcJEwAAAA==.Chunly:BAABLgAECn8pAAQPAAkJvhu2CgCYAgAPAAkJvhu2CgCYAgAHAAQJJhSwCADkAAAIAAMJIg4dbgBoAAAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8ZAAIQAAgJbBFpGQBxAQAQAAgJbBFpGQBxAQAAAA==.Cmorbones:BAAALgAECgEJAQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAPAD4kAA==.Cordi:BAAALgAECgEJAQAAAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMRAAkJcBNzIADWAQARAAkJkBFzIADWAQASAAYJcBBiDwAVAQAAAA==.Cropop:BAAALgAECgcJCwAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8cAAITAAkJHhvaNABFAgATAAkJHhvaNABFAgAAAA==.Davik:BAABLgAECn8YAAIUAAYJ/gw4RwDyAAAUAAYJ/gw4RwDyAAAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAFFAIJAQAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIVAAgJJw2MlgBHAQAVAAgJJw2MlgBHAQAAAA==.',
Dr='Dracarsynimz:BAEALgAFFAIJAgAAAQ==.Dracene:BAABLgAECn8bAAIWAAgJBQiCJADxAAAWAAgJBQiCJADxAAAAAA==.Dragosa:BAAALgAECgMJBgABLgAFFAIJBAAXAAAAAA==.Driver:BAEALgAFFAMJAgABLgAFFAUJEAAYALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fa='Faìladin:BAAALgAECgEJAQAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAXAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMHAAkJvB4OBQAUAwAHAAkJvB4OBQAUAwAIAAEJZQrEhQA7AAAAAA==.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Galyn:BAAALgAECgEJAQABLgAECgkJHAATAB4bAA==.Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMZAAgJkxQ7HwAJAgAZAAgJkxQ7HwAJAgAVAAEJ8QTxvAElAAAAAA==.',
Gb='Gb:BAACLgAFFH8NAAMUAAQJ8hp0IwDaAAAUAAMJsBl0IwDaAAAaAAMJyQ+mMQDIAAAuAAQKfygABBoACQlKHVcIAPACABoACQlKHVcIAPACABQACAnlHAMOAKMCABsAAgk5CDJxAGIAAAAA.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAwAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAPAIQWAA==.',
Hu='Humanmatt:BAAALgAECgUJBwAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8QAAIcAAQJZyDrDQAvAQAcAAQJZyDrDQAvAQAuAAQKf1EAAhwACQnFJWgCAGoDABwACQnFJWgCAGoDAAAA.',
Im='Imnotyourdad:BAAALgAECgcJCAAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAcAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIPAAcJPiQcEAB+AgAPAAcJPiQcEAB+AgAAAA==.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8UAAILAAYJwA+/HAB0AQALAAYJwA+/HAB0AQAuAAQKfzEAAwsACQmzIcAFAFsDAAsACQmzIcAFAFsDAAoAAQkAAHmwAAAAAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIVAAYJCBXuIwB4AQAVAAYJCBXuIwB4AQAuAAQKfygAAhUACQlGIc4XALQCABUACQlGIc4XALQCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8kAAIUAAgJJx1NAgCQAgAUAAgJJx1NAgCQAgAuAAQKfzcAAhQACQklJkABAMADABQACQklJkABAMADAAAA.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Longfoot:BAAALgADCgEJAQAAAA==.Lotieos:BAABLgAECn8cAAIdAAYJMQ77vAACAQAdAAYJMQ77vAACAQAAAA==.Lovelypwr:BAABLgAECn8+AAMUAAkJdROPHADgAQAUAAkJdROPHADgAQAaAAEJSwwgfQAvAAAAAA==.',
Ma='Mannera:BAABLgAFFH8MAAIaAAQJtBd9JAApAQAaAAQJtBd9JAApAQAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIQAAkJZiIjBgCtAgAQAAkJZiIjBgCtAgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIQAAkJHx69BQC3AgAQAAkJHx69BQC3AgABLgAFFAQJEwANACIdAA==.',
Me='Melarac:BAABLgAECn8XAAQLAAgJMws7awDzAAALAAcJ2wc7awDzAAAKAAYJjQliUADMAAAJAAUJ1AbpVgBeAAAAAA==.',
Mi='Minibow:BAAALgAECgQJBwAAAA==.Minimagic:BAACLgAFFH8XAAMTAAUJNRxuUwA2AQATAAUJNRxuUwA2AQAeAAEJBAhBBwBAAAAuAAQKfz4AAhMACQm6JL8KACMDABMACQm6JL8KACMDAAAA.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monker:BAABLgAECn8hAAQHAAgJzh4qHAA3AgAHAAcJrh4qHAA3AgAIAAUJ7htHMQA9AQAPAAYJgBUQPgAjAQAAAA==.Mookake:BAAALgADCgMJAwAAAA==.',
Mu='Muth:BAAALgAECgYJDAAAAA==.Muthra:BAAALgAECgEJAQABLgAECgYJDAAXAAAAAA==.Muthroc:BAAALgAECgQJBQABLgAECgYJDAAXAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAITAAIJ8xuDmACbAAATAAIJ8xuDmACbAAAuAAQKfzgAAhMACAlfI/sgAPACABMACAlfI/sgAPACAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgcJEwAAAA==.',
Ni='Niftyshiftyy:BAAALgAECgcJBwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8JAAMRAAQJSRW0KgAcAQARAAQJpBS0KgAcAQASAAIJixfSAQCfAAAuAAQKfxkAAhEACQkAI6QDADMDABEACQkAI6QDADMDAAEuAAUUCQk0ABEAUxoA.Nitalzit:BAAALgAECgQJBwAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIgAOAH0WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAPAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgAUAHUTAA==.',
Om='Omruc:BAAALgAECgEJAQABLgAECggJFgAZAJMUAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJBgAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIdAAQJ1gQMkADrAAAdAAQJ1gQMkADrAAAuAAQKfx8AAh0ACQkkFD5JAOYBAB0ACQkkFD5JAOYBAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.',
Ph='Pharrel:BAAALgADCgMJAwAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAPAD4kAA==.',
Ra='Rabioso:BAAALgAECgEJAQAAAA==.Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMDAAgJ2R7wBwB3AgADAAgJ2R7wBwB3AgACAAEJ7RlwmQBAAAAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgAECgUJCQAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgYJDAAXAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAFFAEJAQABLgAFFAYJFAALAMAPAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8VAAICAAcJLBWmLwCQAQACAAcJLBWmLwCQAQAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAGAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAFFAEJAQAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJEAAAAA==.',
Sh='Shammtastiç:BAABLgAECn8/AAIfAAkJIhhcGgAOAgAfAAkJIhhcGgAOAgAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJJAAUACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sigrún:BAAALgADCgIJAgAAAA==.Sinley:BAABLgAECn8qAAMdAAgJwg1+eQBxAQAdAAgJwg1+eQBxAQAMAAQJ/AVoMgBTAAAAAA==.',
Sn='Sncak:BAACLgAFFH8nAAMEAAcJoxmfCQAGAgAEAAcJoxmfCQAGAgAFAAEJOQ08BgBcAAAuAAQKfyoAAwQACQkPJCgCAJADAAQACQkPJCgCAJADAAUABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIGAAUJaReCBgBFAQAGAAUJaReCBgBFAQAuAAQKfxsAAgYACQn2ITsEAN0CAAYACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8yAAMSAAgJyRlBBgDtAQASAAcJJh1BBgDtAQARAAYJJw4yZQCrAAABLgAFFAQJEwANACIdAA==.Syrieal:BAACLgAFFH8TAAINAAQJIh1sBgAUAQANAAQJIh1sBgAUAQAuAAQKf0QAAw0ACQnUH9IGALACAA0ACQnAHtIGALACAAwACQkSF6EIAAICAAAA.',
Ta='Taichari:BAAALgAECgUJBQAAAA==.Taiyla:BAACLgAFFH8OAAITAAQJLgiJGgD6AAATAAQJLgiJGgD6AAAuAAQKfz4AAhMACQmmFrkxAFICABMACQmmFrkxAFICAAAA.Talithiala:BAAALgAECgcJEgAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMHAAgJExkqEwAzAgAHAAgJExkqEwAzAgAPAAcJigq1XgCdAAAAAA==.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8ZAAIGAAgJzg8vFgBnAQAGAAgJzg8vFgBnAQAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJCgABLgAFFAYJFAALAMAPAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECgkJHAATAB4bAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQAgAAkJSgvvVgArAQAhAAcJBw3zGwAhAQAAAA==.',
Ts='Tsty:BAAALgADCgQJBQAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORnEFQBjAQAhAAYJORnEFQBjAQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKgAbABwcAA==.Unilock:BAACLgAFFH8KAAIYAAQJ8RQfSwAwAQAYAAQJ8RQfSwAwAQAuAAQKfyAAAhgACQmyGZcoADkCABgACQmyGZcoADkCAAEuAAUUBwkqABsAHBwA.Unipray:BAACLgAFFH8qAAMbAAcJHByKBQAJAgAbAAcJHByKBQAJAgAUAAUJnxpOFQA6AQAuAAQKfykAAxsACQmwIlABAG8DABsACQmwIlABAG8DABQABwnrHloeANMBAAAA.',
Va='Vamperella:BAABLgAECn8aAAIeAAYJkAEOFABMAAAeAAYJkAEOFABMAAAAAA==.',
Ve='Velkor:BAAALgAECgYJDQAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgAECgEJAgABLgAFFAYJFAALAMAPAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAgJMQAdADUlAA==.',
Ye='Yefercas:BAAALgAFFAEJAQAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRavAgAfAgAiAAkJGRavAgAfAgAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIcAAgJARBJVACmAQAcAAgJARBJVACmAQAAAA==.',
Yo='You:BAABLgAECn8kAAINAAkJsxcFFgC6AQANAAkJsxcFFgC6AQAAAA==.',
Yu='Yulogee:BAABLgAFFH8IAAMNAAMJMB7sHgDvAAANAAMJMB7sHgDvAAAdAAEJ4wJVJAEyAAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAXAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCAAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxVOJQC+AQAfAAgJlxVOJQC+AQAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
Zu='Zumadin:BAAALgADCgkJBwAAAA==.Zummev:BAAALgADCgYJBAAAAA==.',
['Æs']='Æsham:BAAALgADCgQJBAAAAA==.',
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
