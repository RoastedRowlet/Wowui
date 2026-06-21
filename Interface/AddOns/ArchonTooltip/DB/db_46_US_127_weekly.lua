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
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aamon:BAAALgAECgEJAgAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgYJDgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8dAAIBAAYJIQIYOgBAAAABAAYJIQIYOgBAAAAAAA==.',
Bi='Biller:BAAALgADCgYJDwAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh0bMgDnAAACAAMJzh0bMgDnAAAuAAQKfx0AAgIACAnWIgIbABUCAAIACAnWIgIbABUCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDwAAAA==.',
Bo='Bootybleaps:BAABLgAFFH8GAAIDAAMJcBKSJgDTAAADAAMJcBKSJgDTAAAAAA==.Bootybsneaks:BAACLgAFFH8jAAIEAAYJziJOCwDlAQAEAAYJziJOCwDlAQAuAAQKfzYAAwQACQn5I9wDAAQDAAQACQn5I9wDAAQDAAUAAQl8FkgmADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIGAAYJ5AsmJwDTAAAGAAYJ5AsmJwDTAAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMHAAYJUBqJLQDIAQAHAAYJUBqJLQDIAQAIAAQJORaPTgDGAAABLgAECggJJAAJABocAA==.Bullievit:BAACLgAFFH8PAAIKAAUJMxTDIQATAQAKAAUJMxTDIQATAQAuAAQKfyQAAwoACQleHYsbAO4BAAoACQleHYsbAO4BAAsABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMMAAkJRBEvCwDHAQAMAAkJRBEvCwDHAQANAAUJ7QB+WgA4AAAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAIOAAYJXyIQPwD4AQAOAAYJXyIQPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgcJEQAAAA==.Chunly:BAABLgAECn8jAAQPAAkJShtOCwCOAgAPAAkJShtOCwCOAgAIAAMJIg4abgBoAAAHAAIJmwQmZABAAAAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8YAAIQAAgJQxFpGQBxAQAQAAgJQxFpGQBxAQAAAA==.Cmorbones:BAAALgAECgEJAQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAPAD4kAA==.Cordi:BAAALgAECgEJAQAAAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMRAAkJcBN0IADWAQARAAkJkBF0IADWAQASAAYJcBBiDwAVAQAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8bAAITAAkJHhvcNABFAgATAAkJHhvcNABFAgAAAA==.Davik:BAABLgAECn8YAAIUAAYJ/gwzRwDyAAAUAAYJ/gwzRwDyAAAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAFFAIJAQAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIVAAgJJw2PlgBHAQAVAAgJJw2PlgBHAQAAAA==.',
Dr='Dracarsynimz:BAEALgAFFAIJAgAAAQ==.Dracene:BAABLgAECn8bAAIWAAgJBQiCJADxAAAWAAgJBQiCJADxAAAAAA==.Dragosa:BAAALgAECgMJBgABLgAFFAIJBAAXAAAAAA==.Driver:BAAALgAFFAMJAgABLgAFFAUJDwAYALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAXAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMHAAkJvB4OBQAUAwAHAAkJvB4OBQAUAwAIAAEJZQrEhQA7AAAAAA==.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMZAAgJkxQ8HwAJAgAZAAgJkxQ8HwAJAgAVAAEJ8QTuvAElAAAAAA==.',
Gb='Gb:BAACLgAFFH8NAAMUAAQJ8hpzIwDaAAAUAAMJsBlzIwDaAAAaAAMJyQ+qMQDIAAAuAAQKfygABBoACQlKHVcIAPACABoACQlKHVcIAPACABQACAnlHAMOAKMCABsAAgk5CDJxAGIAAAAA.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAwAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAPAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8PAAIcAAQJZyBGBAAmAQAcAAQJZyBGBAAmAQAuAAQKf0oAAhwACQmIJWkCAGoDABwACQmIJWkCAGoDAAAA.',
Im='Imnotyourdad:BAAALgAECgEJAQAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAcAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIPAAcJPiQcEAB+AgAPAAcJPiQcEAB+AgAAAA==.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8UAAILAAYJwA/EHAB0AQALAAYJwA/EHAB0AQAuAAQKfzEAAwsACQmzIcAFAFsDAAsACQmzIcAFAFsDAAoAAQkAAHGwAAAAAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIVAAYJCBUDJAB4AQAVAAYJCBUDJAB4AQAuAAQKfygAAhUACQlGIc4XALQCABUACQlGIc4XALQCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAIUAAgJJx1MAgCQAgAUAAgJJx1MAgCQAgAuAAQKfzcAAhQACQklJkABAMADABQACQklJkABAMADAAAA.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIdAAYJMQ71vAACAQAdAAYJMQ71vAACAQAAAA==.Lovelypwr:BAABLgAECn8+AAMUAAkJdROPHADgAQAUAAkJdROPHADgAQAaAAEJSwwefQAvAAAAAA==.',
Ma='Mannera:BAABLgAFFH8MAAIaAAQJtBeIJAApAQAaAAQJtBeIJAApAQAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIQAAkJZiIlBgCtAgAQAAkJZiIlBgCtAgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIQAAkJHx6/BQC3AgAQAAkJHx6/BQC3AgABLgAFFAQJDwANAMAaAA==.',
Me='Melarac:BAABLgAECn8XAAQLAAgJMws+awDzAAALAAcJ2wc+awDzAAAKAAYJjQlaUADMAAAJAAUJ1AbnVgBeAAAAAA==.',
Mi='Minibow:BAAALgAECgQJBgAAAA==.Minimagic:BAACLgAFFH8XAAMTAAUJNRyGUwA2AQATAAUJNRyGUwA2AQAeAAEJBAhEBwBAAAAuAAQKfzwAAhMACQlIJMIKACMDABMACQlIJMIKACMDAAAA.',
Mo='Mogh:BAAALgAECgQJBAAAAA==.Monker:BAABLgAECn8hAAQHAAgJzh4qHAA3AgAHAAcJrh4qHAA3AgAIAAUJ7htEMQA9AQAPAAYJgBUQPgAjAQAAAA==.Mookake:BAAALgADCgMJAwAAAA==.',
Mu='Muth:BAAALgAECgYJDAAAAA==.Muthra:BAAALgAECgEJAQABLgAECgYJDAAXAAAAAA==.Muthroc:BAAALgAECgEJAgABLgAECgYJDAAXAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAITAAIJ8xuSmACbAAATAAIJ8xuSmACbAAAuAAQKfzgAAhMACAlfI/sgAPACABMACAlfI/sgAPACAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgcJEwAAAA==.',
Ni='Niftyshiftyy:BAAALgADCgMJAwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIRAAQJpBS5KgAcAQARAAQJpBS5KgAcAQAuAAQKfxkAAhEACQkAI6QDADMDABEACQkAI6QDADMDAAEuAAUUCQkvABEAUxoA.Nitalzit:BAAALgAECgQJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECggJIQAOAH0WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAPAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgAUAHUTAA==.',
Om='Omruc:BAAALgAECgEJAQABLgAECggJFgAZAJMUAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJBgAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIdAAQJ1gQOkADrAAAdAAQJ1gQOkADrAAAuAAQKfx4AAh0ACQkkFDpJAOYBAB0ACQkkFDpJAOYBAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.',
Ph='Pharrel:BAAALgADCgMJAwAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAPAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMDAAgJ2R7wBwB3AgADAAgJ2R7wBwB3AgACAAEJ7RlumQBAAAAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgAECgUJBQAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgYJDAAXAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAFFAEJAQABLgAFFAYJFAALAMAPAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8VAAICAAcJLBWlLwCQAQACAAcJLBWlLwCQAQAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAGAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJEAAAAA==.',
Sh='Shammtastiç:BAABLgAECn8/AAIfAAkJIhhdGgAOAgAfAAkJIhhdGgAOAgAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAAUACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMdAAgJsg18eQBxAQAdAAgJsg18eQBxAQAMAAQJ/AVpMgBTAAAAAA==.',
Sn='Sncak:BAACLgAFFH8nAAMEAAcJoxmsCQAGAgAEAAcJoxmsCQAGAgAFAAEJOQ08BgBcAAAuAAQKfyoAAwQACQkPJCgCAJADAAQACQkPJCgCAJADAAUABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIGAAUJaReDBgBFAQAGAAUJaReDBgBFAQAuAAQKfxsAAgYACQn2ITsEAN0CAAYACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8wAAMSAAgJyRlBAABFAQASAAcJJh1BAABFAQARAAQJawwvZQCrAAABLgAFFAQJDwANAMAaAA==.Syrieal:BAACLgAFFH8PAAINAAQJwBpkFwAuAQANAAQJwBpkFwAuAQAuAAQKf0MAAw0ACQnUH9UGALACAA0ACQnAHtUGALACAAwACAlmGKEIAAICAAAA.',
Ta='Taiyla:BAACLgAFFH8KAAITAAQJoQb/cgD6AAATAAQJoQb/cgD6AAAuAAQKfz4AAhMACQmmFrsxAFICABMACQmmFrsxAFICAAAA.Talithiala:BAAALgAECgcJEgAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMHAAgJExkqEwAzAgAHAAgJExkqEwAzAgAPAAcJigq3XgCdAAAAAA==.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8ZAAIGAAgJzg8sFgBnAQAGAAgJzg8sFgBnAQAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJCQABLgAFFAYJFAALAMAPAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECgkJGwATAB4bAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQAgAAkJSgvvVgArAQAhAAcJBw3yGwAhAQAAAA==.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORnEFQBjAQAhAAYJORnEFQBjAQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKAAbABwcAA==.Unilock:BAACLgAFFH8KAAIYAAQJ8RQ6SwAwAQAYAAQJ8RQ6SwAwAQAuAAQKfyAAAhgACQmyGZgoADkCABgACQmyGZgoADkCAAEuAAUUBwkoABsAHBwA.Unipray:BAACLgAFFH8oAAMbAAcJHByNBQAJAgAbAAcJHByNBQAJAgAUAAUJnxpQFQA6AQAuAAQKfycAAxsACQmwIlABAG8DABsACQmwIlABAG8DABQABwnrHloeANMBAAAA.',
Va='Vamperella:BAABLgAECn8ZAAIeAAYJcgENFABMAAAeAAYJcgENFABMAAAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgAECgEJAQABLgAFFAYJFAALAMAPAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAgJLAAdADUlAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAXAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRavAgAfAgAiAAkJGRavAgAfAgAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIcAAgJARBLVACmAQAcAAgJARBLVACmAQAAAA==.',
Yo='You:BAABLgAECn8kAAINAAkJsxcEFgC6AQANAAkJsxcEFgC6AQAAAA==.',
Yu='Yulogee:BAABLgAFFH8IAAMNAAMJMB7zHgDvAAANAAMJMB7zHgDvAAAdAAEJ4wJdJAEyAAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAXAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJBwAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxVQJQC+AQAfAAgJlxVQJQC+AQAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
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
