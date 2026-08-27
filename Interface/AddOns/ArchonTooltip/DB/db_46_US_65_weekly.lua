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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Shaman-Enhancement','Shaman-Restoration','Hunter-Survival','Priest-Shadow','Druid-Guardian','Druid-Balance','Monk-Windwalker','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','Priest-Discipline','Mage-Fire','Monk-Mistweaver','DeathKnight-Frost','DeathKnight-Blood','Priest-Holy','Rogue-Outlaw','Hunter-Marksmanship','Evoker-Preservation','Evoker-Devastation','Warrior-Arms','DemonHunter-Vengeance',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH9OAAIBAAkJMx4OBADFAgABAAkJMx4OBADFAgAuAAQKfy0AAwEACQmnIeAQALsCAAEACQmnIeAQALsCAAIABwnaGMsjAJ8BAAAA.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAkJMQADACwYAA==.',
Ak='Akeno:BAAALgADCgYJBgAAAA==.',
Al='Alanestus:BAAALgADCgUJBQAAAA==.Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8jAAIEAAkJQyB/HgBvAgAEAAkJQyB/HgBvAgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Alice:BAAALgAECgEJAQAAAA==.Alius:BAAALgAFFAMJBAAAAA==.',
Am='Ambellina:BAACLgAFFH8LAAIGAAMJbhrRJQDzAAAGAAMJbhrRJQDzAAAuAAQKfzQAAwYACQnmG4cUAG4CAAYACQnmG4cUAG4CAAcABAnmCov8ALwAAAAA.Amp:BAAALgAECgEJAQABLgAFFAcJFQAIAMgQAA==.',
Ar='Ardreigh:BAAALgAECgEJAQAAAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.Ashlord:BAAALgAECgcJCwAAAA==.',
Au='Auxiliry:BAAALgAECgUJBQAAAA==.',
Av='Avenger:BAABLgAFFH8GAAIHAAQJRRgpPQAwAQAHAAQJRRgpPQAwAQABLgAFFAkJTAAJAOgkAA==.',
Ay='Aythrior:BAABLgAECn8WAAIKAAcJRB3LEADcAQAKAAcJRB3LEADcAQAAAA==.',
Ba='Bambiietta:BAACLgAFFH8UAAILAAQJAAVujADxAAALAAQJAAVujADxAAAuAAQKfxkAAgsABwnyCWCaAEsBAAsABwnyCWCaAEsBAAAA.',
Be='Beastsmaster:BAAALgAECgYJCwAAAA==.Beefycrits:BAACLgAFFH8SAAIMAAUJjSU3NACYAQAMAAUJjSU3NACYAQAuAAQKfycAAgwACQnpI8MXABwDAAwACQnpI8MXABwDAAAA.',
Bi='Bitt:BAAALgADCgEJAQAAAA==.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Blastoiz:BAABLgAECn8UAAMNAAgJmxYtAgDRAQANAAgJmxYtAgDRAQAOAAEJVAvTQAAiAAABLgAECggJHQAPAFkKAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgcJCwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.Brutalhunter:BAAALgADCgIJAgABLgAECgEJAQAFAAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Calmduke:BAAALgAECgIJBAAAAA==.Camilacream:BAAALgAECgEJAQAAAA==.Capriestson:BAACLgAFFH8KAAIQAAQJLQ5JHQAGAQAQAAQJLQ5JHQAGAQAuAAQKfzIAAhAACQksGgwQAFwCABAACQksGgwQAFwCAAAA.Cardrin:BAABLgAECn8iAAMRAAkJ7g9GIgA9AQARAAkJ7g9GIgA9AQASAAYJ4gPoWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH82AAITAAkJ/hsvAwDDAQATAAkJ/hsvAwDDAQAuAAQKfyAAAhMACAm+Ih8IAPgCABMACAm+Ih8IAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH84AAIMAAkJ2yCfAgAfAwAMAAkJ2yCfAgAfAwAAAA==.',
Cl='Clarence:BAAALgAECgUJCAAAAA==.Clearance:BAABLgAFFH8UAAIUAAYJPRqwGwCFAQAUAAYJPRqwGwCFAQABLgAFFAkJLgAVAMkXAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgQJBwAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQABLgAECgEJAwAFAAAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAwAFAAAAAA==.',
Da='Daboomdeath:BAAALgAFFAMJAgAAAA==.Daemon:BAACLgAFFH8xAAQDAAkJLBijAQCuAQADAAYJ/xmjAQCuAQAVAAgJDRGKCACgAQAWAAUJixIUCADrAAAuAAQKfz8ABAMACQkqJW4BAOkCAAMACQlRIm4BAOkCABUACQn/I/ISAOQCABYABAmpIZYEACoBAAAA.Dalînar:BAAALgAECgEJAQAAAA==.Darfswader:BAAALgADCgYJBgAAAA==.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAABLgAECn8dAAIPAAgJWQqWJQBwAQAPAAgJWQqWJQBwAQAAAA==.Dattsu:BAABLgAECn8aAAMWAAcJxhICLQAKAQAVAAcJBBKIgQA2AQAWAAUJDxACLQAKAQAAAA==.Dawnoxi:BAAALgADCggJCAAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Debockulus:BAABLgAECn8WAAIWAAYJYAz1BwDEAAAWAAYJYAz1BwDEAAAAAA==.Decenty:BAACLgAFFH8kAAIBAAcJ2Rl7JgCSAQABAAcJ2Rl7JgCSAQAuAAQKfyYAAwIACAl6IGMNAI0CAAIACAnoH2MNAI0CAAEACAmoG6UmAGsCAAAA.Deez:BAABLgAECn8UAAIVAAcJFgoaigBFAQAVAAcJFgoaigBFAQAAAA==.Demonen:BAAALgAECgYJDgABLgAFFAQJBwAVALEGAA==.Demonius:BAAALgADCgMJAwABLgAECgkJFQASAF8GAA==.Derangedxo:BAACLgAFFH9fAAQVAAkJWSVLAACPAgAVAAkJCyVLAACPAgADAAUJtSY+AQDIAQAWAAUJMxTSAQC9AQAuAAQKfygAAxUACQlSJp4CAJsDABUACQlSJp4CAJsDABYAAwmgI+olAC8BAAAA.Desirabelle:BAABLgAECn8WAAIBAAkJVBfBAwAfAgABAAkJVBfBAwAfAgAAAA==.',
Di='Dirty:BAAALgADCgYJCQABLgAECggJHgAXAOQTAA==.Diuoe:BAABLgAFFH8HAAMRAAMJXReqEACjAAARAAIJZByqEACjAAAYAAEJUA1TFgAlAAAAAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragocha:BAAALgAECgEJAQAAAA==.Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgUJCAAAAA==.Droth:BAAALgAECgMJAwAAAA==.Drunkenhoe:BAABLgAECn8UAAIHAAkJRBN8CQDdAQAHAAkJRBN8CQDdAQAAAA==.',
Du='Duskforger:BAABLgAECn8tAAISAAkJaw1MKACOAQASAAkJaw1MKACOAQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAITAAgJTBQnHQDxAQATAAgJTBQnHQDxAQAAAA==.Envyy:BAAALgAECgEJAgAAAA==.',
Ev='Everblack:BAACLgAFFH8VAAMDAAQJUBavBADtAAADAAMJIBivBADtAAAWAAMJExa5CwDhAAAuAAQKfzcAAhYACQmCH+wBALECABYACQmCH+wBALECAAAA.Everybagel:BAAALgADCgMJAwAAAA==.Evilcretin:BAACLgAFFH8KAAIMAAMJ8RzBJwAUAQAMAAMJ8RzBJwAUAQAuAAQKfzIAAgwABgn0I7RPAO0BAAwABgn0I7RPAO0BAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgAECgEJAQAAAA==.Falco:BAAALgADCgYJBgAAAA==.Faraah:BAACLgAFFH8yAAQYAAgJThlGAQDhAQAYAAcJDx1GAQDhAQARAAYJ6BCLCAANAQASAAEJLQdVKwBBAAAuAAQKf0sAAxgACQnoIfQCAO8CABgACQnoIfQCAO8CABkAAQnSBOvbACcAAAAA.',
Fl='Florleesa:BAAALgAECgEJAQAAAA==.Flowstate:BAABLgAFFH8VAAIIAAcJyBCnEwCGAQAIAAcJyBCnEwCGAQAAAA==.',
Fr='Friérén:BAACLgAFFH8PAAIMAAMJSxjVLwD2AAAMAAMJSxjVLwD2AAAuAAQKfyoAAwwACAmXHsxEAA0CAAwACAmXHsxEAA0CABoAAQm4BS0hACkAAAEuAAUUBAkHABUAsQYA.',
Ga='Garhkanis:BAABLgAFFH8MAAIVAAUJQiUbJgCxAQAVAAUJQiUbJgCxAQAAAA==.Garro:BAACLgAFFH8OAAIbAAQJORdjIQAtAQAbAAQJORdjIQAtAQAuAAQKfzEAAhsACAnrHl4SAGACABsACAnrHl4SAGACAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Generico:BAAALgADCgMJAwABLgAFFAkJdAAXABkjAA==.Geoph:BAAALgAECgIJAgAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Gn='Gnosis:BAAALgAECgEJAgAAAA==.',
Go='Goch:BAAALgAFFAEJAQAAAA==.Gochalufagus:BAAALgAECgEJAQAAAA==.Gochamoo:BAAALgAECgQJBAAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gp='Gp:BAAALgAECgQJCwAAAA==.',
Gr='Graud:BAABLgAFFH8GAAIUAAIJdxCGVQB0AAAUAAIJdxCGVQB0AAABLgAFFAMJBwARAF0XAA==.Graudel:BAABLgAFFH8HAAIbAAUJexXsHgA1AQAbAAUJexXsHgA1AQAAAA==.Graudier:BAAALgAFFAIJBAABLgAFFAIJBQAcAJYRAA==.Grimdark:BAABLgAECn8wAAIOAAgJiBqKGgB3AgAOAAgJiBqKGgB3AgAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAFFAIJAgAAAA==.Grumpypants:BAABLgAECn86AAIRAAkJ4Bf9DAASAgARAAkJ4Bf9DAASAgAAAA==.Grunge:BAACLgAFFH8JAAMVAAQJUQhcagDvAAAVAAQJUQhcagDvAAAWAAEJWAC8LQAeAAAuAAQKfygABBUACQmUGvMeAGsCABUACQmUGvMeAGsCABYABQmhENUjADoBAAMAAQk4GsQtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAIMAAgJMCGmIgDoAgAMAAgJMCGmIgDoAgAAAA==.',
Ha='Hairyhealer:BAAALgAECgYJCgAAAA==.Hammertime:BAAALgAECgIJBAAAAA==.Haven:BAABLgAECn8iAAIQAAkJAR74CQDjAgAQAAkJAR74CQDjAgAAAA==.',
He='Heathermarie:BAACLgAFFH8JAAIdAAUJvQsQBAC6AAAdAAUJvQsQBAC6AAAuAAQKf0kAAx0ACQlDIN4AAOYCAB0ACQlDIN4AAOYCAAwAAQmYF948AVAAAAAA.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Hi='Historia:BAABLgAFFH8HAAIVAAQJsQaCagDvAAAVAAQJsQaCagDvAAAAAA==.',
Ho='Holdmyhammer:BAAALgAECgEJAQAAAA==.Holdmytraps:BAAALgAECgUJBwAAAA==.Holypride:BAAALgAECgYJCAAAAA==.Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgAECgQJBQAAAA==.',
['Há']='Háppyelf:BAAALgAECgUJBQAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAACLgAFFH8JAAIeAAQJWxqgJgA5AQAeAAQJWxqgJgA5AQAuAAQKfxUAAx4ACAmIFl4hABECAB4ACAmIFl4hABECAAgAAwkKA7t1AGsAAAAA.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgcJCQAAAA==.Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8rAAIOAAkJlRC8QwCfAQAOAAkJlRC8QwCfAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH9DAAQDAAkJ6R2rAQCFAQAVAAcJWh7pCQAlAgADAAUJbCGrAQCFAQAWAAQJ2xdoBgAKAQAuAAQKfyQABAMACAn5Ii4FABsCABUACAkWIqsdAKQCAAMABQlrJS4FABsCABYAAgkYG2BEAKQAAAAA.Jamboni:BAACLgAFFH8GAAMLAAQJ6RUdiQD3AAALAAMJvBkdiQD3AAAfAAMJWQyeFgDVAAAuAAQKfxgAAyAABwmeIWISAOgBACAABwm4HGISAOgBAAsABQn7IAR/AGUBAAAA.Jarmamathu:BAAALgAECggJCwAAAA==.Jay:BAAALgAFFAIJAgABLgAFFAYJEQALAHkYAA==.',
Je='Jeisansan:BAAALgAECgEJAQAAAA==.',
Ji='Jimlaheys:BAABLgAECn8UAAMZAAgJxAVyawDyAAAZAAgJxAVyawDyAAASAAYJpgQtYACYAAAAAA==.',
Jo='Joje:BAABLgAECn8nAAMVAAkJdBh9JwA/AgAVAAkJdBh9JwA/AgAWAAIJVgmrWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgAECgEJAQAAAA==.Juniperdayne:BAAALgAFFAIJAgAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kalenn:BAAALgAECgEJAQAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgAECgUJBgAAAA==.',
Ke='Keltic:BAABLgAECn8fAAQcAAcJLRFINQBAAQAcAAcJUQ1INQBAAQAhAAYJ5g1LTQCtAAAQAAEJhgORlwAiAAAAAA==.Keora:BAABLgAECn8mAAIUAAkJxRInIgDJAQAUAAkJxRInIgDJAQAAAA==.',
Kh='Khronos:BAABLgAECn8zAAIUAAkJXxtBDQCJAgAUAAkJXxtBDQCJAgAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAABLgAFFH8FAAIcAAIJlhELPwB9AAAcAAIJlhELPwB9AAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Krethrik:BAAALgADCggJFAABLgAECgkJHwAUACkOAA==.Kronik:BAAALgAECgQJBQAAAA==.Krow:BAAALgAECgEJAQAAAA==.',
Ky='Kyrilos:BAAALgAECgEJAQAAAA==.',
['Kæ']='Kæli:BAAALgADCgUJBQAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAACLgAFFH8JAAMiAAMJNyHPBgAfAQAiAAMJNyHPBgAfAQAJAAIJBQRiOAB6AAAuAAQKfxUAAyIABglHF40KAHcBAAkABgmTEo8oALUBACIABQksGI0KAHcBAAAA.',
Le='Lereios:BAAALgAECgEJAQABLgAECggJDQAFAAAAAA==.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightimus:BAAALgADCgIJAgAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBwAAAA==.Lightsmith:BAABLgAECn8hAAMGAAkJbiCOGQBGAgAGAAkJbiCOGQBGAgAHAAMJ2xu31wDpAAAAAA==.Lightxsoul:BAAALgAECgEJAQAAAA==.Lilpump:BAABLgAFFH8JAAMBAAcJHASLUQA9AAABAAEJSxOLUQA9AAACAAcJ8wD4JAArAAAAAA==.Liyun:BAAALgAECgEJAQABLgAECgkJJgAUAMUSAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAwAAAA==.Lorez:BAACLgAFFH8cAAIVAAYJwg+EOQBkAQAVAAYJwg+EOQBkAQAuAAQKfxYAAhUACQnGGiRGAPkBABUACQnGGiRGAPkBAAAA.Low:BAABLgAECn8nAAIVAAgJKReiQgDTAQAVAAgJKReiQgDTAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn89AAINAAkJQhG7BAA9AQANAAkJQhG7BAA9AQAAAA==.Mageaurora:BAAALgAECgYJCQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Maysia:BAAALgADCgUJBQAAAA==.Mazzh:BAABLgAFFH8hAAQEAAgJIiFoCgAGAgAEAAcJECFoCgAGAgAPAAQJ4hdKCgDxAAAjAAUJJRv7GQDjAAABLgAFFAkJSAAMANAmAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Mem:BAABLgAECn8XAAMVAAYJ7ANYJgBiAAAVAAYJ7ANYJgBiAAAWAAUJIQDKSQAIAAAAAA==.Meowyn:BAAALgADCgcJBwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgAECgQJAgAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mikeybad:BAAALgAECgYJBwABLgAECgkJMgAgAK8gAA==.Minimage:BAAALgAECgEJAQAAAA==.Minipist:BAAALgAECgYJBgAAAA==.Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJGAsCXwCEAQABAAkJ6AoCXwCEAQACAAYJEAlKOwATAQAAAA==.',
Mo='Mode:BAAALgAECgEJAQABLgAFFAQJDwAeAMcbAA==.Moobie:BAAALgAECgYJEQABLgAFFAMJBAAFAAAAAA==.Moobiemist:BAABLgAECn8XAAMeAAcJcxh7BQD1AQAeAAcJcxh7BQD1AQATAAEJ8wMMKgAVAAABLgAFFAMJBAAFAAAAAA==.Mortikhan:BAAALgAECgYJCgAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Mu='Mumsydk:BAEALgAFFAIJAgABLgAFFAkJOQAZANgfAA==.',
Na='Narium:BAABLgAECn8jAAIcAAkJJRiJFgAjAgAcAAkJJRiJFgAjAgAAAA==.Narth:BAAALgAECgYJDwAAAA==.Navaren:BAAALgAFFAEJAQAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Niccâs:BAAALgAECgEJAQAAAA==.Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAgAAAA==.',
No='Noctilucent:BAAALgAECgYJEAAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECggJEQAAAA==.',
Or='Orknight:BAAALgAECgMJAwAAAA==.',
Ou='Ouch:BAAALgAECgUJCQAAAA==.',
Oz='Ozzie:BAAALgAECgEJAgAAAA==.',
Pa='Pallywix:BAAALgAECgMJAwAAAA==.Paredes:BAAALgAECgkJCwAAAA==.',
Pe='Peewee:BAAALgAECgIJAgAAAA==.Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAACLgAFFH8NAAILAAQJbRYRZQAtAQALAAQJbRYRZQAtAQAuAAQKfyAAAgsACAnJH1kyADUCAAsACAnJH1kyADUCAAEuAAUUCAkZABUAcRoA.',
Po='Police:BAABLgAFFH8FAAMXAAMJRRMKJgB+AAAXAAIJCxUKJgB+AAANAAEJug8kFgBAAAABLgAECggJGQAFAAAAAA==.Pompkin:BAAALgADCgQJBAABLgAFFAQJBwAVALEGAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8rAAINAAkJ8hohCQAsAgANAAkJ8hohCQAsAgAAAA==.Prophesy:BAACLgAFFH8GAAIHAAMJpAn7gAC0AAAHAAMJpAn7gAC0AAAuAAQKfyMAAgcACAmaHMIoAIICAAcACAmaHMIoAIICAAAA.Proteus:BAACLgAFFH8LAAILAAQJpwizhAD/AAALAAQJpwizhAD/AAAuAAQKfysAAwsACAlYF+xZALgBAAsACAlYF+xZALgBAB8ABAkXDLcOALcAAAAA.',
Pu='Puff:BAAALgAECgIJAgAAAA==.Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Rebeccalee:BAAALgADCgMJBQABLgAECgEJAQAFAAAAAA==.Reflex:BAAALgAECggJEQAAAA==.Retpar:BAAALgAECgYJBwABLgAFFAMJBwARAF0XAA==.Reventön:BAABLgAECn8rAAILAAkJ+g7EWwC0AQALAAkJ+g7EWwC0AQAAAA==.',
Rh='Rhaena:BAAALgAECgIJAgABLgAFFAkJMQADACwYAA==.Rhylie:BAAALgAFFAMJAwAAAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Rockandstone:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAABLgAECn8VAAMSAAkJXwZxQQAIAQASAAgJAQdxQQAIAQAZAAgJCATIhgDJAAAAAA==.',
['Rá']='Ráîstlin:BAABLgAFFH8LAAMMAAQJ3wYQRgCzAAAMAAQJVAYQRgCzAAAaAAEJAAbtCQAoAAAAAA==.',
['Ré']='Rédrumelite:BAAALgAECgQJBAAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJEwAAAA==.',
Sc='Scarletmoon:BAAALgAECgQJBAAAAA==.',
Se='Selro:BAAALgADCgIJAgAAAA==.Senada:BAABLgAECn8eAAIMAAgJcgPk0QDvAAAMAAgJcgPk0QDvAAAAAA==.Senkait:BAABLgAECn8vAAQXAAkJ/xucDgCEAgAXAAkJ/xucDgCEAgAOAAYJtxvROQCbAQANAAIJoBeoLgCDAAAAAA==.',
Sh='Shamoura:BAACLgAFFH9RAAIXAAkJ6BxcAQASAgAXAAkJ6BxcAQASAgAuAAQKfx0AAhcACAmcIzEJAP8CABcACAmcIzEJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shamyzz:BAAALgAECgEJAQAAAA==.Shinoa:BAAALgAECggJAwAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shlongtofoot:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAwAFAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sl='Slunks:BAABLgAFFH8FAAIBAAIJzAiNiwBsAAABAAIJzAiNiwBsAAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
Sn='Snipymonk:BAAALgAFFAEJAQAAAA==.',
So='Soulreaver:BAAALgAECgQJBQAAAA==.Soulszaura:BAACLgAFFH8jAAIHAAgJDhueCQA+AgAHAAgJDhueCQA+AgAuAAQKfzMAAgcACQluJAoSAAIDAAcACQluJAoSAAIDAAAA.',
Sp='Spinlo:BAAALgAFFAIJAgABLgAFFAkJNgATAP4bAA==.Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8VAAIBAAgJ8BZZKwB6AQABAAgJ8BZZKwB6AQAuAAQKfzEAAgEACQnaHwkRALoCAAEACQnaHwkRALoCAAAA.Steampunk:BAACLgAFFH8FAAIMAAMJjgNElgCjAAAMAAMJjgNElgCjAAAuAAQKfxgAAgwABwk8EOudAD4BAAwABwk8EOudAD4BAAAA.Stinkyfeet:BAAALgAECgEJAQAAAA==.',
Su='Suwanee:BAAALgAECgMJAwAAAA==.',
Sw='Swade:BAABLgAECn8dAAIIAAYJbhInCAC0AAAIAAYJbhInCAC0AAABLgAECggJHQAPAFkKAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAQJBwAVALEGAA==.Synarri:BAACLgAFFH9RAAMGAAkJlSCMCgANAgAGAAkJlSCMCgANAgAHAAYJbxwJDAC4AQAuAAQKf10AAwcACQmGJSUBAF8DAAcACQmGJSUBAF8DAAYACQkEHN4NAKkCAAEuAAUUCQlsAAYAyiMA.Syneria:BAACLgAFFH9sAAMGAAkJyiP5AAAXAwAGAAkJyiP5AAAXAwAHAAUJDht+FwA9AQAuAAQKf2gAAwcACQm2JeIAAGoDAAcACQm2JeIAAGoDAAYACQkaIkkLAMQCAAAA.Syneriah:BAAALgAFFAIJAgABLgAFFAkJbAAGAMojAA==.Synn:BAABLgAFFH8FAAMkAAIJaxqtFQBVAAAkAAIJaxqtFQBVAAAUAAEJjwFPbwAoAAABLgAFFAkJbAAGAMojAA==.Synpai:BAACLgAFFH8oAAMGAAgJQBwlBAA6AgAGAAcJ+holBAA6AgAHAAYJjRckEACCAQAuAAQKfywAAwcACQmQH14bAKACAAcACAmDIl4bAKACAAYABwkvGAQsANcBAAEuAAUUCQlsAAYAyiMA.',
['Sá']='Sázed:BAAALgADCgMJAwAAAA==.',
Ta='Taccitus:BAACLgAFFH8pAAMBAAkJUBOMGADtAQABAAgJyROMGADtAQACAAEJARDqGgBTAAAuAAQKfy4AAwEACQljIdEPAMQCAAEACQljIdEPAMQCAAIAAwk3F4o9AMAAAAAA.Taciitus:BAAALgAFFAEJAQAAAA==.Tailzz:BAAALgAECgcJDwAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAFFAEJAwAAAA==.',
Te='Teach:BAABLgAECn8kAAQUAAkJoRtgGgADAgAUAAcJbBtgGgADAgAkAAcJ1AwTJgC8AAAlAAIJfhjOBACXAAAAAA==.',
Th='Thelôpen:BAAALgAECgEJAQAAAA==.Thermafrost:BAAALgADCgMJAwAAAA==.Thuggdk:BAAALgAFFAEJAQABLgAFFAkJNgATAP4bAA==.Thuggjr:BAABLgAFFH8FAAMbAAMJ8AurOgDIAAAbAAMJHQqrOgDIAAAmAAIJLwc9HABmAAABLgAFFAkJNgATAP4bAA==.Thuggzxp:BAAALgAECgEJAQABLgAFFAkJNgATAP4bAA==.Thunderwar:BAABLgAECn8wAAQbAAcJqRZjDAAGAQAbAAUJthVjDAAGAQAKAAcJyBXMJQADAQAmAAEJsxBSHAAzAAAAAA==.Thunderwings:BAAALgADCgQJBAAAAA==.',
Ti='Tiazy:BAAALgAECgQJBwAAAA==.Tidepod:BAAALgAECgcJCAAAAA==.',
To='Toomato:BAAALgAECgQJBwAAAA==.Totemterror:BAEBLgAECn8lAAIOAAkJVibXAADRAwAOAAkJVibXAADRAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tr='Tracwave:BAAALgAECgUJDAAAAA==.',
Ts='Tsukimiya:BAABLgAFFH8KAAIBAAgJdBrbBACqAgABAAgJdBrbBACqAgAAAA==.',
Tx='Tx:BAAALgAECgYJCwAAAA==.',
Ty='Tydradul:BAACLgAFFH8OAAIVAAQJyAdVaAD0AAAVAAQJyAdVaAD0AAAuAAQKfywAAhUACQmTFSo0AAgCABUACQmTFSo0AAgCAAAA.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAACLgAFFH8OAAIZAAMJGhJoHACQAAAZAAMJGhJoHACQAAAuAAQKfzwAAxkACQk1HtkKABADABkACQk1HtkKABADABgABQk5FEEbADMBAAAA.Valy:BAABLgAECn8fAAMcAAgJahdSFQAwAgAcAAgJahdSFQAwAgAhAAEJzAwbcgArAAAAAA==.',
Ve='Veladria:BAACLgAFFH8OAAILAAYJ2RQHRgBoAQALAAYJ2RQHRgBoAQAuAAQKfxwAAgsACQmAHBZHAO0BAAsACQmAHBZHAO0BAAAA.Vellion:BAAALgAECgEJAwAAAA==.Velynn:BAAALgAECgQJBAABLgAFFAYJDgALANkUAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Verrindyss:BAAALgAECgEJAgAAAA==.',
Vi='Violenthighz:BAAALgADCgYJBgAAAA==.Violet:BAAALgADCgQJAQAAAA==.Violetfairie:BAAALgAECgYJCgABLgAECgYJFwAVAOwDAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Volcanis:BAAALgAECgEJAgAAAA==.Vora:BAAALgAFFAEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAACLgAFFH8OAAIBAAUJYxq/NwBFAQABAAUJYxq/NwBFAQAuAAQKfxoAAgEABglwJIMlAHECAAEABglwJIMlAHECAAAA.Waymond:BAAALgADCgMJAwABLgAECgEJAgAFAAAAAA==.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAkJQwADAOkdAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBwABLgAECgkJFQASAF8GAA==.',
Wi='Wikkid:BAACLgAFFH8FAAISAAIJuwQsJgBaAAASAAIJuwQsJgBaAAAuAAQKf0cAAhIACQmUF5wFAJgBABIACQmUF5wFAJgBAAAA.Wikkidsin:BAAALgADCgQJBAABLgAFFAIJBQASALsEAA==.Wikyd:BAAALgAECgQJBAABLgAFFAIJBQASALsEAA==.Windowpain:BAAALgAECgQJBAAAAA==.Winrawr:BAAALgAECgEJAwABLgAECggJDQAFAAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgUJEwAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgIJAgAAAA==.',
Xx='Xxz:BAAALgADCgMJBQAAAA==.',
Xy='Xyon:BAAALgAECgEJAQAAAA==.',
Ya='Yagami:BAABLgAECn8hAAQBAAgJ5iAdHwBaAgABAAgJrR4dHwBaAgACAAQJGyLyJgCJAQAnAAUJFR5RDwBdAQAAAA==.Yaldabaoth:BAAALgADCgcJBwAAAA==.',
Yi='Yiesus:BAABLgAFFH8IAAIQAAUJBwrOFQA2AQAQAAUJBwrOFQA2AQABLgAFFAkJPwABAOEkAA==.',
Ym='Ymir:BAABLgAECn8cAAMWAAgJkhP8DQDnAQAWAAgJkhP8DQDnAQAVAAQJDgST4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8JAAIZAAMJNQ/TQgCnAAAZAAMJNQ/TQgCnAAAuAAQKfzkAAhkACQmOHTEQANECABkACQmOHTEQANECAAAA.',
Yp='Yppah:BAABLgAECn8fAAIXAAkJ1w5uMwBuAQAXAAkJ1w5uMwBuAQAAAA==.',
Yu='Yuhmato:BAABLgAFFH8JAAILAAIJ/Bo6ygCZAAALAAIJ/Bo6ygCZAAAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Ze='Zenocline:BAAALgAECgEJAQAAAA==.Zephyroot:BAAALgAECgcJCQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQhAAgJIBBsKwCaAQAhAAcJThFsKwCaAQAcAAMJJAjwcgBCAAAQAAEJhwpWYQA1AAAAAA==.Zons:BAAALgAECgEJAQAAAA==.Zoodu:BAAALgAECgQJBAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zushakon:BAAALgADCgUJBQAAAA==.Zuzana:BAACLgAFFH8dAAIBAAgJPRkgFAAPAgABAAgJPRkgFAAPAgAuAAQKfyMAAgEACAnGIxgNABcDAAEACAnGIxgNABcDAAAA.',
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
