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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Monk-Mistweaver','DeathKnight-Frost','Priest-Discipline','Priest-Holy','Rogue-Outlaw','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Preservation',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8qAAIBAAcJ/R83CwBCAgABAAcJ/R83CwBCAgAuAAQKfyUAAwEACQnWHWQiAD0CAAEACQnWHWQiAD0CAAIABwnaGMsjAJ8BAAEuAAUUCQkxAAMA6R8A.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAgJLAAEAA0bAA==.',
Al='Alanestus:BAAALgADCgUJBQAAAA==.Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8jAAIFAAkJQyArGwB2AgAFAAkJQyArGwB2AgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.Alius:BAAALgAECgYJDQAAAA==.',
Am='Ambellina:BAACLgAFFH8LAAIHAAMJbhrPIgD9AAAHAAMJbhrPIgD9AAAuAAQKfzQAAwcACQnmG4cUAG4CAAcACQnmG4cUAG4CAAgABAnmCvbwALwAAAAA.Amp:BAAALgAECgEJAQABLgAFFAYJEwAJAOoPAA==.',
Ar='Aravalia:BAAALgADCgIJAgAAAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.Ashlord:BAAALgAECgQJBAAAAA==.',
Au='Auxiliry:BAAALgAECgUJBQAAAA==.',
Av='Avenger:BAABLgAFFH8GAAIIAAQJRRg8NAA0AQAIAAQJRRg8NAA0AQABLgAFFAkJOwAKAAciAA==.',
Ay='Aythrior:BAABLgAECn8WAAILAAcJRB2sDwDhAQALAAcJRB2sDwDhAQAAAA==.',
Ba='Bambiietta:BAACLgAFFH8PAAIMAAQJ2QSXfQD5AAAMAAQJ2QSXfQD5AAAuAAQKfxkAAgwABwnyCWCaAEsBAAwABwnyCWCaAEsBAAAA.',
Be='Beastsmaster:BAAALgAECgUJBgAAAA==.Beefycrits:BAACLgAFFH8OAAINAAQJjSVINACGAQANAAQJjSVINACGAQAuAAQKfycAAg0ACQnpI8MXABwDAA0ACQnpI8MXABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgcJCwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Calmduke:BAAALgAECgIJAwAAAA==.Camilacream:BAAALgAECgEJAQAAAA==.Capriestson:BAACLgAFFH8KAAIOAAQJLQ4cGgAJAQAOAAQJLQ4cGgAJAQAuAAQKfzIAAg4ACQksGukOAGQCAA4ACQksGukOAGQCAAAA.Cardrin:BAABLgAECn8iAAMPAAkJ7g9/HwA+AQAPAAkJ7g9/HwA+AQAQAAYJ4gPoWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8hAAIDAAYJSRusBQCtAQADAAYJSRusBQCtAQAuAAQKfyAAAgMACAm+Ih8IAPgCAAMACAm+Ih8IAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH8UAAINAAgJCx70DQBgAgANAAgJCx70DQBgAgAAAA==.',
Cl='Clarence:BAAALgAECgUJCAAAAA==.Clearance:BAABLgAFFH8QAAIRAAUJ9BYQIwAwAQARAAUJ9BYQIwAwAQABLgAFFAgJJQASAAMaAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgQJBwAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQABLgAECgEJAwAGAAAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.',
Da='Daboomdeath:BAAALgAFFAMJAgAAAA==.Daemon:BAACLgAFFH8sAAQEAAgJDRv+AADBAQAEAAYJ/xn+AADBAQASAAcJOROKCACgAQATAAUJixIUCADrAAAuAAQKfzcABAQACQnaJDkBAO8CAAQACQlRIjkBAO8CABIACQkzI/ISAOQCABMAAwk5FI4xAPMAAAAA.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAABLgAECn8dAAIUAAgJWQq+IwB6AQAUAAgJWQq+IwB6AQAAAA==.Dattsu:BAABLgAECn8aAAMTAAcJxhICLQAKAQASAAcJBBLaewA8AQATAAUJDxACLQAKAQAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgYJDgABLgAFFAQJBwASALEGAA==.Demonius:BAAALgADCgMJAwABLgAECgkJFQAQAF8GAA==.Derangedxo:BAACLgAFFH9DAAQSAAkJpSOGAAA3AwASAAkJeyOGAAA3AwATAAUJMxTSAQC9AQAEAAUJjiUJAQC9AQAuAAQKfyMAAxIACQlOJp4CAJsDABIACQlOJp4CAJsDABMAAwmgI+olAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgAVAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.Drunkenhoe:BAAALgAECgMJAwAAAA==.',
Du='Duskforger:BAABLgAECn8tAAIQAAkJaw2JJQCSAQAQAAkJaw2JJQCSAQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAIDAAgJTBQnHQDxAQADAAgJTBQnHQDxAQAAAA==.',
Ev='Everblack:BAACLgAFFH8IAAMTAAMJBR3zDgCwAAATAAIJAyDzDgCwAAAEAAEJBxffHQBRAAAuAAQKfzcAAhMACQmCH7gBALYCABMACQmCH7gBALYCAAAA.Evilcretin:BAACLgAFFH8KAAINAAMJ8RzBJwAUAQANAAMJ8RzBJwAUAQAuAAQKfzAAAg0ABgn0I/RLAPEBAA0ABgn0I/RLAPEBAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Falco:BAAALgADCgYJBgAAAA==.Faraah:BAACLgAFFH8RAAIWAAUJAx79AwBvAQAWAAUJAx79AwBvAQAuAAQKf0sAAxYACQnoIZYCAPICABYACQnoIZYCAPICABcAAQnSBOvbACcAAAAA.',
Fl='Florleesa:BAAALgADCgYJCAAAAA==.Flowstate:BAABLgAFFH8TAAIJAAYJ6g8QGgBDAQAJAAYJ6g8QGgBDAQAAAA==.',
Fr='Friérén:BAACLgAFFH8PAAINAAMJSxjVLwD2AAANAAMJSxjVLwD2AAAuAAQKfyoAAw0ACAmXHpNBABECAA0ACAmXHpNBABECABgAAQm4BS0hACkAAAEuAAUUBAkHABIAsQYA.',
Ga='Garhkanis:BAABLgAFFH8LAAISAAQJQiUgHQC4AQASAAQJQiUgHQC4AQAAAA==.Garro:BAACLgAFFH8OAAIZAAQJOReUHQAtAQAZAAQJOReUHQAtAQAuAAQKfycAAhkACAl+HmMUAEcCABkACAl+HmMUAEcCAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Generico:BAAALgADCgMJAwABLgAFFAYJIQAVABUlAA==.Genjidh:BAABLgAECn8hAAQBAAgJ5iBYHQBaAgABAAgJrR5YHQBaAgACAAQJGyLyJgCJAQAaAAUJFR5RDwBdAQAAAA==.Geoph:BAAALgAECgIJAgAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgADCgEJAQAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gr='Graud:BAABLgAFFH8GAAIRAAIJdxC1TQB9AAARAAIJdxC1TQB9AAAAAA==.Graudel:BAABLgAFFH8HAAIZAAUJexVEGwA2AQAZAAUJexVEGwA2AQAAAA==.Grimdark:BAABLgAECn8wAAIbAAgJiBqgGAB4AgAbAAgJiBqgGAB4AgAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAFFAIJAgAAAA==.Grumpypants:BAABLgAECn85AAIPAAkJ4Bf0CwASAgAPAAkJ4Bf0CwASAgAAAA==.Grunge:BAACLgAFFH8JAAMSAAQJUQiXYQDyAAASAAQJUQiXYQDyAAATAAEJWABNKgAfAAAuAAQKfygABBIACQmUGlccAHQCABIACQmUGlccAHQCABMABQmhENUjADoBAAQAAQk4GsQtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAINAAgJMCGmIgDoAgANAAgJMCGmIgDoAgAAAA==.',
Ha='Hairyhealer:BAAALgAECgYJCgAAAA==.Haven:BAABLgAECn8iAAIOAAkJAR74CQDjAgAOAAkJAR74CQDjAgAAAA==.',
He='Heathermarie:BAACLgAFFH8GAAIcAAMJYQ4fAwC6AAAcAAMJYQ4fAwC6AAAuAAQKfz8AAhwACQn/H7sAAOgCABwACQn/H7sAAOgCAAAA.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Hi='Historia:BAABLgAFFH8HAAISAAQJsQbdYQDyAAASAAQJsQbdYQDyAAAAAA==.',
Ho='Holdmytraps:BAAALgAECgUJBwAAAA==.Holypride:BAAALgAECgYJBgAAAA==.Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgAECgQJBQAAAA==.',
['Há']='Háppyelf:BAAALgAECgUJBQAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAACLgAFFH8IAAIdAAQJhhlKIAA+AQAdAAQJhhlKIAA+AQAuAAQKfxQAAx0ACAmIFsAeAA8CAB0ACAmIFsAeAA8CAAkAAwkKA7t1AGsAAAAA.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgcJCQAAAA==.Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8rAAIbAAkJlRA/QACfAQAbAAkJlRA/QACfAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8dAAQEAAcJjxlUAgB4AQAEAAQJLB9UAgB4AQASAAUJuBlWEABeAQATAAQJzRdoBgAKAQAuAAQKfyQABAQACAn5Ii4FABsCABIACAkWIqsdAKQCAAQABQlrJS4FABsCABMAAgkYG2BEAKQAAAAA.Jamboni:BAABLgAFFH8GAAMMAAQJ6RVkegD/AAAMAAMJvBlkegD/AAAeAAMJWQzvEgDVAAAAAA==.Jarmamathu:BAAALgAECgcJCgAAAA==.Jay:BAAALgAFFAIJAgAAAA==.',
Ji='Jimlaheys:BAABLgAECn8UAAMXAAgJxAVjZwD1AAAXAAgJxAVjZwD1AAAQAAYJpgQRWwCZAAAAAA==.',
Jo='Joje:BAABLgAECn8kAAMSAAgJIhijPwDYAQASAAgJIhijPwDYAQATAAIJVgmrWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgAECgEJAQAAAA==.Juniperdayne:BAAALgAFFAEJAQAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAABLgAECn8dAAQfAAcJLRG7MQBGAQAfAAcJUQ27MQBGAQAgAAYJ5g2WSQCvAAAOAAEJhgMhjgAiAAAAAA==.Keora:BAABLgAECn8mAAIRAAkJxRI2IADPAQARAAkJxRI2IADPAQAAAA==.',
Kh='Khronos:BAABLgAECn8pAAIRAAkJTRieEQBPAgARAAkJTRieEQBPAgAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAABLgAFFH8FAAIfAAIJlhGyOAB+AAAfAAIJlhGyOAB+AAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Krethrik:BAAALgADCggJFAABLgAECggJEwAGAAAAAA==.Kronik:BAAALgAECgQJBQAAAA==.Krow:BAAALgAECgEJAQAAAA==.',
['Kæ']='Kæli:BAAALgADCgUJBQAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAACLgAFFH8JAAMhAAMJNyHmBQAmAQAhAAMJNyHmBQAmAQAKAAIJBQROMwB/AAAuAAQKfxUAAyEABglHFyYKAHcBAAoABgmTEo8oALUBACEABQksGCYKAHcBAAAA.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightimus:BAAALgADCgIJAgAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBwAAAA==.Lightsmith:BAABLgAECn8hAAMHAAkJbiCOGQBGAgAHAAkJbiCOGQBGAgAIAAMJ2xvezADqAAAAAA==.Liyun:BAAALgAECgEJAQABLgAECgkJJgARAMUSAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAwAAAA==.Lorez:BAACLgAFFH8cAAISAAYJwg+KMQBoAQASAAYJwg+KMQBoAQAuAAQKfxQAAhIACQnCFyRGAPkBABIACQnCFyRGAPkBAAAA.Low:BAABLgAECn8mAAISAAgJKRdxQADWAQASAAgJKRdxQADWAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn8yAAIiAAkJQhGFDADbAQAiAAkJQhGFDADbAQAAAA==.Mageaurora:BAAALgAECgYJCQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Maysia:BAAALgADCgUJBQAAAA==.Mazzh:BAABLgAFFH8WAAMFAAYJOSJjGgCFAQAFAAUJZCJjGgCFAQAjAAUJJRs/FwDqAAABLgAFFAkJDQANAEwmAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Mem:BAAALgAECgYJDQAAAA==.Meowyn:BAAALgADCgcJBwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgAECgQJAgAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mikeybad:BAAALgAECgEJAgABLgAECgkJIgAMAIogAA==.Minimage:BAAALgAECgEJAQAAAA==.Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJGAsCXwCEAQABAAkJ6AoCXwCEAQACAAYJEAlKOwATAQAAAA==.',
Mo='Moobie:BAAALgAECgYJEQAAAA==.Moobiemist:BAAALgADCgEJAQABLgAECgYJEQAGAAAAAA==.Mortikhan:BAAALgAECgYJCgAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Mu='Mumsydk:BAEALgAECgEJAQABLgAFFAkJMAAXAK0fAA==.',
Na='Narium:BAABLgAECn8ZAAIfAAgJsRf1IgCnAQAfAAgJsRf1IgCnAQAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAgAAAA==.',
No='Noctilucent:BAAALgAECgUJBwAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgMJAwAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Oz='Ozzie:BAAALgAECgEJAQAAAA==.',
Pa='Pallywix:BAAALgAECgMJAwAAAA==.Paredes:BAAALgAECgUJBwAAAA==.',
Pe='Peewee:BAAALgAECgIJAgAAAA==.Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAACLgAFFH8NAAIMAAQJbRZ8VwA3AQAMAAQJbRZ8VwA3AQAuAAQKfyAAAgwACAnJH4svADgCAAwACAnJH4svADgCAAEuAAUUBwkYABIArh0A.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAQJBwASALEGAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8rAAIiAAkJ8hpdCAAwAgAiAAkJ8hpdCAAwAgAAAA==.Prophesy:BAACLgAFFH8GAAIIAAMJpAnwcgC3AAAIAAMJpAnwcgC3AAAuAAQKfyMAAggACAmaHMIoAIICAAgACAmaHMIoAIICAAAA.Proteus:BAACLgAFFH8LAAIMAAQJpwhudgAHAQAMAAQJpwhudgAHAQAuAAQKfyoAAwwACAlYF/1VALsBAAwACAlYF/1VALsBAB4ABAkXDLcOALcAAAAA.',
Pu='Puff:BAAALgAECgIJAgAAAA==.Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.Push:BAAALgAECgIJBAAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Reflex:BAAALgAECggJEQAAAA==.Retpar:BAAALgAECgYJBwABLgAFFAIJBgARAHcQAA==.Reventön:BAABLgAECn8rAAIMAAkJ+g7QVAC+AQAMAAkJ+g7QVAC+AQAAAA==.',
Rh='Rhaena:BAAALgAECgIJAgABLgAFFAgJLAAEAA0bAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAABLgAECn8VAAMQAAkJXwb0PQAJAQAQAAgJAQf0PQAJAQAXAAgJCATIhgDJAAAAAA==.',
['Rá']='Ráîstlin:BAAALgAFFAEJAQAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJDwAAAA==.',
Se='Selro:BAAALgADCgIJAgAAAA==.Senada:BAABLgAECn8eAAINAAgJcgNByQD2AAANAAgJcgNByQD2AAAAAA==.Senkait:BAABLgAECn8vAAQVAAkJ/xtyDQCHAgAVAAkJ/xtyDQCHAgAbAAYJtxvROQCbAQAiAAIJoBfBKgCGAAAAAA==.',
Sh='Shamoura:BAACLgAFFH8qAAIVAAgJcRhcAQASAgAVAAgJcRhcAQASAgAuAAQKfx0AAhUACAmcIzEJAP8CABUACAmcIzEJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shamyzz:BAAALgAECgEJAQAAAA==.Shinoa:BAAALgAECgcJAQAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shlongtofoot:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sl='Slunks:BAAALgAFFAIJAwAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulreaver:BAAALgAECgMJAwAAAA==.Soulszaura:BAACLgAFFH8jAAIIAAgJDhtKBgBKAgAIAAgJDhtKBgBKAgAuAAQKfzEAAggACQkhIgoSAAIDAAgACQkhIgoSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8TAAIBAAYJJhjDIwCEAQABAAYJJhjDIwCEAQAuAAQKfzEAAgEACQnaH/wPALkCAAEACQnaH/wPALkCAAAA.Steampunk:BAACLgAFFH8FAAINAAMJjgNMiwCuAAANAAMJjgNMiwCuAAAuAAQKfxgAAg0ABwk8EG+XAEUBAA0ABwk8EG+XAEUBAAAA.',
Su='Suwanee:BAAALgAECgMJAwAAAA==.',
Sw='Swade:BAABLgAECn8aAAIJAAYJ7wwtQwDlAAAJAAYJ7wwtQwDlAAABLgAECggJHQAUAFkKAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAQJBwASALEGAA==.Synarri:BAACLgAFFH8iAAMHAAUJHCV6CAAYAgAHAAUJHCV6CAAYAgAIAAMJNBjeVADzAAAuAAQKf0oAAwgACQkkIkILAAMDAAgACQkkIkILAAMDAAcACQkEHN4NAKkCAAEuAAUUCAknAAcABh8A.Syneria:BAACLgAFFH8nAAMHAAgJBh8FAQAZAgAHAAgJBh8FAQAZAgAIAAMJEw5CagDKAAAuAAQKf0MAAwcACQmaH0kLAMQCAAcACAnpIEkLAMQCAAgACQmTH/c1AB4CAAAA.Synn:BAAALgAFFAIJAwABLgAFFAgJJwAHAAYfAA==.Synpai:BAACLgAFFH8NAAMHAAQJABiYIQAGAQAHAAQJABiYIQAGAQAIAAIJQA7+hgCLAAAuAAQKfyoAAwgACQlpH7IYAKUCAAgACAlWIrIYAKUCAAcABwkvGAQsANcBAAEuAAUUCAknAAcABh8A.',
Ta='Taccitus:BAACLgAFFH8nAAIBAAcJ9RVnGwC1AQABAAcJ9RVnGwC1AQAuAAQKfy4AAwEACQljIb4OAMQCAAEACQljIb4OAMQCAAIAAwk3F3g5AMAAAAAA.Tailzz:BAAALgAECgcJDwAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAFFAEJAwAAAA==.',
Te='Teach:BAABLgAECn8hAAMRAAkJYhkoGQAGAgARAAcJHxooGQAGAgAkAAcJ1AyRJAC/AAAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thuggjr:BAAALgAECgEJAQABLgAFFAYJIQADAEkbAA==.Thunderwar:BAABLgAECn8bAAILAAYJDBiHIwAHAQALAAYJDBiHIwAHAQAAAA==.',
Ti='Tiazy:BAAALgAECgMJBAAAAA==.Tidepod:BAAALgAECgYJBgAAAA==.',
To='Toomato:BAAALgAECgQJBwAAAA==.Totemterror:BAEBLgAECn8lAAIbAAkJViaeAADUAwAbAAkJViaeAADUAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tx='Tx:BAAALgAECgYJCwAAAA==.',
Ty='Tydradul:BAACLgAFFH8MAAISAAQJyAepXwD3AAASAAQJyAepXwD3AAAuAAQKfywAAhIACQmTFcMxAAwCABIACQmTFcMxAAwCAAAA.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAACLgAFFH8FAAIXAAMJmQ6kPQCyAAAXAAMJmQ6kPQCyAAAuAAQKfzYAAhcACQk1HhMKABEDABcACQk1HhMKABEDAAAA.Valy:BAABLgAECn8fAAMfAAgJahf1EwAyAgAfAAgJahf1EwAyAgAgAAEJzAzWbAArAAAAAA==.',
Ve='Veladria:BAACLgAFFH8OAAIMAAYJ2RReOwBuAQAMAAYJ2RReOwBuAQAuAAQKfxwAAgwACQmAHPRBAPUBAAwACQmAHPRBAPUBAAAA.Vellion:BAAALgAECgEJAwAAAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Verrindyss:BAAALgAECgEJAgAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAACLgAFFH8KAAIBAAUJYxp3LwBOAQABAAUJYxp3LwBOAQAuAAQKfxoAAgEABglwJIMlAHECAAEABglwJIMlAHECAAAA.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAcJHQAEAI8ZAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBwABLgAECgkJFQAQAF8GAA==.',
Wi='Wikkid:BAABLgAECn83AAIQAAkJzxD4IACyAQAQAAkJzxD4IACyAQAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgUJDwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgEJAQAAAA==.',
Xx='Xxz:BAAALgADCgIJAgAAAA==.',
Xy='Xyon:BAAALgAECgEJAQAAAA==.',
Yi='Yiesus:BAABLgAFFH8IAAIOAAUJBwosEwA4AQAOAAUJBwosEwA4AQABLgAFFAgJLwABAGgkAA==.',
Ym='Ymir:BAABLgAECn8cAAMTAAgJkhP8DQDnAQATAAgJkhP8DQDnAQASAAQJDgST4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8JAAIXAAMJNQ8wPQC0AAAXAAMJNQ8wPQC0AAAuAAQKfzkAAhcACQmOHU8PANECABcACQmOHU8PANECAAAA.',
Yp='Yppah:BAABLgAECn8fAAIVAAkJ1w49MABwAQAVAAkJ1w49MABwAQAAAA==.',
Yu='Yuhmato:BAABLgAFFH8JAAIMAAIJ/BpFtACiAAAMAAIJ/BpFtACiAAAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQgAAgJIBBsKwCaAQAgAAcJThFsKwCaAQAfAAMJJAibaQBGAAAOAAEJhwpWYQA1AAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8dAAIBAAgJPRnbDQAkAgABAAgJPRnbDQAkAgAuAAQKfyMAAgEACAnGIxgNABcDAAEACAnGIxgNABcDAAAA.',
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
