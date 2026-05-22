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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Shaman-Enhancement','Hunter-Marksmanship','DeathKnight-Frost','Evoker-Preservation','Warrior-Protection','Priest-Holy','Priest-Discipline',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8UAAIBAAYJixJXCwB8AQABAAYJixJXCwB8AQAuAAQKfyQAAwEACQnWHZ8XAEcCAAEACQnWHZ8XAEcCAAIABwnaGMsjAJ8BAAEuAAUUCAkkAAMA7B0A.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAcJJAAEAM0YAA==.',
Al='Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8jAAIFAAkJQiBtDACrAgAFAAkJQiBtDACrAgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJBgAGAAAAAA==.Alius:BAAALgAECgEJAQAAAA==.',
Am='Ambellina:BAACLgAFFH8JAAIHAAMJbhryGAARAQAHAAMJbhryGAARAQAuAAQKfzAAAwcACQnLG4cUAG4CAAcACQnLG4cUAG4CAAgABAnmCiayAM0AAAAA.Amp:BAAALgAECgEJAQABLgAFFAUJEQAJAFcQAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.',
Au='Auxiliry:BAAALgADCgEJAQAAAA==.',
Av='Avenger:BAABLgAFFH8FAAIIAAQJRRhgGgBWAQAIAAQJRRhgGgBWAQABLgAFFAcJIgAKAFQhAA==.',
Ay='Aythrior:BAAALgAECgcJEAAAAA==.',
Ba='Bambiietta:BAABLgAECn8WAAILAAcJJghgmgBLAQALAAcJJghgmgBLAQAAAA==.',
Be='Beefycrits:BAACLgAFFH8KAAIMAAMJLSZ1OwBDAQAMAAMJLSZ1OwBDAQAuAAQKfycAAgwACQnnI8MXABwDAAwACQnnI8MXABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgYJBwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Capriestson:BAABLgAECn8lAAINAAgJ5hY1FgDHAQANAAgJ5hY1FgDHAQAAAA==.Cardrin:BAABLgAECn8iAAMOAAkJ7g+zEgBRAQAOAAkJ7g+zEgBRAQAPAAYJ4gPoWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8cAAIDAAUJKhp3AgCPAQADAAUJKhp3AgCPAQAuAAQKfyAAAgMACAm+Ih8IAPgCAAMACAm+Ih8IAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH8RAAIMAAYJXB9CEQDLAQAMAAYJXB9CEQDLAQAAAA==.',
Cl='Clarence:BAAALgAECgUJCAAAAA==.Clearance:BAABLgAFFH8LAAIQAAUJVhGdGwAkAQAQAAUJVhGdGwAkAQAAAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgMJBgAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQABLgAECgEJAwAGAAAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.',
Da='Daemon:BAACLgAFFH8kAAQEAAcJzRjAAQBHAQARAAYJfxKKCACgAQAEAAUJJBHAAQBHAQASAAQJXhAUCADrAAAuAAQKfzcABAQACQnTJFoAABsDAAQACQlQIloAABsDABEACQksI/ISAOQCABIAAwk5FI4xAPMAAAAA.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAABLgAECn8YAAITAAcJpAvcHgBVAQATAAcJpAvcHgBVAQAAAA==.Dattsu:BAABLgAECn8aAAMRAAcJxRKxYABAAQARAAcJAxKxYABAAQASAAUJDxACLQAKAQAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgYJDgABLgAFFAMJDAAMAG0TAA==.Demonius:BAAALgADCgMJAwABLgAECgkJFQAPAF8GAA==.Derangedxo:BAACLgAFFH8vAAQRAAkJRyFNAADtAgARAAgJOCJNAADtAgASAAUJMRTSAQC9AQAEAAIJ4SZcBwB0AAAuAAQKfyMAAxEACQlOJp4CAJsDABEACQlOJp4CAJsDABIAAwmgI+olAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgAUAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.',
Du='Duskforger:BAABLgAECn8kAAIPAAgJ6QvzJgA6AQAPAAgJ6QvzJgA6AQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAIDAAgJTBQnHQDxAQADAAgJTBQnHQDxAQAAAA==.',
Ev='Everblack:BAABLgAECn81AAISAAkJUR/eAADKAgASAAkJUR/eAADKAgAAAA==.Evilcretin:BAACLgAFFH8KAAIMAAMJ8RzBJwAUAQAMAAMJ8RzBJwAUAQAuAAQKfykAAgwABgn0I0g5APIBAAwABgn0I0g5APIBAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Falco:BAAALgADCgYJBgAAAA==.Faraah:BAABLgAECn9BAAMVAAkJyiFmAQD7AgAVAAkJyiFmAQD7AgAWAAEJ0gTr2wAnAAAAAA==.',
Fl='Florleesa:BAAALgADCgYJCAAAAA==.Flowstate:BAABLgAFFH8RAAIJAAUJVxAwGwAQAQAJAAUJVxAwGwAQAQAAAA==.',
Fr='Friérén:BAACLgAFFH8MAAIMAAMJbRPVLwD2AAAMAAMJbRPVLwD2AAAuAAQKfyoAAwwACAmXHo0rACkCAAwACAmXHo0rACkCABcAAQm4BS0hACkAAAAA.',
Ga='Garhkanis:BAAALgAFFAEJAQAAAA==.Garro:BAACLgAFFH8HAAIYAAMJqBU+IADlAAAYAAMJqBU+IADlAAAuAAQKfx4AAhgACAkFHtAbAG4CABgACAkFHtAbAG4CAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Genjidh:BAABLgAECn8cAAQBAAgJ3x+BPgCBAQACAAQJGyLyJgCJAQABAAYJaRyBPgCBAQAZAAUJFR5RDwBdAQAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgADCgEJAQAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gr='Graud:BAABLgAFFH8GAAIQAAIJdxCrNACVAAAQAAIJdxCrNACVAAAAAA==.Grimdark:BAABLgAECn8iAAIaAAYJahZXOQBpAQAaAAYJahZXOQBpAQAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAECgYJDwAAAA==.Grumpypants:BAABLgAECn8rAAIOAAgJuBaiCwC8AQAOAAgJuBaiCwC8AQAAAA==.Grunge:BAACLgAFFH8JAAMRAAQJUQhdQgACAQARAAQJUQhdQgACAQASAAEJWAAKHgAgAAAuAAQKfygABBEACQmTGmYRAIoCABEACQmTGmYRAIoCABIABQmhENUjADoBAAQAAQk4GsQtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAIMAAgJMCGmIgDoAgAMAAgJMCGmIgDoAgAAAA==.',
Ha='Haven:BAABLgAECn8iAAINAAkJAR74CQDjAgANAAkJAR74CQDjAgAAAA==.',
He='Heathermarie:BAABLgAECn8oAAIbAAkJShoMAQBsAgAbAAkJShoMAQBsAgAAAA==.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Ho='Holypride:BAAALgADCgEJAQAAAA==.Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgAECgIJAgAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAAALgAFFAIJAwAAAA==.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgQJBAAAAA==.Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8nAAIaAAkJLRAILwCeAQAaAAkJLRAILwCeAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8YAAQRAAcJyBZWEABeAQARAAUJnBhWEABeAQASAAQJyRdoBgAKAQAEAAEJeBuXCgBcAAAuAAQKfyQABAQACAn5Ii4FABsCABEACAkWIqsdAKQCAAQABQlrJS4FABsCABIAAgkYG2BEAKQAAAAA.Jamboni:BAAALgAECgUJCgAAAA==.Jarmamathu:BAAALgAECgcJCgAAAA==.Jay:BAAALgAFFAIJAgAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDAAAAA==.',
Jo='Joje:BAABLgAECn8hAAMRAAcJuRjmOwCsAQARAAcJuRjmOwCsAQASAAIJVgmrWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgAECgEJAQAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAAALgAECgkJEAAAAA==.Keora:BAABLgAECn8lAAIQAAkJBRJnGADEAQAQAAkJBRJnGADEAQAAAA==.',
Kh='Khronos:BAABLgAECn8ZAAIQAAkJKg4XIwBwAQAQAAkJKg4XIwBwAQAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAAALgAFFAIJBAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Kronik:BAAALgADCggJDAAAAA==.Krow:BAAALgADCggJGgAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAAALgAFFAIJAgAAAA==.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBgAAAA==.Lightsmith:BAABLgAECn8fAAMHAAkJbiCOGQBGAgAHAAkJbiCOGQBGAgAIAAEJIRlSFAFGAAAAAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAgAAAA==.Lorez:BAABLgAFFH8VAAIRAAUJPw7xNwAfAQARAAUJPw7xNwAfAQAAAA==.Low:BAABLgAECn8gAAIRAAcJlRkaPwChAQARAAcJlRkaPwChAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn8eAAIcAAgJFQ22DQBkAQAcAAgJFQ22DQBkAQAAAA==.Mageaurora:BAAALgAECgQJAwAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Mazzh:BAABLgAFFH8GAAMFAAMJxCCKLgACAQAFAAMJTiCKLgACAQAdAAIJmxnwGQC2AAABLgAFFAgJBwAMAD0mAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Meowyn:BAAALgADCgcJBwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgADCggJDAAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mikeybad:BAAALgAECgEJAgABLgAECgYJHAALAOIhAA==.Minimage:BAAALgADCgYJBgAAAA==.Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJGAsCXwCEAQABAAkJ6AoCXwCEAQACAAYJEAlKOwATAQAAAA==.',
Mo='Moobie:BAAALgADCggJDwAAAA==.Mortikhan:BAAALgAECgIJAgAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Na='Narium:BAAALgAECggJEwAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAgAAAA==.',
No='Noctilucent:BAAALgAECgUJBwAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgIJAgAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Pa='Pallywix:BAAALgADCgYJBwAAAA==.Paredes:BAAALgAECgQJBQAAAA==.',
Pe='Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAACLgAFFH8IAAILAAQJ1RLTZADrAAALAAQJ1RLTZADrAAAuAAQKfx8AAgsACAnDH/IfAEUCAAsACAnDH/IfAEUCAAEuAAUUBgkVABEAOh8A.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAMJDAAMAG0TAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8gAAIcAAkJ2xg7BgAaAgAcAAkJ2xg7BgAaAgAAAA==.Prophesy:BAACLgAFFH8GAAIIAAMJpAmgRgDWAAAIAAMJpAmgRgDWAAAuAAQKfyMAAggACAmbHMIoAIICAAgACAmbHMIoAIICAAAA.Proteus:BAACLgAFFH8HAAILAAQJFAVdTwAVAQALAAQJFAVdTwAVAQAuAAQKfyoAAwsACAlYF+E5ANMBAAsACAlYF+E5ANMBAB4ABAkXDLcOALcAAAAA.',
Pu='Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Reflex:BAAALgAECgcJDQAAAA==.Retpar:BAAALgAECgYJBwAAAA==.Reventön:BAABLgAECn8nAAILAAkJsg5QPwC/AQALAAkJsg5QPwC/AQAAAA==.',
Rh='Rhaena:BAAALgAECgIJAgABLgAFFAcJJAAEAM0YAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAABLgAECn8VAAMPAAkJXwYQLwAJAQAPAAgJAQcQLwAJAQAWAAgJCATIhgDJAAAAAA==.',
['Rá']='Ráîstlin:BAAALgAECgEJAQAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJCwAAAA==.',
Se='Senada:BAABLgAECn8eAAIMAAgJcgNspQD3AAAMAAgJcgNspQD3AAAAAA==.Senkait:BAABLgAECn8mAAQUAAgJIB2lDgA0AgAUAAgJ3BylDgA0AgAaAAYJthvROQCbAQAcAAIJoBfeHACMAAAAAA==.',
Sh='Shamoura:BAACLgAFFH8fAAIUAAcJ9xdcAQASAgAUAAcJ9xdcAQASAgAuAAQKfx0AAhQACAmcIzEJAP8CABQACAmcIzEJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shinoa:BAAALgAECgcJAQAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shlongtofoot:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulszaura:BAACLgAFFH8eAAIIAAcJIhuGAwAQAgAIAAcJIhuGAwAQAgAuAAQKfzEAAggACQkhIgoSAAIDAAgACQkhIgoSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8NAAIBAAUJwRMFKwAlAQABAAUJwRMFKwAlAQAuAAQKfygAAgEACQmEHdEWAE0CAAEACQmEHdEWAE0CAAAA.Steampunk:BAABLgAECn8UAAIMAAcJzQ/ehAAyAQAMAAcJzQ/ehAAyAQAAAA==.',
Sw='Swade:BAABLgAECn8YAAIJAAYJ0AooOgDXAAAJAAYJ0AooOgDXAAABLgAECgcJGAATAKQLAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAMJDAAMAG0TAA==.Synarri:BAACLgAFFH8TAAMHAAQJMhrrEwA5AQAHAAQJMhrrEwA5AQAIAAIJmxYAUwCoAAAuAAQKf0oAAwgACQkkIrgFABcDAAgACQkkIrgFABcDAAcACQkEHN4NAKkCAAEuAAUUBwkcAAcA6xoA.Syneria:BAACLgAFFH8cAAMHAAcJ6xoFAQAZAgAHAAcJ6xoFAQAZAgAIAAEJ6QHBewA/AAAuAAQKf0IAAwcACQmaH0kLAMQCAAcACAnpIEkLAMQCAAgACQk0HQsqABECAAAA.Synn:BAAALgAFFAIJAwABLgAFFAcJHAAHAOsaAA==.Synpai:BAACLgAFFH8KAAMHAAQJABidFQApAQAHAAQJABidFQApAQAIAAIJQA7CWgCcAAAuAAQKfyEAAwcACQlAFQQsANcBAAcABwkuFAQsANcBAAgABgk7Gx9gAMQBAAEuAAUUBwkcAAcA6xoA.',
Ta='Taccitus:BAACLgAFFH8bAAIBAAYJdRUiFQB/AQABAAYJdRUiFQB/AQAuAAQKfykAAwEACQliIUMdAKICAAEACQliIUMdAKICAAIAAgltGZ0zAI4AAAAA.Tailzz:BAAALgAECgUJCAAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAFFAEJAQAAAA==.',
Te='Teach:BAABLgAECn8YAAMfAAYJ3gs0KwAZAQAfAAYJ3gs0KwAZAQAQAAQJGhlrNAAIAQAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thunderwar:BAABLgAECn8WAAIgAAYJ0hbPHAD/AAAgAAYJ0hbPHAD/AAAAAA==.',
Ti='Tiazy:BAAALgAECgEJAQAAAA==.',
To='Toomato:BAAALgAECgQJBwAAAA==.Totemterror:BAEBLgAECn8lAAIaAAkJViY4AADfAwAaAAkJViY4AADfAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tx='Tx:BAAALgADCgIJAgAAAA==.',
Ty='Tydradul:BAACLgAFFH8FAAIRAAIJHgs5eQCLAAARAAIJHgs5eQCLAAAuAAQKfyoAAhEACAnxFiQwANgBABEACAnxFiQwANgBAAAA.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAABLgAECn80AAIWAAgJ3iB/CQDlAgAWAAgJ3iB/CQDlAgAAAA==.Valy:BAAALgAECgYJEgAAAA==.',
Ve='Veladria:BAACLgAFFH8LAAILAAQJORlGOABEAQALAAQJORlGOABEAQAuAAQKfxoAAgsABwmYHGhaAOIBAAsABwmYHGhaAOIBAAAA.Vellion:BAAALgADCgYJCAAAAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAACLgAFFH8FAAIBAAEJKSXIYgBrAAABAAEJKSXIYgBrAAAuAAQKfxgAAgEABgm9I4MlAHECAAEABgm9I4MlAHECAAAA.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAcJGAARAMgWAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBwABLgAECgkJFQAPAF8GAA==.',
Wi='Wikkid:BAABLgAECn8vAAIPAAcJnw6IKQAqAQAPAAcJnw6IKQAqAQAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgQJBwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgEJAQAAAA==.',
Yi='Yiesus:BAABLgAFFH8HAAINAAQJKAxaEQAsAQANAAQJKAxaEQAsAQABLgAFFAgJIAABADUiAA==.',
Ym='Ymir:BAABLgAECn8cAAMSAAgJkhP8DQDnAQASAAgJkhP8DQDnAQARAAQJDgST4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8JAAIWAAMJNQ+zLADDAAAWAAMJNQ+zLADDAAAuAAQKfzgAAhYACQlqHWcKANcCABYACQlqHWcKANcCAAAA.',
Yp='Yppah:BAABLgAECn8fAAIUAAkJ1g6sIQCBAQAUAAkJ1g6sIQCBAQAAAA==.',
Yu='Yuhmato:BAAALgAFFAIJBAAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQhAAgJIBBsKwCaAQAhAAcJThFsKwCaAQAiAAMJJAjqTgBJAAANAAEJhwpWYQA1AAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8aAAIBAAYJPR38DQCxAQABAAYJPR38DQCxAQAuAAQKfyMAAgEACAm0IxgNABcDAAEACAm0IxgNABcDAAAA.',
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
