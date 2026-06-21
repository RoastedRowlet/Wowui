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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Hunter-Survival','Priest-Shadow','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Monk-Mistweaver','DeathKnight-Frost','DeathKnight-Blood','Priest-Discipline','Priest-Holy','Rogue-Outlaw','Shaman-Enhancement','Hunter-Marksmanship','Evoker-Preservation',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH83AAIBAAcJZyO5CgBwAgABAAcJZyO5CgBwAgAuAAQKfykAAwEACQmSH+IQALsCAAEACQmSH+IQALsCAAIABwnaGMsjAJ8BAAEuAAUUCQk8AAMAZiAA.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAgJLAAEAA0bAA==.',
Al='Alanestus:BAAALgADCgUJBQAAAA==.Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8jAAIFAAkJQyCBHgBvAgAFAAkJQyCBHgBvAgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.Alius:BAAALgAECgYJDQAAAA==.',
Am='Ambellina:BAACLgAFFH8LAAIHAAMJbhrVJQDzAAAHAAMJbhrVJQDzAAAuAAQKfzQAAwcACQnmG4cUAG4CAAcACQnmG4cUAG4CAAgABAnmCob8ALwAAAAA.Amp:BAAALgAECgEJAQABLgAFFAcJFQAJAMgQAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.Ashlord:BAAALgAECgcJCwAAAA==.',
Au='Auxiliry:BAAALgAECgUJBQAAAA==.',
Av='Avenger:BAABLgAFFH8GAAIIAAQJRRgyPQAwAQAIAAQJRRgyPQAwAQABLgAFFAkJQwAKAMEiAA==.',
Ay='Aythrior:BAABLgAECn8WAAILAAcJRB3MEADcAQALAAcJRB3MEADcAQAAAA==.',
Ba='Bambiietta:BAACLgAFFH8SAAIMAAQJAAWgDQCpAAAMAAQJAAWgDQCpAAAuAAQKfxkAAgwABwnyCWCaAEsBAAwABwnyCWCaAEsBAAAA.',
Be='Beastsmaster:BAAALgAECgYJCwAAAA==.Beefycrits:BAACLgAFFH8SAAINAAUJjSVWNACYAQANAAUJjSVWNACYAQAuAAQKfycAAg0ACQnpI8MXABwDAA0ACQnpI8MXABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Blastoiz:BAAALgAECgYJBQABLgAECggJHQAOAFkKAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgcJCwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Calmduke:BAAALgAECgIJBAAAAA==.Camilacream:BAAALgAECgEJAQAAAA==.Capriestson:BAACLgAFFH8KAAIPAAQJLQ5JHQAGAQAPAAQJLQ5JHQAGAQAuAAQKfzIAAg8ACQksGgwQAFwCAA8ACQksGgwQAFwCAAAA.Cardrin:BAABLgAECn8iAAMQAAkJ7g9GIgA9AQAQAAkJ7g9GIgA9AQARAAYJ4gPoWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8hAAIDAAYJSRtuBwCgAQADAAYJSRtuBwCgAQAuAAQKfyAAAgMACAm+Ih8IAPgCAAMACAm+Ih8IAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH8tAAINAAkJ9B+hAgAfAwANAAkJ9B+hAgAfAwAAAA==.',
Cl='Clarence:BAAALgAECgUJCAAAAA==.Clearance:BAABLgAFFH8SAAISAAYJxBfnGwCDAQASAAYJxBfnGwCDAQABLgAFFAgJJQATAAMaAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgQJBwAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQABLgAECgEJAwAGAAAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.',
Da='Daboomdeath:BAAALgAFFAMJAgAAAA==.Daemon:BAACLgAFFH8sAAQEAAgJDRujAQCuAQAEAAYJ/xmjAQCuAQATAAcJOROKCACgAQAUAAUJixIUCADrAAAuAAQKfzgABAQACQnqJG4BAOkCAAQACQlRIm4BAOkCABMACQlCI/ISAOQCABQAAwk5FI4xAPMAAAAA.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAABLgAECn8dAAIOAAgJWQqVJQBwAQAOAAgJWQqVJQBwAQAAAA==.Dattsu:BAABLgAECn8aAAMUAAcJxhICLQAKAQATAAcJBBKFgQA2AQAUAAUJDxACLQAKAQAAAA==.Dawnoxi:BAAALgADCggJCAAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgYJDgABLgAFFAQJBwATALEGAA==.Demonius:BAAALgADCgMJAwABLgAECgkJFQARAF8GAA==.Derangedxo:BAACLgAFFH9OAAQTAAkJWyRLAACPAgATAAkJAyRLAACPAgAEAAUJtSY+AQDIAQAUAAUJMxTSAQC9AQAuAAQKfyQAAxMACQlOJp4CAJsDABMACQlOJp4CAJsDABQAAwmgI+olAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgAVAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.Drunkenhoe:BAAALgAECgQJBQAAAA==.',
Du='Duskforger:BAABLgAECn8tAAIRAAkJaw1KKACOAQARAAkJaw1KKACOAQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAIDAAgJTBQnHQDxAQADAAgJTBQnHQDxAQAAAA==.',
Ev='Everblack:BAACLgAFFH8PAAMEAAQJUBZFAQCWAAAUAAMJExa9CwDhAAAEAAIJyhJFAQCWAAAuAAQKfzcAAhQACQmCH+wBALECABQACQmCH+wBALECAAAA.Evilcretin:BAACLgAFFH8KAAINAAMJ8RzBJwAUAQANAAMJ8RzBJwAUAQAuAAQKfzAAAg0ABgn0I7RPAO0BAA0ABgn0I7RPAO0BAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Falco:BAAALgADCgYJBgAAAA==.Faraah:BAACLgAFFH8ZAAMWAAUJAx7tBABoAQAWAAUJAx7tBABoAQAQAAMJCwy2IQCVAAAuAAQKf0sAAxYACQnoIfQCAO8CABYACQnoIfQCAO8CABcAAQnSBOvbACcAAAAA.',
Fl='Florleesa:BAAALgADCgYJCAAAAA==.Flowstate:BAABLgAFFH8VAAIJAAcJyBCvEwCGAQAJAAcJyBCvEwCGAQAAAA==.',
Fr='Friérén:BAACLgAFFH8PAAINAAMJSxjVLwD2AAANAAMJSxjVLwD2AAAuAAQKfyoAAw0ACAmXHs9EAA0CAA0ACAmXHs9EAA0CABgAAQm4BS0hACkAAAEuAAUUBAkHABMAsQYA.',
Ga='Garhkanis:BAABLgAFFH8LAAITAAQJQiVIJgCwAQATAAQJQiVIJgCwAQAAAA==.Garro:BAACLgAFFH8OAAIZAAQJORdmIQAtAQAZAAQJORdmIQAtAQAuAAQKfywAAhkACAnrHl4SAGACABkACAnrHl4SAGACAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Generico:BAAALgADCgMJAwABLgAECgUJDAAGAAAAAA==.Genjidh:BAABLgAECn8hAAQBAAgJ5iAfHwBaAgABAAgJrR4fHwBaAgACAAQJGyLyJgCJAQAaAAUJFR5RDwBdAQAAAA==.Geoph:BAAALgAECgIJAgAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgAECgQJBAAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gp='Gp:BAAALgAECgQJCAAAAA==.',
Gr='Graud:BAABLgAFFH8GAAISAAIJdxCGVQB0AAASAAIJdxCGVQB0AAAAAA==.Graudel:BAABLgAFFH8HAAIZAAUJexXyHgA1AQAZAAUJexXyHgA1AQAAAA==.Grimdark:BAABLgAECn8wAAIbAAgJiBqJGgB3AgAbAAgJiBqJGgB3AgAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAFFAIJAgAAAA==.Grumpypants:BAABLgAECn86AAIQAAkJ4Bf9DAASAgAQAAkJ4Bf9DAASAgAAAA==.Grunge:BAACLgAFFH8JAAMTAAQJUQhzagDvAAATAAQJUQhzagDvAAAUAAEJWAC9LQAeAAAuAAQKfygABBMACQmUGvMeAGsCABMACQmUGvMeAGsCABQABQmhENUjADoBAAQAAQk4GsQtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAINAAgJMCGmIgDoAgANAAgJMCGmIgDoAgAAAA==.',
Ha='Hairyhealer:BAAALgAECgYJCgAAAA==.Hammertime:BAAALgAECgEJAgAAAA==.Haven:BAABLgAECn8iAAIPAAkJAR74CQDjAgAPAAkJAR74CQDjAgAAAA==.',
He='Heathermarie:BAACLgAFFH8GAAIcAAMJYQ4RBAC6AAAcAAMJYQ4RBAC6AAAuAAQKf0kAAxwACQlDIN4AAOYCABwACQlDIN4AAOYCAA0AAQmYF9k8AVAAAAAA.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Hi='Historia:BAABLgAFFH8HAAITAAQJsQaaagDvAAATAAQJsQaaagDvAAAAAA==.',
Ho='Holdmytraps:BAAALgAECgUJBwAAAA==.Holypride:BAAALgAECgYJBwAAAA==.Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgAECgQJBQAAAA==.',
['Há']='Háppyelf:BAAALgAECgUJBQAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAACLgAFFH8IAAIdAAQJhhmcJgA5AQAdAAQJhhmcJgA5AQAuAAQKfxUAAx0ACAmIFl8hABECAB0ACAmIFl8hABECAAkAAwkKA7t1AGsAAAAA.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgcJCQAAAA==.Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8rAAIbAAkJlRC4QwCfAQAbAAkJlRC4QwCfAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8dAAQEAAcJjxkcAwBqAQAEAAQJLB8cAwBqAQATAAUJuBlWEABeAQAUAAQJzRdoBgAKAQAuAAQKfyQABAQACAn5Ii4FABsCABMACAkWIqsdAKQCAAQABQlrJS4FABsCABQAAgkYG2BEAKQAAAAA.Jamboni:BAACLgAFFH8GAAMMAAQJ6RUliQD3AAAMAAMJvBkliQD3AAAeAAMJWQyeFgDVAAAuAAQKfxgAAx8ABwmeIWISAOgBAB8ABwm4HGISAOgBAAwABQn7IP9+AGUBAAAA.Jarmamathu:BAAALgAECggJCwAAAA==.Jay:BAAALgAFFAIJAgAAAA==.',
Ji='Jimlaheys:BAABLgAECn8UAAMXAAgJxAV0awDyAAAXAAgJxAV0awDyAAARAAYJpgQmYACYAAAAAA==.',
Jo='Joje:BAABLgAECn8mAAMTAAkJdBh9JwA/AgATAAkJdBh9JwA/AgAUAAIJVgmrWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgAECgEJAQAAAA==.Juniperdayne:BAAALgAFFAEJAQAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAABLgAECn8dAAQgAAcJLRFINQBAAQAgAAcJUQ1INQBAAQAhAAYJ5g1FTQCtAAAPAAEJhgOKlwAiAAAAAA==.Keora:BAABLgAECn8mAAISAAkJxRImIgDJAQASAAkJxRImIgDJAQAAAA==.',
Kh='Khronos:BAABLgAECn8wAAISAAkJ2hpCDQCJAgASAAkJ2hpCDQCJAgAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAABLgAFFH8FAAIgAAIJlhEPPwB9AAAgAAIJlhEPPwB9AAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Krethrik:BAAALgADCggJFAABLgAECggJFgASAEcKAA==.Kronik:BAAALgAECgQJBQAAAA==.Krow:BAAALgAECgEJAQAAAA==.',
['Kæ']='Kæli:BAAALgADCgUJBQAAAA==.',
La='Large:BAACLgAFFH8JAAMiAAMJNyHPBgAfAQAiAAMJNyHPBgAfAQAKAAIJBQRjOAB6AAAuAAQKfxUAAyIABglHF40KAHcBAAoABgmTEo8oALUBACIABQksGI0KAHcBAAAA.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightimus:BAAALgADCgIJAgAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBwAAAA==.Lightsmith:BAABLgAECn8hAAMHAAkJbiCOGQBGAgAHAAkJbiCOGQBGAgAIAAMJ2xu41wDpAAAAAA==.Lilpump:BAABLgAFFH8HAAICAAcJ8wBVBgAuAAACAAcJ8wBVBgAuAAAAAA==.Liyun:BAAALgAECgEJAQABLgAECgkJJgASAMUSAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAwAAAA==.Lorez:BAACLgAFFH8cAAITAAYJwg+mOQBkAQATAAYJwg+mOQBkAQAuAAQKfxYAAhMACQnGGiRGAPkBABMACQnGGiRGAPkBAAAA.Low:BAABLgAECn8mAAITAAgJKRehQgDUAQATAAgJKRehQgDUAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn8zAAIjAAkJQhGLDQDXAQAjAAkJQhGLDQDXAQAAAA==.Mageaurora:BAAALgAECgYJCQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Maysia:BAAALgADCgUJBQAAAA==.Mazzh:BAABLgAFFH8WAAMFAAYJOSITJAB1AQAFAAUJZCITJAB1AQAkAAUJJRsJGgDjAAABLgAFFAkJHgANANMkAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Mem:BAAALgAECgYJEgAAAA==.Meowyn:BAAALgADCgcJBwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgAECgQJAgAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mikeybad:BAAALgAECgEJAgABLgAECgkJIgAMAIogAA==.Minimage:BAAALgAECgEJAQAAAA==.Minipist:BAAALgAECgYJBgAAAA==.Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJGAsCXwCEAQABAAkJ6AoCXwCEAQACAAYJEAlKOwATAQAAAA==.',
Mo='Moobie:BAAALgAECgYJEQABLgAFFAMJAwAGAAAAAA==.Moobiemist:BAAALgAECgcJEAABLgAFFAMJAwAGAAAAAA==.Mortikhan:BAAALgAECgYJCgAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Mu='Mumsydk:BAEALgAFFAIJAgABLgAFFAkJNAAXANgfAA==.',
Na='Narium:BAABLgAECn8jAAIgAAkJJRiHFgAjAgAgAAkJJRiHFgAjAgAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Niccâs:BAAALgAECgEJAQAAAA==.Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAgAAAA==.',
No='Noctilucent:BAAALgAECgUJBwAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgMJAwAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Oz='Ozzie:BAAALgAECgEJAgAAAA==.',
Pa='Pallywix:BAAALgAECgMJAwAAAA==.Paredes:BAAALgAECgcJCQAAAA==.',
Pe='Peewee:BAAALgAECgIJAgAAAA==.Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAACLgAFFH8NAAIMAAQJbRYYZQAtAQAMAAQJbRYYZQAtAQAuAAQKfyAAAgwACAnJH1cyADUCAAwACAnJH1cyADUCAAEuAAUUCAkZABMAcRoA.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAQJBwATALEGAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8rAAIjAAkJ8hohCQAsAgAjAAkJ8hohCQAsAgAAAA==.Prophesy:BAACLgAFFH8GAAIIAAMJpAkFgQC0AAAIAAMJpAkFgQC0AAAuAAQKfyMAAggACAmaHMIoAIICAAgACAmaHMIoAIICAAAA.Proteus:BAACLgAFFH8LAAIMAAQJpwi5hAD/AAAMAAQJpwi5hAD/AAAuAAQKfyoAAwwACAlYF+lZALgBAAwACAlYF+lZALgBAB4ABAkXDLcOALcAAAAA.',
Pu='Puff:BAAALgAECgIJAgAAAA==.Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Reflex:BAAALgAECggJEQAAAA==.Retpar:BAAALgAECgYJBwABLgAFFAIJBgASAHcQAA==.Reventön:BAABLgAECn8rAAIMAAkJ+g7DWwC0AQAMAAkJ+g7DWwC0AQAAAA==.',
Rh='Rhaena:BAAALgAECgIJAgABLgAFFAgJLAAEAA0bAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAABLgAECn8VAAMRAAkJXwZsQQAIAQARAAgJAQdsQQAIAQAXAAgJCATIhgDJAAAAAA==.',
['Rá']='Ráîstlin:BAAALgAFFAEJAQAAAA==.',
['Ré']='Rédrumelite:BAAALgAECgQJBAAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJEAAAAA==.',
Se='Selro:BAAALgADCgIJAgAAAA==.Senada:BAABLgAECn8eAAINAAgJcgPd0QDvAAANAAgJcgPd0QDvAAAAAA==.Senkait:BAABLgAECn8vAAQVAAkJ/xubDgCEAgAVAAkJ/xubDgCEAgAbAAYJtxvROQCbAQAjAAIJoBenLgCDAAAAAA==.',
Sh='Shamoura:BAACLgAFFH8uAAIVAAgJyBhcAQASAgAVAAgJyBhcAQASAgAuAAQKfx0AAhUACAmcIzEJAP8CABUACAmcIzEJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shamyzz:BAAALgAECgEJAQAAAA==.Shinoa:BAAALgAECgcJAQAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shlongtofoot:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sl='Slunks:BAABLgAFFH8FAAIBAAIJzAiViwBsAAABAAIJzAiViwBsAAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulreaver:BAAALgAECgQJBQAAAA==.Soulszaura:BAACLgAFFH8jAAIIAAgJDhuiCQA+AgAIAAgJDhuiCQA+AgAuAAQKfzEAAggACQkhIgoSAAIDAAgACQkhIgoSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8UAAIBAAcJ/xhsKwB6AQABAAcJ/xhsKwB6AQAuAAQKfzEAAgEACQnaHwsRALoCAAEACQnaHwsRALoCAAAA.Steampunk:BAACLgAFFH8FAAINAAMJjgNTlgCjAAANAAMJjgNTlgCjAAAuAAQKfxgAAg0ABwk8EOmdAD4BAA0ABwk8EOmdAD4BAAAA.',
Su='Suwanee:BAAALgAECgMJAwAAAA==.',
Sw='Swade:BAABLgAECn8aAAIJAAYJ7wzrRQDjAAAJAAYJ7wzrRQDjAAABLgAECggJHQAOAFkKAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAQJBwATALEGAA==.Synarri:BAACLgAFFH8iAAMHAAUJHCWQCgANAgAHAAUJHCWQCgANAgAIAAMJNBjPXwDwAAAuAAQKf0oAAwgACQkkItUMAP4CAAgACQkkItUMAP4CAAcACQkEHN4NAKkCAAEuAAUUCAkxAAcABh8A.Syneria:BAACLgAFFH8xAAMHAAgJBh8FAQAZAgAHAAgJBh8FAQAZAgAIAAUJvBZ8PAAyAQAuAAQKf1QAAwgACQk4JcsFAEUDAAgACQk4JcsFAEUDAAcACAkTIkkLAMQCAAAA.Synn:BAAALgAFFAIJAwABLgAFFAgJMQAHAAYfAA==.Synpai:BAACLgAFFH8NAAMHAAQJABi3JAD7AAAHAAQJABi3JAD7AAAIAAIJQA7ClACLAAAuAAQKfyoAAwgACQlpH10bAKACAAgACAlWIl0bAKACAAcABwkvGAQsANcBAAEuAAUUCAkxAAcABh8A.',
['Sá']='Sázed:BAAALgADCgMJAwAAAA==.',
Ta='Taccitus:BAACLgAFFH8oAAIBAAgJyROcGADtAQABAAgJyROcGADtAQAuAAQKfy4AAwEACQljIdMPAMQCAAEACQljIdMPAMQCAAIAAwk3F4g9AMAAAAAA.Taciitus:BAAALgAFFAEJAQAAAA==.Tailzz:BAAALgAECgcJDwAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAFFAEJAwAAAA==.',
Te='Teach:BAABLgAECn8hAAMSAAkJYhlhGgADAgASAAcJHxphGgADAgAlAAcJ1AwTJgC8AAAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thuggjr:BAAALgAFFAMJAwABLgAFFAYJIQADAEkbAA==.Thuggzxp:BAAALgAECgEJAQABLgAFFAYJIQADAEkbAA==.Thunderwar:BAABLgAECn8bAAILAAYJDBjMJQADAQALAAYJDBjMJQADAQAAAA==.',
Ti='Tiazy:BAAALgAECgQJBwAAAA==.Tidepod:BAAALgAECgcJCAAAAA==.',
To='Toomato:BAAALgAECgQJBwAAAA==.Totemterror:BAEBLgAECn8lAAIbAAkJVibXAADRAwAbAAkJVibXAADRAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tx='Tx:BAAALgAECgYJCwAAAA==.',
Ty='Tydradul:BAACLgAFFH8MAAITAAQJyAduaAD0AAATAAQJyAduaAD0AAAuAAQKfywAAhMACQmTFSk0AAgCABMACQmTFSk0AAgCAAAA.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAACLgAFFH8HAAIXAAMJSA+KQgCoAAAXAAMJSA+KQgCoAAAuAAQKfzwAAxcACQk1HtkKABADABcACQk1HtkKABADABYABQk5FD0bADMBAAAA.Valy:BAABLgAECn8fAAMgAAgJahdRFQAwAgAgAAgJahdRFQAwAgAhAAEJzAwXcgArAAAAAA==.',
Ve='Veladria:BAACLgAFFH8OAAIMAAYJ2RQKRgBoAQAMAAYJ2RQKRgBoAQAuAAQKfxwAAgwACQmAHBJHAO0BAAwACQmAHBJHAO0BAAAA.Vellion:BAAALgAECgEJAwAAAA==.Velynn:BAAALgAECgQJBAABLgAFFAYJDgAMANkUAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Verrindyss:BAAALgAECgEJAgAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAACLgAFFH8KAAIBAAUJYxrINwBFAQABAAUJYxrINwBFAQAuAAQKfxoAAgEABglwJIMlAHECAAEABglwJIMlAHECAAAA.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAcJHQAEAI8ZAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBwABLgAECgkJFQARAF8GAA==.',
Wi='Wikkid:BAABLgAECn86AAIRAAkJsxGDIwCuAQARAAkJsxGDIwCuAQAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgUJEwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgEJAQAAAA==.',
Xx='Xxz:BAAALgADCgMJBQAAAA==.',
Xy='Xyon:BAAALgAECgEJAQAAAA==.',
Ya='Yaldabaoth:BAAALgADCgcJBwAAAA==.',
Yi='Yiesus:BAABLgAFFH8IAAIPAAUJBwrPFQA2AQAPAAUJBwrPFQA2AQABLgAFFAgJMgABAGgkAA==.',
Ym='Ymir:BAABLgAECn8cAAMUAAgJkhP8DQDnAQAUAAgJkhP8DQDnAQATAAQJDgST4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8JAAIXAAMJNQ/aQgCnAAAXAAMJNQ/aQgCnAAAuAAQKfzkAAhcACQmOHTEQANECABcACQmOHTEQANECAAAA.',
Yp='Yppah:BAABLgAECn8fAAIVAAkJ1w5sMwBuAQAVAAkJ1w5sMwBuAQAAAA==.',
Yu='Yuhmato:BAABLgAFFH8JAAIMAAIJ/BpDygCZAAAMAAIJ/BpDygCZAAAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Ze='Zenocline:BAAALgAECgEJAQAAAA==.Zephyroot:BAAALgAECgIJAgAAAA==.',
Zo='Zod:BAABLgAECn8UAAQhAAgJIBBsKwCaAQAhAAcJThFsKwCaAQAgAAMJJAjucgBCAAAPAAEJhwpWYQA1AAAAAA==.Zons:BAAALgAECgEJAQAAAA==.Zoodu:BAAALgAECgQJBAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8dAAIBAAgJPRkxFAAPAgABAAgJPRkxFAAPAgAuAAQKfyMAAgEACAnGIxgNABcDAAEACAnGIxgNABcDAAAA.',
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
