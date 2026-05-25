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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Rogue-Outlaw','Shaman-Enhancement','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Frost','Evoker-Preservation',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8eAAIBAAcJdhaDDQDmAQABAAcJdhaDDQDmAQAuAAQKfyUAAwEACQnWHXkdAEYCAAEACQnWHXkdAEYCAAIABwnaGMsjAJ8BAAEuAAUUCQknAAMArRsA.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAgJLAAEAA0bAA==.',
Al='Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8jAAIFAAkJQyC6EwCKAgAFAAkJQyC6EwCKAgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.Alius:BAAALgAECgIJAwAAAA==.',
Am='Ambellina:BAACLgAFFH8JAAIHAAMJbhoLHQAHAQAHAAMJbhoLHQAHAQAuAAQKfzAAAwcACQnLG4cUAG4CAAcACQnLG4cUAG4CAAgABAnmCn7RAMsAAAAA.Amp:BAAALgAECgEJAQABLgAFFAUJEQAJAFcQAA==.',
Ar='Aravalia:BAAALgADCgEJAQAAAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.Ashlord:BAAALgADCgEJAQAAAA==.',
Au='Auxiliry:BAAALgADCgEJAQAAAA==.',
Av='Avenger:BAABLgAFFH8GAAIIAAQJRRjRJABHAQAIAAQJRRjRJABHAQABLgAFFAkJLAAKAOEgAA==.',
Ay='Aythrior:BAABLgAECn8WAAILAAcJRB0zDQDwAQALAAcJRB0zDQDwAQAAAA==.',
Ba='Bambiietta:BAACLgAFFH8IAAIMAAQJ7QJlcADqAAAMAAQJ7QJlcADqAAAuAAQKfxkAAgwABwnyCWCaAEsBAAwABwnyCWCaAEsBAAAA.',
Be='Beastsmaster:BAAALgAECgEJAQAAAA==.Beefycrits:BAACLgAFFH8OAAINAAQJjSWUIQCcAQANAAQJjSWUIQCcAQAuAAQKfycAAg0ACQnpI8MXABwDAA0ACQnpI8MXABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgYJBwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Calmduke:BAAALgAECgIJAgAAAA==.Capriestson:BAABLgAECn8tAAIOAAgJ3xh/FAAFAgAOAAgJ3xh/FAAFAgAAAA==.Cardrin:BAABLgAECn8iAAMPAAkJ7g+GGABLAQAPAAkJ7g+GGABLAQAQAAYJ4gPoWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8dAAIDAAYJ/hiaBACcAQADAAYJ/hiaBACcAQAuAAQKfyAAAgMACAm+Ih8IAPgCAAMACAm+Ih8IAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH8RAAINAAYJXB+IGwC3AQANAAYJXB+IGwC3AQAAAA==.',
Cl='Clarence:BAAALgAECgUJCAAAAA==.Clearance:BAABLgAFFH8PAAIRAAUJDBNUHgAkAQARAAUJDBNUHgAkAQABLgAFFAgJIQASAKUYAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgQJBwAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQABLgAECgEJAwAGAAAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.',
Da='Daemon:BAACLgAFFH8sAAQEAAgJDRtuAADXAQAEAAYJ/xluAADXAQASAAcJOROKCACgAQATAAUJixIUCADrAAAuAAQKfzcABAQACQnaJMIAAAIDAAQACQlRIsIAAAIDABIACQkzI/ISAOQCABMAAwk5FI4xAPMAAAAA.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAABLgAECn8cAAIUAAcJowu/JABWAQAUAAcJowu/JABWAQAAAA==.Dattsu:BAABLgAECn8aAAMTAAcJxhICLQAKAQASAAcJBBK5bgBGAQATAAUJDxACLQAKAQAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgYJDgABLgAFFAMJDwANAEsYAA==.Demonius:BAAALgADCgMJAwABLgAECgkJFQAQAF8GAA==.Derangedxo:BAACLgAFFH82AAQSAAkJMCMrAABKAwASAAkJBiMrAABKAwATAAUJMxTSAQC9AQAEAAQJniYBAgBcAQAuAAQKfyMAAxIACQlOJp4CAJsDABIACQlOJp4CAJsDABMAAwmgI+olAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgAVAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.',
Du='Duskforger:BAABLgAECn8tAAIQAAkJaw05IACZAQAQAAkJaw05IACZAQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAIDAAgJTBQnHQDxAQADAAgJTBQnHQDxAQAAAA==.',
Ev='Everblack:BAACLgAFFH8FAAMTAAMJuRutCgCzAAATAAIJER6tCgCzAAAEAAEJBxcOFQBSAAAuAAQKfzUAAhMACQlRH0EBAL4CABMACQlRH0EBAL4CAAAA.Evilcretin:BAACLgAFFH8KAAINAAMJ8RzBJwAUAQANAAMJ8RzBJwAUAQAuAAQKfy0AAg0ABgn0I7pHAOgBAA0ABgn0I7pHAOgBAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Falco:BAAALgADCgYJBgAAAA==.Faraah:BAACLgAFFH8FAAIWAAMJZxUBCQDwAAAWAAMJZxUBCQDwAAAuAAQKf0sAAxYACQnoIcQBAAEDABYACQnoIcQBAAEDABcAAQnSBOvbACcAAAAA.',
Fl='Florleesa:BAAALgADCgYJCAAAAA==.Flowstate:BAABLgAFFH8RAAIJAAUJVxB6IAANAQAJAAUJVxB6IAANAQAAAA==.',
Fo='Forfungamer:BAAALgAFFAEJAQAAAA==.',
Fr='Friérén:BAACLgAFFH8PAAINAAMJSxjVLwD2AAANAAMJSxjVLwD2AAAuAAQKfyoAAw0ACAmXHsg4ABkCAA0ACAmXHsg4ABkCABgAAQm4BS0hACkAAAAA.',
Ga='Garhkanis:BAAALgAFFAMJBAAAAA==.Garro:BAACLgAFFH8LAAIZAAQJORcMFwAyAQAZAAQJORcMFwAyAQAuAAQKfx4AAhkACAkFHtAbAG4CABkACAkFHtAbAG4CAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Genjidh:BAABLgAECn8hAAQBAAgJ5iAwGQBhAgABAAgJrR4wGQBhAgACAAQJGyLyJgCJAQAaAAUJFR5RDwBdAQAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgADCgEJAQAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gr='Graud:BAABLgAFFH8GAAIRAAIJdxDWPgCKAAARAAIJdxDWPgCKAAAAAA==.Grimdark:BAABLgAECn8tAAIbAAgJiBoJFAB/AgAbAAgJiBoJFAB/AgAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAFFAIJAgAAAA==.Grumpypants:BAABLgAECn80AAIPAAgJvha5DgC7AQAPAAgJvha5DgC7AQAAAA==.Grunge:BAACLgAFFH8JAAMSAAQJUQhSUAD9AAASAAQJUQhSUAD9AAATAAEJWAAQIwAgAAAuAAQKfygABBIACQmUGl0XAIACABIACQmUGl0XAIACABMABQmhENUjADoBAAQAAQk4GsQtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAINAAgJMCGmIgDoAgANAAgJMCGmIgDoAgAAAA==.',
Ha='Hairyhealer:BAAALgAECgEJAQAAAA==.Haven:BAABLgAECn8iAAIOAAkJAR74CQDjAgAOAAkJAR74CQDjAgAAAA==.',
He='Heathermarie:BAABLgAECn8zAAIcAAkJzBs/AQB8AgAcAAkJzBs/AQB8AgAAAA==.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Hi='Historia:BAAALgAECgEJAQABLgAFFAMJDwANAEsYAA==.',
Ho='Holdmytraps:BAAALgAECgMJAwAAAA==.Holypride:BAAALgADCgEJAQAAAA==.Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgAECgQJBQAAAA==.',
['Há']='Háppyelf:BAAALgAECgUJBQAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAACLgAFFH8GAAIdAAMJExhjIgDgAAAdAAMJExhjIgDgAAAuAAQKfxQAAx0ACAmIFlYZAA4CAB0ACAmIFlYZAA4CAAkAAwkKA7t1AGsAAAAA.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgcJBwAAAA==.Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Io='Ionlyeatpoop:BAAALgAECgQJBAAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8nAAIbAAkJLRCdOACcAQAbAAkJLRCdOACcAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8YAAQSAAcJyxZWEABeAQASAAUJnBhWEABeAQATAAQJzRdoBgAKAQAEAAEJeBvVEABYAAAuAAQKfyQABAQACAn5Ii4FABsCABIACAkWIqsdAKQCAAQABQlrJS4FABsCABMAAgkYG2BEAKQAAAAA.Jamboni:BAAALgAECgYJDQAAAA==.Jarmamathu:BAAALgAECgcJCgAAAA==.Jay:BAAALgAFFAIJAgAAAA==.',
Ji='Jimlaheys:BAABLgAECn8UAAMXAAgJwwV5XgD6AAAXAAgJwwV5XgD6AAAQAAYJpgTvUACZAAAAAA==.',
Jo='Joje:BAABLgAECn8kAAMSAAgJIhjHNwDhAQASAAgJIhjHNwDhAQATAAIJVgmrWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgAECgEJAQAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAABLgAECn8YAAQeAAcJuA52KgBRAQAeAAcJUQ12KgBRAQAfAAMJag75ZACaAAAOAAEJhgP3egAkAAAAAA==.Keora:BAABLgAECn8lAAIRAAkJBhIFHQDNAQARAAkJBhIFHQDNAQAAAA==.',
Kh='Khronos:BAABLgAECn8dAAIRAAkJKg4CKACBAQARAAkJKg4CKACBAQAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAABLgAFFH8FAAIeAAIJlhFFLACYAAAeAAIJlhFFLACYAAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Kronik:BAAALgAECgQJBAAAAA==.Krow:BAAALgADCggJGgAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAABLgAECn8VAAMgAAYJRxe+CAB8AQAKAAYJkxKPKAC1AQAgAAUJLBi+CAB8AQAAAA==.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBwAAAA==.Lightsmith:BAABLgAECn8fAAMHAAkJbiCOGQBGAgAHAAkJbiCOGQBGAgAIAAEJIRkoOwFFAAAAAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAwAAAA==.Lorez:BAACLgAFFH8aAAISAAUJwhIXPAAsAQASAAUJwhIXPAAsAQAuAAQKfxQAAhIACQnCFyRGAPkBABIACQnCFyRGAPkBAAAA.Low:BAABLgAECn8lAAISAAcJlxkWSgCmAQASAAcJlxkWSgCmAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn8pAAIhAAkJPhFCCgDfAQAhAAkJPhFCCgDfAQAAAA==.Mageaurora:BAAALgAECgYJCQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Mazzh:BAABLgAFFH8KAAMFAAUJ4B7tOgD7AAAFAAQJTiDtOgD7AAAiAAMJeBnwGQC2AAABLgAFFAgJBwANAD0mAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Meowyn:BAAALgADCgcJBwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgAECgQJAgAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mikeybad:BAAALgAECgEJAgABLgAECggJHwAjAMMhAA==.Minimage:BAAALgADCgcJBwAAAA==.Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJGAsCXwCEAQABAAkJ6AoCXwCEAQACAAYJEAlKOwATAQAAAA==.',
Mo='Moobie:BAAALgAECgQJBQAAAA==.Mortikhan:BAAALgAECgIJAgAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Na='Narium:BAABLgAECn8UAAIeAAgJ8BOgJgBsAQAeAAgJ8BOgJgBsAQAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAgAAAA==.',
No='Noctilucent:BAAALgAECgUJBwAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgIJAgAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Pa='Pallywix:BAAALgAECgMJAwAAAA==.Paredes:BAAALgAECgUJBwAAAA==.',
Pe='Peewee:BAAALgAECgIJAgAAAA==.Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAACLgAFFH8IAAIMAAQJuhKlRwA4AQAMAAQJuhKlRwA4AQAuAAQKfyAAAgwACAnJH/EnAD8CAAwACAnJH/EnAD8CAAEuAAUUBgkWABIARiEA.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAMJDwANAEsYAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8oAAIhAAkJvBk+BwArAgAhAAkJvBk+BwArAgAAAA==.Prophesy:BAACLgAFFH8GAAIIAAMJpAnvVwDMAAAIAAMJpAnvVwDMAAAuAAQKfyMAAggACAmaHMIoAIICAAgACAmaHMIoAIICAAAA.Proteus:BAACLgAFFH8HAAIMAAQJFAXoYgAGAQAMAAQJFAXoYgAGAQAuAAQKfyoAAwwACAlYFxpKAMEBAAwACAlYFxpKAMEBACQABAkXDLcOALcAAAAA.',
Pu='Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Reflex:BAAALgAECggJDgAAAA==.Retpar:BAAALgAECgYJBwAAAA==.Reventön:BAABLgAECn8nAAIMAAkJtQ4qTAC7AQAMAAkJtQ4qTAC7AQAAAA==.',
Rh='Rhaena:BAAALgAECgIJAgABLgAFFAgJLAAEAA0bAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAABLgAECn8VAAMQAAkJXwZXNgALAQAQAAgJAQdXNgALAQAXAAgJCATIhgDJAAAAAA==.',
['Rá']='Ráîstlin:BAAALgAECgEJAQAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJCwAAAA==.',
Se='Senada:BAABLgAECn8eAAINAAgJcgNMtgD8AAANAAgJcgNMtgD8AAAAAA==.Senkait:BAABLgAECn8vAAQVAAkJ/xvUCgCPAgAVAAkJ/xvUCgCPAgAbAAYJtxvROQCbAQAhAAIJoBcsIwCIAAAAAA==.',
Sh='Shamoura:BAACLgAFFH8gAAIVAAgJfxZcAQASAgAVAAgJfxZcAQASAgAuAAQKfx0AAhUACAmcIzEJAP8CABUACAmcIzEJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shinoa:BAAALgAECgcJAQAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shlongtofoot:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulszaura:BAACLgAFFH8eAAIIAAcJIRufBgD8AQAIAAcJIRufBgD8AQAuAAQKfzEAAggACQkhIgoSAAIDAAgACQkhIgoSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8OAAIBAAYJ+hBxIABnAQABAAYJ+hBxIABnAQAuAAQKfzEAAgEACQnaH/oMAMMCAAEACQnaH/oMAMMCAAAA.Steampunk:BAABLgAECn8UAAINAAcJ0A8NkwA3AQANAAcJ0A8NkwA3AQAAAA==.',
Sw='Swade:BAABLgAECn8YAAIJAAYJ0Ap/QQDXAAAJAAYJ0Ap/QQDXAAABLgAECgcJHAAUAKMLAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAMJDwANAEsYAA==.Synarri:BAACLgAFFH8dAAMHAAUJsiR6BgAMAgAHAAUJsiR6BgAMAgAIAAMJDRP+TgDlAAAuAAQKf0oAAwgACQkkIrgHABYDAAgACQkkIrgHABYDAAcACQkEHN4NAKkCAAEuAAUUCAkdAAcAIBwA.Syneria:BAACLgAFFH8dAAMHAAgJIBwFAQAZAgAHAAgJIBwFAQAZAgAIAAEJ6QE3lAA9AAAuAAQKf0IAAwcACQmaH0kLAMQCAAcACAnpIEkLAMQCAAgACQk0HfAsAHACAAAA.Synn:BAAALgAFFAIJAwABLgAFFAgJHQAHACAcAA==.Synpai:BAACLgAFFH8KAAMHAAQJABjBGgAYAQAHAAQJABjBGgAYAQAIAAIJQA5LbQCWAAAuAAQKfyoAAwgACQlpHwYTALUCAAgACAlWIgYTALUCAAcABwkvGAQsANcBAAEuAAUUCAkdAAcAIBwA.',
Ta='Taccitus:BAACLgAFFH8fAAIBAAYJdRXCHQB1AQABAAYJdRXCHQB1AQAuAAQKfykAAwEACQljIUMdAKICAAEACQljIUMdAKICAAIAAgltGYE8AIoAAAAA.Tailzz:BAAALgAECgYJDgAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAFFAEJAgAAAA==.',
Te='Teach:BAABLgAECn8bAAMRAAcJpRoqIAC0AQARAAYJpRoqIAC0AQAlAAYJ3gs0KwAZAQAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thunderwar:BAABLgAECn8bAAILAAYJDBiuHgAUAQALAAYJDBiuHgAUAQAAAA==.',
Ti='Tiazy:BAAALgAECgEJAQAAAA==.',
To='Toomato:BAAALgAECgQJBwAAAA==.Totemterror:BAEBLgAECn8lAAIbAAkJViZTAADZAwAbAAkJViZTAADZAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tx='Tx:BAAALgAECgYJCgAAAA==.',
Ty='Tydradul:BAACLgAFFH8IAAISAAMJKglXZgDKAAASAAMJKglXZgDKAAAuAAQKfyoAAhIACAnxFjQ7ANUBABIACAnxFjQ7ANUBAAAA.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAABLgAECn82AAIXAAkJNR5qCAAWAwAXAAkJNR5qCAAWAwAAAA==.Valy:BAABLgAECn8WAAMeAAYJRBPyLQA7AQAeAAYJRBPyLQA7AQAfAAEJzAwdYgAuAAAAAA==.',
Ve='Veladria:BAACLgAFFH8MAAIMAAUJORmMSwAyAQAMAAUJORmMSwAyAQAuAAQKfxoAAgwABwmYHGhaAOIBAAwABwmYHGhaAOIBAAAA.Vellion:BAAALgADCgYJCAAAAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Verrindyss:BAAALgAECgEJAgAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAACLgAFFH8FAAIBAAEJKSWkcABpAAABAAEJKSWkcABpAAAuAAQKfxoAAgEABglwJIMlAHECAAEABglwJIMlAHECAAEuAAUUBAkFABsAsQ8A.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAcJGAASAMsWAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBwABLgAECgkJFQAQAF8GAA==.',
Wi='Wikkid:BAABLgAECn83AAIQAAkJzxAWHAC6AQAQAAkJzxAWHAC6AQAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgUJDgAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgEJAQAAAA==.',
Yi='Yiesus:BAABLgAFFH8HAAIOAAQJKAyhFQAdAQAOAAQJKAyhFQAdAQABLgAFFAgJKQABAEYkAA==.',
Ym='Ymir:BAABLgAECn8cAAMTAAgJkhP8DQDnAQATAAgJkhP8DQDnAQASAAQJDgST4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8JAAIXAAMJNQ/6MwDBAAAXAAMJNQ/6MwDBAAAuAAQKfzgAAhcACQlqHRgNANUCABcACQlqHRgNANUCAAAA.',
Yp='Yppah:BAABLgAECn8fAAIVAAkJ1w4IKQB6AQAVAAkJ1w4IKQB6AQAAAA==.',
Yu='Yuhmato:BAABLgAFFH8HAAIMAAIJrBDPpQCTAAAMAAIJrBDPpQCTAAAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQfAAgJIBBsKwCaAQAfAAcJThFsKwCaAQAeAAMJJAi+WwBGAAAOAAEJhwpWYQA1AAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8aAAIBAAYJPR3TFQChAQABAAYJPR3TFQChAQAuAAQKfyMAAgEACAnGIxgNABcDAAEACAnGIxgNABcDAAAA.',
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
