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

local lookup = {'Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Warlock-Demonology','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aamon:BAAALgAECgEJAQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgUJCwAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8aAAIBAAYJYAHhOABAAAABAAYJYAHhOABAAAAAAA==.',
Bi='Biller:BAAALgADCgYJDwAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh2MMADnAAACAAMJzh2MMADnAAAuAAQKfx0AAgIACAnWIm8aABgCAAIACAnWIm8aABgCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDwAAAA==.',
Bo='Bootybleaps:BAAALgAFFAMJAwAAAA==.Bootybsneaks:BAACLgAFFH8iAAIDAAYJziJfCgDoAQADAAYJziJfCgDoAQAuAAQKfzUAAwMACQkiI+QEAOgCAAMACQkiI+QEAOgCAAQAAQl8FrMlADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIFAAYJ5As4JgDTAAAFAAYJ5As4JgDTAAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMGAAYJUBpiLADHAQAGAAYJUBpiLADHAQAHAAQJORa+TQDGAAABLgAECggJJAAIABocAA==.Bullievit:BAACLgAFFH8OAAIJAAUJMxSnIAAUAQAJAAUJMxSnIAAUAQAuAAQKfyQAAwkACQleHTkbAO4BAAkACQleHTkbAO4BAAoABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMLAAkJRBG3CgDNAQALAAkJRBG3CgDNAQAMAAUJ7QCsWAA5AAAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAINAAYJXyIQPwD4AQANAAYJXyIQPwD4AQAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgYJDwAAAA==.Chunly:BAABLgAECn8dAAQOAAkJMBU8FQANAgAOAAkJMBU8FQANAgAHAAMJIg4CbQBoAAAGAAIJmwQmZABAAAAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8YAAIPAAgJQxH+GAByAQAPAAgJQxH+GAByAQAAAA==.Cmorbones:BAAALgADCgUJBQAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAOAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMQAAkJcBO9HwDZAQAQAAkJkBG9HwDZAQARAAYJcBAjDwAVAQAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8VAAISAAcJ0hjrYAC7AQASAAcJ0hjrYAC7AQAAAA==.Davik:BAABLgAECn8YAAITAAYJ/gzvRQD1AAATAAYJ/gzvRQD1AAAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgQJBwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJCgAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIUAAgJJw0SkwBKAQAUAAgJJw0SkwBKAQAAAA==.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAQAEILAQ==.Dracene:BAABLgAECn8bAAIVAAgJBQj+IwDxAAAVAAgJBQj+IwDxAAAAAA==.Dragosa:BAAALgAECgMJAwABLgAFFAIJBAAWAAAAAA==.Driver:BAAALgAFFAMJAgABLgAFFAUJDwAXALYLAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBwABLgAECgUJDAAWAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMGAAkJvB4OBQAUAwAGAAkJvB4OBQAUAwAHAAEJZQrEhQA7AAAAAA==.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMYAAgJkxTSHgAKAgAYAAgJkxTSHgAKAgAUAAEJ8QSktQElAAAAAA==.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hpAIgDbAAATAAMJsBlAIgDbAAAZAAMJyQ8xMADJAAAuAAQKfygABBkACQlKHSEIAPICABkACQlKHSEIAPICABMACAnlHAMOAKMCABoAAgk5CDJxAGIAAAAA.',
Ge='Generel:BAAALgAECgEJAQAAAA==.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gl='Glassnops:BAAALgAFFAIJAgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAOAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8MAAIbAAQJZyBrKABdAQAbAAQJZyBrKABdAQAuAAQKf0kAAhsACQmIJTsCAGsDABsACQmIJTsCAGsDAAAA.',
Im='Imnotyourdad:BAAALgADCgMJAwAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAbAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIOAAcJPiQcEAB+AgAOAAcJPiQcEAB+AgAAAA==.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8TAAIKAAYJ8A56GwB2AQAKAAYJ8A56GwB2AQAuAAQKfy8AAgoACQmzIZgFAFsDAAoACQmzIZgFAFsDAAAA.',
Kr='Krazedwolf:BAACLgAFFH8KAAIUAAYJCBWWIQB5AQAUAAYJCBWWIQB5AQAuAAQKfygAAhQACQlGITcXALYCABQACQlGITcXALYCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx32AQCUAgATAAgJJx32AQCUAgAuAAQKfzcAAhMACQklJkABAMADABMACQklJkABAMADAAAA.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIcAAYJMQ50uQAEAQAcAAYJMQ50uQAEAQAAAA==.Lovelypwr:BAABLgAECn8+AAMTAAkJdROJGwDnAQATAAkJdROJGwDnAQAZAAEJSwx7egAvAAAAAA==.',
Ma='Mannera:BAABLgAFFH8KAAIZAAQJtBcbIwAqAQAZAAQJtBcbIwAqAQAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJBAAAAA==.Matheris:BAABLgAECn8YAAIPAAkJZiL9BQCvAgAPAAkJZiL9BQCvAgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIPAAkJHx6cBQC4AgAPAAkJHx6cBQC4AgABLgAFFAQJDwAMAMAaAA==.',
Me='Melarac:BAABLgAECn8XAAQKAAgJMwt2agDyAAAKAAcJ2wd2agDyAAAJAAYJjQkOTwDMAAAIAAUJ1AZ/VABeAAAAAA==.',
Mi='Minibow:BAAALgAECgMJBAAAAA==.Minimagic:BAACLgAFFH8XAAMSAAUJNRzXTwBGAQASAAUJNRzXTwBGAQAdAAEJBAi9BgBAAAAuAAQKfzwAAhIACQlIJGAKACQDABIACQlIJGAKACQDAAAA.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQGAAgJzh5mGwA3AgAGAAcJrh5mGwA3AgAHAAUJ7hu8MAA9AQAOAAYJgBUQPgAjAQAAAA==.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAISAAIJ8xtglQCjAAASAAIJ8xtglQCjAAAuAAQKfzgAAhIACAlfI/sgAPACABIACAlfI/sgAPACAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgMJAwAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJEgAAAA==.',
Ni='Niftyshiftyy:BAAALgADCgMJAwAAAA==.Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIQAAQJpBQaKQAgAQAQAAQJpBQaKQAgAQAuAAQKfxkAAhAACQkAI5QDADQDABAACQkAI5QDADQDAAEuAAUUCAkoABAA8hsA.Nitalzit:BAAALgADCgQJBwAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQAWAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAOAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Ot='Otsana:BAAALgAECgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAACLgAFFH8FAAIcAAQJ1gSyiwDuAAAcAAQJ1gSyiwDuAAAuAAQKfx4AAhwACQkkFBxIAOcBABwACQkkFBxIAOcBAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAOAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.Rahimah:BAAALgADCgYJBgAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMeAAgJ2R7CBwB3AgAeAAgJ2R7CBwB3AgACAAEJ7RkOlwBAAAAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAWAAAAAA==.Roidsnmolly:BAAALgAECggJAwAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAYJEwAKAPAOAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhQjLwCRAQACAAcJUhQjLwCRAQAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAFAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDwAAAA==.',
Sh='Shammtastiç:BAABLgAECn88AAIfAAkJThfiGQAPAgAfAAkJThfiGQAPAgAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMcAAgJsg1pdwByAQAcAAgJsg1pdwByAQALAAQJ/AUpMQBTAAAAAA==.',
Sn='Sncak:BAACLgAFFH8nAAMDAAcJoxnACAAJAgADAAcJoxnACAAJAgAEAAEJOQ08BgBcAAAuAAQKfyoAAwMACQkPJCgCAJADAAMACQkPJCgCAJADAAQABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8KAAIFAAUJaRc0BgBGAQAFAAUJaRc0BgBGAQAuAAQKfxsAAgUACQn2ITsEAN0CAAUACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8sAAMRAAgJ8xgiBgDtAQARAAcJLRwiBgDtAQAQAAQJawy0YgCtAAABLgAFFAQJDwAMAMAaAA==.Syrieal:BAACLgAFFH8PAAIMAAQJwBpTFgAyAQAMAAQJwBpTFgAyAQAuAAQKf0IAAwwACQnUH6QGALMCAAwACQnAHqQGALMCAAsACAlmGH0IAAMCAAAA.',
Ta='Taiyla:BAACLgAFFH8KAAISAAQJoQbRbwAHAQASAAQJoQbRbwAHAQAuAAQKfz4AAhIACQmmFtwwAFMCABIACQmmFtwwAFMCAAAA.Talithiala:BAAALgAECgYJDwAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMGAAgJExkqEwAzAgAGAAgJExkqEwAzAgAOAAcJigrGXACfAAAAAA==.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAABLgAECn8XAAIFAAcJORDTGQA5AQAFAAcJORDTGQA5AQAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJBQABLgAFFAYJEwAKAPAOAA==.',
To='Torrcham:BAAALgAECgEJAQABLgAECgcJFQASANIYAA==.',
Tr='Trip:BAABLgAECn8kAAMgAAkJSgvvVgArAQAgAAkJSgvvVgArAQAhAAcJBw1PGwAiAQAAAA==.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIhAAYJORlfFQBkAQAhAAYJORlfFQBkAQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJKAAaABwcAA==.Unilock:BAACLgAFFH8KAAIXAAQJ8RSmSAAxAQAXAAQJ8RSmSAAxAQAuAAQKfyAAAhcACQmyGdQnADsCABcACQmyGdQnADsCAAEuAAUUBwkoABoAHBwA.Unipray:BAACLgAFFH8oAAMaAAcJHBwBBQAMAgAaAAcJHBwBBQAMAgATAAUJnxpQFAA8AQAuAAQKfycAAxoACQmwIlABAG8DABoACQmwIlABAG8DABMABwnrHtIUAEcCAAAA.',
Va='Vamperella:BAABLgAECn8ZAAIdAAYJcgFaEwBMAAAdAAYJcgFaEwBMAAAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgcJDQAAAA==.Wolffspirit:BAAALgADCgEJAQABLgAFFAYJEwAKAPAOAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJKwAcAEklAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAWAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRadAgAgAgAiAAkJGRadAgAgAgAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIbAAgJARB3UgCnAQAbAAgJARB3UgCnAQAAAA==.',
Yo='You:BAABLgAECn8kAAIMAAkJsxeaFQC9AQAMAAkJsxeaFQC9AQAAAA==.',
Yu='Yulogee:BAABLgAFFH8HAAMMAAMJMB6VHQD0AAAMAAMJMB6VHQD0AAAcAAEJ4wLLGwEyAAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAWAAAAAA==.',
Za='Zabrozo:BAAALgAECgcJCAAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIfAAgJlxW3JAC+AQAfAAgJlxW3JAC+AQAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
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
