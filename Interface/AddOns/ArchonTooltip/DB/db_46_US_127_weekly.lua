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

local lookup = {'Unknown-Unknown','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Warlock-Demonology','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Mage-Arcane','Evoker-Preservation','DemonHunter-Havoc','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aamon:BAAALgAECgEJAgAAAA==.Aarius:BAAALgAECgYJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Ak='Akrøma:BAAALgADCgQJAwAAAA==.',
Al='Alex:BAAALgAFFAQJDAABLgAFFAgJEgABAAAAAQ==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Ar='Archon:BAAALgAECgEJAQAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgkJEgAAAA==.Bazthrax:BAAALgAECgYJDwAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8dAAICAAYJIQIaOgBAAAACAAYJIQIaOgBAAAAAAA==.',
Bi='Biller:BAAALgAECgIJAgAAAA==.',
Bl='Blade:BAACLgAFFH8KAAIDAAMJzh0XMgDnAAADAAMJzh0XMgDnAAAuAAQKfx0AAgMACAnWIgIbABUCAAMACAnWIgIbABUCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Blitzed:BAAALgAECgIJAwABLgAFFAMJCgADAM4dAA==.Bluemoon:BAAALgADCgkJHgAAAA==.',
Bo='Bootybleaps:BAABLgAFFH8LAAMDAAMJYhXTGQDUAAADAAMJvBTTGQDUAAAEAAMJcBKKJgDTAAAAAA==.Bootybsneaks:BAACLgAFFH8oAAIFAAgJPh9FCwDlAQAFAAgJPh9FCwDlAQAuAAQKfzYAAwUACQn5I9wDAAQDAAUACQn5I9wDAAQDAAYAAQl8FkkmADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Breakingwind:BAAALgAECgEJAQAAAA==.Brynhild:BAABLgAECn8ZAAIHAAYJ5AsmJwDTAAAHAAYJ5AsmJwDTAAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMIAAYJUBqMLQDIAQAIAAYJUBqMLQDIAQAJAAQJORaQTgDGAAABLgAECggJJAAKABocAA==.Bullievit:BAACLgAFFH8RAAILAAUJMxS8IQATAQALAAUJMxS8IQATAQAuAAQKfyQAAwsACQleHY0bAO4BAAsACQleHY0bAO4BAAwABAktBTyeAI4AAAAA.Bullizaria:BAABLgAFFH8FAAIIAAEJYhX+PwA6AAAIAAEJYhX+PwA6AAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMNAAkJRBEwCwDHAQANAAkJRBEwCwDHAQAOAAUJ7QB8WgA4AAAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgADAM4dAA==.Chaozz:BAABLgAECn8YAAIPAAYJXyIQPwD4AQAPAAYJXyIQPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgcJEwAAAA==.Chunly:BAACLgAFFH8IAAIQAAMJFA/WDwC8AAAQAAMJFA/WDwC8AAAuAAQKfywABBAACQm+G7YKAJgCABAACQm+G7YKAJgCAAgABQlwFJQQACIBAAkAAwkiDh1uAGgAAAAA.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8ZAAIRAAgJbBFpGQBxAQARAAgJbBFpGQBxAQAAAA==.Cmorbones:BAAALgAECgEJAQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAQAD4kAA==.Cordi:BAAALgAECgEJAgAAAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMSAAkJcBNzIADWAQASAAkJkBFzIADWAQATAAYJcBBiDwAVAQAAAA==.Cropop:BAAALgAFFAEJAQAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8gAAIUAAkJ9xvaNABFAgAUAAkJ9xvaNABFAgAAAA==.Davik:BAABLgAECn8ZAAIVAAcJug44RwDyAAAVAAcJug44RwDyAAAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAFFAMJAwAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIWAAgJJw2MlgBHAQAWAAgJJw2MlgBHAQAAAA==.',
Dr='Dracarsynimz:BAEALgAFFAIJAgAAAQ==.Dracene:BAABLgAECn8bAAIXAAgJBQiCJADxAAAXAAgJBQiCJADxAAAAAA==.Dragosa:BAAALgAECgMJBgABLgAFFAIJBAABAAAAAA==.Driver:BAEALgAFFAMJAgABLgAFFAUJEQAYALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fa='Faìladin:BAAALgAECgIJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAABAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMIAAkJvB4OBQAUAwAIAAkJvB4OBQAUAwAJAAEJZQrEhQA7AAAAAA==.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Fu='Fughost:BAAALgAECgMJAQAAAA==.',
Ga='Galyn:BAAALgAECgEJAQABLgAECgkJIAAUAPcbAA==.Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMZAAgJkxQ7HwAJAgAZAAgJkxQ7HwAJAgAWAAEJ8QTxvAElAAAAAA==.',
Gb='Gb:BAACLgAFFH8NAAMVAAQJ8hp0IwDaAAAVAAMJsBl0IwDaAAAaAAMJyQ+mMQDIAAAuAAQKfygABBoACQlKHVcIAPACABoACQlKHVcIAPACABUACAnlHAMOAKMCABsAAgk5CDJxAGIAAAAA.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAABLgAFFH8IAAIUAAMJeQRwSgCkAAAUAAMJeQRwSgCkAAAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAQAIQWAA==.',
Hu='Humanmatt:BAAALgAECgUJBwAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAFFAEJAQAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8SAAIcAAUJJCGxKwBbAQAcAAUJJCGxKwBbAQAuAAQKf1kAAhwACQnNJWgCAGoDABwACQnNJWgCAGoDAAAA.',
Im='Imnotyourdad:BAAALgAECgcJEwAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAFFAEJAQABLgAFFAMJBgAdAIsOAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAcAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.Kanlies:BAAALgAECgEJAQAAAA==.',
Ke='Keg:BAABLgAECn8dAAIQAAcJPiQcEAB+AgAQAAcJPiQcEAB+AgAAAA==.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovo:BAAALgAECgYJCwABLgAFFAcJHQAMALEOAA==.Kovowolf:BAACLgAFFH8dAAIMAAcJsQ4wCwCHAQAMAAcJsQ4wCwCHAQAuAAQKfzIAAwwACQmzIcAFAFsDAAwACQmzIcAFAFsDAAsAAQkAAHmwAAAAAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIWAAYJCBXuIwB4AQAWAAYJCBXuIwB4AQAuAAQKfygAAhYACQlGIc4XALQCABYACQlGIc4XALQCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemonhead:BAAALgADCgEJAQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH9GAAIVAAkJhR9cAQDrAgAVAAkJhR9cAQDrAgAuAAQKfzcAAhUACQklJkABAMADABUACQklJkABAMADAAAA.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Longfoot:BAAALgADCgIJAgAAAA==.Lotieos:BAABLgAECn8cAAIeAAYJMQ77vAACAQAeAAYJMQ77vAACAQAAAA==.Lovelypwr:BAABLgAECn8+AAMVAAkJdROPHADgAQAVAAkJdROPHADgAQAaAAEJSwwgfQAvAAAAAA==.',
Ma='Mannera:BAABLgAFFH8RAAIaAAUJlhcOEgAbAQAaAAUJlhcOEgAbAQAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIRAAkJZiIjBgCtAgARAAkJZiIjBgCtAgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAACLgAFFH8JAAMRAAMJOQ/DEQCZAAARAAMJSg7DEQCZAAADAAIJOgzCJwCFAAAuAAQKfxsAAxEACQkfHr0FALcCABEACQkfHr0FALcCAAMAAQk/HKAiAFIAAAEuAAUUBQkcAA4AIh0A.',
Me='Melarac:BAABLgAECn8XAAQMAAgJMws7awDzAAAMAAcJ2wc7awDzAAALAAYJjQliUADMAAAKAAUJ1AbpVgBeAAAAAA==.',
Mi='Minibow:BAAALgAECgYJDAAAAA==.Minimagic:BAACLgAFFH8XAAMUAAUJNRxuUwA2AQAUAAUJNRxuUwA2AQAfAAEJBAhBBwBAAAAuAAQKfz4AAhQACQm6JL8KACMDABQACQm6JL8KACMDAAAA.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monkbenice:BAAALgAECgQJBgAAAA==.Monker:BAABLgAECn8hAAQIAAgJzh4qHAA3AgAIAAcJrh4qHAA3AgAJAAUJ7htHMQA9AQAQAAYJgBUQPgAjAQAAAA==.Mookake:BAAALgADCgMJAwAAAA==.Morden:BAAALgAECggJBwAAAA==.',
Mu='Muth:BAAALgAFFAEJAQAAAA==.Muthra:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Muthroc:BAAALgAECgUJCQABLgAFFAEJAQABAAAAAA==.Muthunter:BAAALgAECgEJAgABLgAFFAEJAQABAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAIUAAIJ8xuDmACbAAAUAAIJ8xuDmACbAAAuAAQKfzgAAhQACAlfI/sgAPACABQACAlfI/sgAPACAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Never:BAACLgAFFH9ZAAMSAAkJtB3WAwDbAgASAAkJtB3WAwDbAgAgAAkJ1RksAQBCAgAuAAQKfyMABCAACQm4H/gBAFwDACAACQm4H/gBAFwDABIACQmoHREMAJkCABMAAwl7HB8nAOkAAAAA.Nezukokamado:BAACLgAFFH8JAAIhAAQJjgmyDQDSAAAhAAQJjgmyDQDSAAAuAAQKfxYAAiEACAktCuY2AN8AACEACAktCuY2AN8AAAAA.',
Ni='Niftyshiftyy:BAABLgAECn8aAAIKAAcJMRHIBgA3AQAKAAcJMRHIBgA3AQAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8JAAMSAAQJSRW0KgAcAQASAAQJpBS0KgAcAQATAAIJixctBQCKAAAuAAQKfxkAAhIACQkAI6QDADMDABIACQkAI6QDADMDAAEuAAUUCQlCABIAQR0A.Nitalzit:BAAALgAECgQJBwAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIgAPAH0WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAQAD4kAA==.',
Oa='Oakshion:BAAALgAECgEJAgAAAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgAVAHUTAA==.',
Om='Omruc:BAAALgAECgEJAQABLgAECggJFgAZAJMUAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgUJCAAAAA==.',
Oz='Ozultima:BAAALgAECgEJAQAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIeAAQJ1gQMkADrAAAeAAQJ1gQMkADrAAAuAAQKfx8AAh4ACQkkFD5JAOYBAB4ACQkkFD5JAOYBAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.Palzara:BAAALgAECgUJBQAAAA==.',
Ph='Pharrel:BAAALgADCgMJAwAAAA==.',
Po='Poplockdrop:BAAALgAECgYJAwAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAQAD4kAA==.',
Ra='Rabioso:BAAALgAECgEJAQAAAA==.Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMEAAgJ2R7wBwB3AgAEAAgJ2R7wBwB3AgADAAEJ7RlwmQBAAAAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgAECgUJDwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAFFAEJAQABAAAAAA==.Roidsnmolly:BAAALgAECggJBQAAAA==.Roksharu:BAAALgAFFAEJAQABLgAECggJGgAHAM4PAA==.',
Ru='Runa:BAAALgAFFAEJAgABLgAFFAcJHQAMALEOAA==.',
Sa='Sadie:BAAALgAECgUJBAAAAA==.Sahlberg:BAABLgAECn8VAAIDAAcJLBWmLwCQAQADAAcJLBWmLwCQAQAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAHAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAFFAEJAgAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJEAAAAA==.',
Sh='Shaihardt:BAEALgAECgQJBQABLgAFFAEJBAABAAAAAA==.Shammtastiç:BAABLgAECn9OAAIiAAkJWRjfBADIAQAiAAkJWRjfBADIAQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAkJRgAVAIUfAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sigrún:BAAALgADCgIJAgAAAA==.Sinley:BAABLgAECn8sAAMeAAkJBw9+eQBxAQAeAAkJ9A1+eQBxAQANAAQJ+wtoMgBTAAAAAA==.',
Sn='Sncak:BAACLgAFFH8pAAMFAAgJ7xefCQAGAgAFAAgJ7xefCQAGAgAGAAEJOQ08BgBcAAAuAAQKfyoAAwUACQkPJCgCAJADAAUACQkPJCgCAJADAAYABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8QAAIHAAYJ9Bh7AgBmAQAHAAYJ9Bh7AgBmAQAuAAQKfxsAAgcACQn2ITsEAN0CAAcACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8yAAMTAAgJyRlBBgDtAQATAAcJJh1BBgDtAQASAAYJJw4yZQCrAAABLgAFFAUJHAAOACIdAA==.Syrieal:BAACLgAFFH8cAAMOAAUJIh1cFwAuAQAOAAUJIh1cFwAuAQANAAMJcArLDgC7AAAuAAQKf00AAw4ACQlSIdIGALACAA4ACQnwH9IGALACAA0ACQkwGqEIAAICAAAA.',
Ta='Taichari:BAAALgAECgUJCgAAAA==.Taiyla:BAACLgAFFH8WAAIUAAUJ+AmTMwD6AAAUAAUJ+AmTMwD6AAAuAAQKfz4AAhQACQmmFrkxAFICABQACQmmFrkxAFICAAAA.Talithiala:BAAALgAECgcJEgAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMIAAgJExkqEwAzAgAIAAgJExkqEwAzAgAQAAcJigq1XgCdAAAAAA==.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Teikou:BAAALgADCgYJBgABLgAFFAUJEgAcACQhAA==.Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8aAAIHAAgJzg8vFgBnAQAHAAgJzg8vFgBnAQAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJCgABLgAFFAcJHQAMALEOAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECgkJIAAUAPcbAA==.',
Tr='Trip:BAABLgAECn8kAAMjAAkJSgvvVgArAQAjAAkJSgvvVgArAQAkAAcJBw3zGwAhAQAAAA==.',
Ts='Tsabotavok:BAAALgADCgYJDAAAAA==.Tsty:BAAALgADCgQJBQAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8YAAIkAAYJ0B7EFQBjAQAkAAYJ0B7EFQBjAQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAkJLwAbAIUaAA==.Unilock:BAACLgAFFH8KAAIYAAQJ8RQfSwAwAQAYAAQJ8RQfSwAwAQAuAAQKfyAAAhgACQmyGZcoADkCABgACQmyGZcoADkCAAEuAAUUCQkvABsAhRoA.Unipray:BAACLgAFFH8vAAMbAAkJhRqKBQAJAgAbAAkJhRqKBQAJAgAVAAUJnxpOFQA6AQAuAAQKfykAAxsACQmwIlABAG8DABsACQmwIlABAG8DABUABwnrHloeANMBAAAA.',
Us='Ustom:BAAALgADCgQJBgAAAA==.',
Va='Vamperella:BAABLgAECn8aAAIfAAYJkAEOFABMAAAfAAYJkAEOFABMAAAAAA==.',
Ve='Velkor:BAAALgAECgYJEAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgkJEgAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJEgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffhawk:BAAALgAECgEJAQAAAA==.Wolffspirit:BAAALgAECgUJBwABLgAFFAcJHQAMALEOAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAkJRQAeAJclAA==.',
Ye='Yeet:BAAALgAECgQJCAAAAA==.Yefercas:BAAALgAFFAEJAQABLgAFFAIJAwABAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIlAAkJGRavAgAfAgAlAAkJGRavAgAfAgAAAA==.',
Yl='Ylvis:BAACLgAFFH8QAAIcAAQJywvWMADhAAAcAAQJywvWMADhAAAuAAQKfzYAAhwACAn+EUlUAKYBABwACAn+EUlUAKYBAAAA.',
Yo='You:BAABLgAECn8kAAIOAAkJsxcFFgC6AQAOAAkJsxcFFgC6AQAAAA==.',
Yu='Yulogee:BAABLgAFFH8IAAMOAAMJMB7sHgDvAAAOAAMJMB7sHgDvAAAeAAEJ4wJVJAEyAAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCQAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIiAAgJlxVOJQC+AQAiAAgJlxVOJQC+AQAAAA==.Zerofuntion:BAAALgAECgEJAQAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
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
