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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Monk-Windwalker','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Priest-Shadow','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Warlock-Demonology','Warlock-Destruction','Hunter-Survival','Shaman-Elemental','Druid-Feral','Druid-Restoration','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Shaman-Restoration','Mage-Fire','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Rogue-Outlaw','Shaman-Enhancement','Hunter-Marksmanship','DeathKnight-Frost','Evoker-Preservation',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaphrodite:BAAALgADCgcJDwAAAA==.',
Ab='Abyssalblink:BAACLgAFFH8kAAIBAAcJeB1XCwAjAgABAAcJeB1XCwAjAgAuAAQKfyUAAwEACQnWHVYgAD8CAAEACQnWHVYgAD8CAAIABwnaGMsjAJ8BAAEuAAUUCQkoAAMAQhwA.',
Ac='Acousticsins:BAAALgAECgYJBgAAAA==.Acting:BAAALgADCgIJAgAAAA==.',
Ad='Adolphyace:BAAALgADCgUJBQAAAA==.',
Ae='Aemond:BAAALgAECgYJEgABLgAFFAgJLAAEAA0bAA==.',
Al='Alastorv:BAAALgADCgMJAwAAAA==.Aleight:BAABLgAECn8jAAIFAAkJQyBRGAB+AgAFAAkJQyBRGAB+AgAAAA==.Aleynna:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.Alius:BAAALgAECgYJCwAAAA==.',
Am='Ambellina:BAACLgAFFH8LAAIHAAMJbhqPIAADAQAHAAMJbhqPIAADAQAuAAQKfzQAAwcACQnmG4cUAG4CAAcACQnmG4cUAG4CAAgABAnmCiToALUAAAAA.Amp:BAAALgAECgEJAQABLgAFFAYJEwAJAOoPAA==.',
Ar='Aravalia:BAAALgADCgIJAgAAAA==.',
As='Aselir:BAAALgADCgEJAgAAAA==.Ashlord:BAAALgAECgQJBAAAAA==.',
Au='Auxiliry:BAAALgAECgUJBQAAAA==.',
Av='Avenger:BAABLgAFFH8GAAIIAAQJRRipLAA8AQAIAAQJRRipLAA8AQABLgAFFAkJNAAKAAQiAA==.',
Ay='Aythrior:BAABLgAECn8WAAILAAcJRB2wDgDnAQALAAcJRB2wDgDnAQAAAA==.',
Ba='Bambiietta:BAACLgAFFH8LAAIMAAQJbwOrdwDvAAAMAAQJbwOrdwDvAAAuAAQKfxkAAgwABwnyCWCaAEsBAAwABwnyCWCaAEsBAAAA.',
Be='Beastsmaster:BAAALgAECgEJAgAAAA==.Beefycrits:BAACLgAFFH8OAAINAAQJjSUKKwCPAQANAAQJjSUKKwCPAQAuAAQKfycAAg0ACQnpI8MXABwDAA0ACQnpI8MXABwDAAAA.',
Bl='Blacktusks:BAAALgADCgEJAQAAAA==.Bloomkin:BAAALgADCgMJAwAAAA==.',
Bo='Boos:BAAALgAECgcJCwAAAA==.',
Br='Brahski:BAAALgADCgQJBAAAAA==.',
Ca='Caelith:BAAALgAECgMJBQAAAA==.Caligos:BAAALgADCgcJCQAAAA==.Calmduke:BAAALgAECgIJAgAAAA==.Camilacream:BAAALgAECgEJAQAAAA==.Capriestson:BAACLgAFFH8GAAIOAAQJLQ5nFwAYAQAOAAQJLQ5nFwAYAQAuAAQKfzAAAg4ACAk3GtcUAAoCAA4ACAk3GtcUAAoCAAAA.Cardrin:BAABLgAECn8iAAMPAAkJ7g9NHABGAQAPAAkJ7g9NHABGAQAQAAYJ4gPoWwCzAAAAAA==.',
Ch='Chel:BAAALgADCgUJBQAAAA==.Chewbatterys:BAAALgADCgcJDAAAAA==.Choplo:BAACLgAFFH8hAAIDAAYJSRtZBAC1AQADAAYJSRtZBAC1AQAuAAQKfyAAAgMACAm+Ih8IAPgCAAMACAm+Ih8IAPgCAAAA.Chounizadi:BAAALgADCgEJAQAAAA==.',
Ci='Cinema:BAABLgAFFH8UAAINAAgJCx7NCQBpAgANAAgJCx7NCQBpAgAAAA==.',
Cl='Clarence:BAAALgAECgUJCAAAAA==.Clearance:BAABLgAFFH8PAAIRAAUJDBMDJAAWAQARAAUJDBMDJAAWAQABLgAFFAgJJQASAAMaAA==.Cleopaatra:BAAALgADCgYJBgAAAA==.',
Cr='Crazyjoker:BAAALgAECgQJBwAAAA==.',
Cy='Cyxodh:BAAALgADCgUJBQABLgAECgEJAwAGAAAAAA==.Cyxopal:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.',
Da='Daboomdeath:BAAALgAFFAMJAQAAAA==.Daemon:BAACLgAFFH8sAAQEAAgJDRu/AADHAQAEAAYJ/xm/AADHAQASAAcJOROKCACgAQATAAUJixIUCADrAAAuAAQKfzcABAQACQnaJAcBAPcCAAQACQlRIgcBAPcCABIACQkzI/ISAOQCABMAAwk5FI4xAPMAAAAA.Darkurge:BAAALgAECgQJBAAAAA==.Darthswaderr:BAABLgAECn8dAAIUAAgJWQo7IgB8AQAUAAgJWQo7IgB8AQAAAA==.Dattsu:BAABLgAECn8aAAMTAAcJxhICLQAKAQASAAcJBBIadgBCAQATAAUJDxACLQAKAQAAAA==.',
De='Dealer:BAAALgADCgkJGAAAAA==.Deez:BAAALgAECgcJEwAAAA==.Demonen:BAAALgAECgYJDgABLgAFFAMJDwANAEsYAA==.Demonius:BAAALgADCgMJAwABLgAECgkJFQAQAF8GAA==.Derangedxo:BAACLgAFFH8+AAQSAAkJpSNEAABIAwASAAkJeyNEAABIAwATAAUJMxTSAQC9AQAEAAQJnibRAgBXAQAuAAQKfyMAAxIACQlOJp4CAJsDABIACQlOJp4CAJsDABMAAwmgI+olAC8BAAAA.',
Di='Dibbons:BAAALgADCgMJAwAAAA==.Dirty:BAAALgADCgYJCQABLgAECggJHgAVAOQTAA==.',
Do='Dominina:BAAALgAECgIJAgAAAA==.',
Dr='Dragonsmonk:BAAALgAECgcJDQAAAA==.Droppi:BAAALgADCgMJAwAAAA==.Droth:BAAALgAECgMJAwAAAA==.Drunkenhoe:BAAALgAECgIJAgAAAA==.',
Du='Duskforger:BAABLgAECn8tAAIQAAkJaw0cIwCXAQAQAAkJaw0cIwCXAQAAAA==.',
En='Enana:BAAALgAECgYJCwAAAA==.Enkor:BAABLgAECn8bAAIDAAgJTBQnHQDxAQADAAgJTBQnHQDxAQAAAA==.',
Ev='Everblack:BAACLgAFFH8IAAMTAAMJBR3nDACzAAATAAIJAyDnDACzAAAEAAEJBxdgGQBTAAAuAAQKfzcAAhMACQmCH4ABALsCABMACQmCH4ABALsCAAAA.Evilcretin:BAACLgAFFH8KAAINAAMJ8RzBJwAUAQANAAMJ8RzBJwAUAQAuAAQKfzAAAg0ABgn0I0tNANwBAA0ABgn0I0tNANwBAAAA.',
Ey='Eyeballin:BAAALgADCgIJAgAAAA==.',
Fa='Faeri:BAAALgAECgMJBgAAAA==.Faeroshus:BAAALgADCgcJBwAAAA==.Falco:BAAALgADCgYJBgAAAA==.Faraah:BAACLgAFFH8LAAIWAAQJJhlTBQA9AQAWAAQJJhlTBQA9AQAuAAQKf0sAAxYACQnoITUCAPYCABYACQnoITUCAPYCABcAAQnSBOvbACcAAAAA.',
Fl='Florleesa:BAAALgADCgYJCAAAAA==.Flowstate:BAABLgAFFH8TAAIJAAYJ6g9zFgBMAQAJAAYJ6g9zFgBMAQAAAA==.',
Fo='Forfungamer:BAAALgAFFAIJAwAAAA==.',
Fr='Friérén:BAACLgAFFH8PAAINAAMJSxjVLwD2AAANAAMJSxjVLwD2AAAuAAQKfyoAAw0ACAmXHt89AAwCAA0ACAmXHt89AAwCABgAAQm4BS0hACkAAAAA.',
Ga='Garhkanis:BAABLgAFFH8FAAISAAMJuyKlQQAwAQASAAMJuyKlQQAwAQAAAA==.Garro:BAACLgAFFH8OAAIZAAQJORfuGQA1AQAZAAQJORfuGQA1AQAuAAQKfyQAAhkACAldHtAbAG4CABkACAldHtAbAG4CAAAA.Garzislao:BAAALgAECgQJBAAAAA==.',
Ge='Generico:BAAALgADCgMJAwABLgAFFAYJIQAVABUlAA==.Genjidh:BAABLgAECn8hAAQBAAgJ5iDhGwBZAgABAAgJrR7hGwBZAgACAAQJGyLyJgCJAQAaAAUJFR5RDwBdAQAAAA==.',
Gl='Gluttony:BAAALgADCgIJAgAAAA==.',
Go='Gochamoo:BAAALgADCgEJAQAAAA==.Gorggononson:BAAALgAECgQJBAAAAA==.',
Gr='Graud:BAABLgAFFH8GAAIRAAIJdxCTRgCCAAARAAIJdxCTRgCCAAAAAA==.Grimdark:BAABLgAECn8wAAIbAAgJiBq9FgB7AgAbAAgJiBq9FgB7AgAAAA==.Groda:BAAALgADCgcJCgAAAA==.Gromit:BAAALgAFFAIJAgAAAA==.Grumpypants:BAABLgAECn85AAIPAAkJ4BfvCgAVAgAPAAkJ4BfvCgAVAgAAAA==.Grunge:BAACLgAFFH8JAAMSAAQJUQh0WQD8AAASAAQJUQh0WQD8AAATAAEJWAAOJwAgAAAuAAQKfygABBIACQmUGmwaAHgCABIACQmUGmwaAHgCABMABQmhENUjADoBAAQAAQk4GsQtAEMAAAAA.',
Gu='Gumbomage:BAABLgAECn8hAAINAAgJMCGmIgDoAgANAAgJMCGmIgDoAgAAAA==.',
Ha='Hairyhealer:BAAALgAECgQJBAAAAA==.Haven:BAABLgAECn8iAAIOAAkJAR74CQDjAgAOAAkJAR74CQDjAgAAAA==.',
He='Heathermarie:BAABLgAECn85AAIcAAkJbB74AAC7AgAcAAkJbB74AAC7AgAAAA==.',
Hf='Hf:BAAALgAECgkJBgAAAA==.',
Hi='Historia:BAAALgAFFAMJAwABLgAFFAMJDwANAEsYAA==.',
Ho='Holdmytraps:BAAALgAECgUJBwAAAA==.Holypride:BAAALgADCgEJAQAAAA==.Horned:BAAALgADCgIJAgAAAA==.Hotcoffee:BAAALgADCgIJAgAAAA==.',
Hz='Hzwx:BAAALgAECgQJBQAAAA==.',
['Há']='Háppyelf:BAAALgAECgUJBQAAAA==.',
Ia='Iamchewy:BAAALgADCgMJAwAAAA==.Iamjacksfist:BAAALgAECgIJBAAAAA==.Iaptopz:BAACLgAFFH8IAAIdAAQJhhkoGwBFAQAdAAQJhhkoGwBFAQAuAAQKfxQAAx0ACAmIFmIcAA4CAB0ACAmIFmIcAA4CAAkAAwkKA7t1AGsAAAAA.',
Ic='Iceblock:BAAALgAECgQJBAAAAA==.',
In='Indra:BAAALgAECgcJCQAAAA==.Inmelancholy:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgYJBgAAAA==.',
Ir='Irishbaby:BAAALgAECgMJAgAAAA==.',
Iy='Iyali:BAAALgADCgEJAQAAAA==.',
Iz='Iza:BAABLgAECn8rAAIbAAkJlRCTPACfAQAbAAkJlRCTPACfAQAAAA==.',
Ja='Jador:BAAALgAECgEJAgAAAA==.Jake:BAECLgAFFH8YAAQSAAcJyxZWEABeAQASAAUJnBhWEABeAQATAAQJzRdoBgAKAQAEAAEJeBuBGQBTAAAuAAQKfyQABAQACAn5Ii4FABsCABIACAkWIqsdAKQCAAQABQlrJS4FABsCABMAAgkYG2BEAKQAAAAA.Jamboni:BAAALgAFFAMJAwAAAA==.Jarmamathu:BAAALgAECgcJCgAAAA==.Jay:BAAALgAFFAIJAgAAAA==.',
Ji='Jimlaheys:BAABLgAECn8UAAMXAAgJxAU4YwD5AAAXAAgJxAU4YwD5AAAQAAYJpgTZVgCZAAAAAA==.',
Jo='Joje:BAABLgAECn8kAAMSAAgJIhiqPADcAQASAAgJIhiqPADcAQATAAIJVgmrWgBfAAAAAA==.Joolz:BAAALgADCgMJAwAAAA==.',
Ju='Juddson:BAAALgAECgEJAgAAAA==.Jumper:BAAALgAECgEJAQAAAA==.Juniperdayne:BAAALgAFFAEJAQAAAA==.Juri:BAAALgAECgEJAQAAAA==.',
Ka='Kaleheo:BAAALgADCgIJAgAAAA==.Kanbu:BAAALgADCgYJBgAAAA==.Kardd:BAAALgAECgEJAwAAAA==.Karnstein:BAAALgADCgIJAQAAAA==.',
Ke='Keltic:BAABLgAECn8YAAQeAAcJuA5SLgBDAQAeAAcJUQ1SLgBDAQAfAAMJag75ZACaAAAOAAEJhgOhhAAjAAAAAA==.Keora:BAABLgAECn8mAAIRAAkJxRJlHwDDAQARAAkJxRJlHwDDAQAAAA==.',
Kh='Khronos:BAABLgAECn8mAAIRAAkJnBZkEwAqAgARAAkJnBZkEwAqAgAAAA==.',
Ki='Kiing:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgYJBwAAAA==.Kittier:BAABLgAFFH8FAAIeAAIJlhFKMwCDAAAeAAIJlhFKMwCDAAAAAA==.Kittyforeman:BAAALgADCgYJCQAAAA==.',
Kr='Krethrik:BAAALgADCggJDgABLgAECgUJCwAGAAAAAA==.Kronik:BAAALgAECgQJBQAAAA==.Krow:BAAALgADCggJGgAAAA==.',
La='Labobo:BAAALgADCggJCQAAAA==.Large:BAACLgAFFH8FAAMgAAIJxh4/CQC1AAAgAAIJxh4/CQC1AAAKAAIJBQQ9LwCAAAAuAAQKfxUAAyAABglHF6gJAHgBAAoABgmTEo8oALUBACAABQksGKgJAHgBAAAA.',
Li='Lightbright:BAAALgADCgMJAQAAAA==.Lightingmcqu:BAAALgAECgYJBAAAAA==.Lightmane:BAAALgAECgUJBwAAAA==.Lightsmith:BAABLgAECn8fAAMHAAkJbiCOGQBGAgAHAAkJbiCOGQBGAgAIAAEJIRlSVAFCAAAAAA==.Liyun:BAAALgAECgEJAQABLgAECgkJJgARAMUSAA==.',
Lo='Loaf:BAAALgAECgcJEQAAAA==.Lobotomy:BAAALgAFFAEJAwAAAA==.Lorez:BAACLgAFFH8cAAISAAYJwg9wKQBzAQASAAYJwg9wKQBzAQAuAAQKfxQAAhIACQnCFyRGAPkBABIACQnCFyRGAPkBAAAA.Low:BAABLgAECn8lAAISAAcJlxmJTwChAQASAAcJlxmJTwChAQAAAA==.',
Lu='Lukian:BAAALgADCgUJBQAAAA==.Lustonpull:BAAALgAECgYJDAAAAA==.',
Ma='Mace:BAABLgAECn8pAAIhAAkJPhGSCwDdAQAhAAkJPhGSCwDdAQAAAA==.Mageaurora:BAAALgAECgYJCQAAAA==.Marax:BAAALgAFFAEJAQAAAA==.Maugrim:BAAALgAECggJCgAAAA==.Maysia:BAAALgADCgUJBQAAAA==.Mazzh:BAABLgAFFH8WAAMFAAYJOSLLEgCRAQAFAAUJZCLLEgCRAQAiAAUJJRujFADvAAABLgAFFAkJDQANAEwmAA==.',
Me='Melmus:BAAALgADCgMJAwAAAA==.Mem:BAAALgAECgUJCgAAAA==.Meowyn:BAAALgADCgcJBwAAAA==.Meowzer:BAAALgADCgUJBQAAAA==.Meowzur:BAAALgAECgEJAQAAAA==.Meÿa:BAAALgAECgQJAgAAAA==.',
Mg='Mgjun:BAAALgADCgEJAQAAAA==.',
Mi='Mikeybad:BAAALgAECgEJAgABLgAECggJIAAMAMMhAA==.Minimage:BAAALgAECgEJAQAAAA==.Mistabones:BAAALgAECgMJAwAAAA==.Miyara:BAABLgAECn8aAAMBAAkJGAsCXwCEAQABAAkJ6AoCXwCEAQACAAYJEAlKOwATAQAAAA==.',
Mo='Moobie:BAAALgAECgYJEQAAAA==.Mortikhan:BAAALgAECgMJBAAAAA==.',
Ms='Msindica:BAAALgADCgcJCQAAAA==.',
Na='Narium:BAABLgAECn8WAAIeAAgJyBWIIgCWAQAeAAgJyBWIIgCWAQAAAA==.Narth:BAAALgAECgYJDwAAAA==.Nazrogg:BAAALgADCggJCAAAAA==.',
Ni='Nitekiller:BAAALgADCgkJCQAAAA==.Nitro:BAAALgAECgEJAgAAAA==.',
No='Noctilucent:BAAALgAECgUJBwAAAA==.Nol:BAAALgADCgcJBwAAAA==.',
Nu='Nuculais:BAAALgAECgEJAQAAAA==.',
Op='Opfee:BAAALgAECgYJCAAAAA==.',
Or='Orknight:BAAALgAECgIJAgAAAA==.',
Ou='Ouch:BAAALgAECgQJBAAAAA==.',
Pa='Pallywix:BAAALgAECgMJAwAAAA==.Paredes:BAAALgAECgUJBwAAAA==.',
Pe='Peewee:BAAALgAECgIJAgAAAA==.Peonu:BAAALgADCgcJCAAAAA==.',
Pl='Playingjacky:BAACLgAFFH8NAAIMAAQJbRZPSwA8AQAMAAQJbRZPSwA8AQAuAAQKfyAAAgwACAnJHzYsADsCAAwACAnJHzYsADsCAAEuAAUUBwkYABIArh0A.',
Po='Pompkin:BAAALgADCgQJBAABLgAFFAMJDwANAEsYAA==.Potatto:BAAALgAECgEJAQAAAA==.',
Pr='Pride:BAABLgAECn8pAAIhAAkJvBlXCAAmAgAhAAkJvBlXCAAmAgAAAA==.Prophesy:BAACLgAFFH8GAAIIAAMJpAlTZgC+AAAIAAMJpAlTZgC+AAAuAAQKfyMAAggACAmaHMIoAIICAAgACAmaHMIoAIICAAAA.Proteus:BAACLgAFFH8LAAIMAAQJpwhKawAIAQAMAAQJpwhKawAIAQAuAAQKfyoAAwwACAlYF/ZQAL0BAAwACAlYF/ZQAL0BACMABAkXDLcOALcAAAAA.',
Pu='Puff:BAAALgAECgEJAQAAAA==.Puffslock:BAAALgAECgMJAwAAAA==.Punted:BAAALgADCgcJDAAAAA==.Purplenurple:BAAALgAECgcJCwAAAA==.',
Ra='Rama:BAAALgAECgUJCgAAAA==.',
Re='Reflex:BAAALgAECggJEQAAAA==.Retpar:BAAALgAECgYJBwAAAA==.Reventön:BAABLgAECn8rAAIMAAkJ+g6VUAC+AQAMAAkJ+g6VUAC+AQAAAA==.',
Rh='Rhaena:BAAALgAECgIJAgABLgAFFAgJLAAEAA0bAA==.',
Ri='Richgoonie:BAAALgADCgMJAwAAAA==.',
Ro='Ronniechan:BAAALgAECggJCAAAAA==.Roontala:BAAALgADCgQJBAAAAA==.',
Ru='Rune:BAAALgADCgIJAgAAAA==.Runninscared:BAABLgAECn8VAAMQAAkJXwbUOgAKAQAQAAgJAQfUOgAKAQAXAAgJCATIhgDJAAAAAA==.',
['Rá']='Ráîstlin:BAAALgAECgEJAQAAAA==.',
['Rü']='Rüntzz:BAAALgAECgYJDQAAAA==.',
Se='Senada:BAABLgAECn8eAAINAAgJcgMzwwDmAAANAAgJcgMzwwDmAAAAAA==.Senkait:BAABLgAECn8vAAQVAAkJ/xtUDACLAgAVAAkJ/xtUDACLAgAbAAYJtxvROQCbAQAhAAIJoBd/JwCHAAAAAA==.',
Sh='Shamoura:BAACLgAFFH8lAAIVAAgJwhZcAQASAgAVAAgJwhZcAQASAgAuAAQKfx0AAhUACAmcIzEJAP8CABUACAmcIzEJAP8CAAAA.Shamourax:BAAALgAECgYJDwAAAA==.Shinoa:BAAALgAECgcJAQAAAA==.Shippo:BAAALgADCgEJAQAAAA==.Shlongtofoot:BAAALgADCgEJAQAAAA==.Shon:BAAALgADCgEJAQABLgAECgEJAwAGAAAAAA==.Shoosh:BAAALgADCgEJAQAAAA==.Shínobu:BAAALgADCgUJBgAAAA==.',
Si='Siouxsie:BAAALgADCgEJAwAAAA==.',
Sk='Skimpossible:BAAALgADCgQJBAAAAA==.',
Sm='Smeech:BAAALgAECgYJBgAAAA==.',
So='Soulreaver:BAAALgADCgkJCQAAAA==.Soulszaura:BAACLgAFFH8fAAIIAAgJDhvsBABIAgAIAAgJDhvsBABIAgAuAAQKfzEAAggACQkhIgoSAAIDAAgACQkhIgoSAAIDAAAA.',
Sp='Sport:BAAALgADCgEJAQAAAA==.',
St='Starchucker:BAACLgAFFH8TAAIBAAYJJhiyHACUAQABAAYJJhiyHACUAQAuAAQKfzEAAgEACQnaH7IOALsCAAEACQnaH7IOALsCAAAA.Steampunk:BAACLgAFFH8FAAINAAMJjgMeggCwAAANAAMJjgMeggCwAAAuAAQKfxQAAg0ABwnQD7OhAB0BAA0ABwnQD7OhAB0BAAAA.',
Sw='Swade:BAABLgAECn8YAAIJAAYJ0ApkRQDVAAAJAAYJ0ApkRQDVAAABLgAECggJHQAUAFkKAA==.',
Sy='Sylvaine:BAAALgADCggJEAAAAA==.Sylvenna:BAAALgADCgMJAwABLgAFFAMJDwANAEsYAA==.Synarri:BAACLgAFFH8iAAMHAAUJHCXNBgAgAgAHAAUJHCXNBgAgAgAIAAMJNBh6TAD3AAAuAAQKf0oAAwgACQkkItcJAAUDAAgACQkkItcJAAUDAAcACQkEHN4NAKkCAAEuAAUUCAkiAAcA7h4A.Syneria:BAACLgAFFH8iAAMHAAgJ7h4FAQAZAgAHAAgJ7h4FAQAZAgAIAAIJghOCcgCaAAAuAAQKf0MAAwcACQmaH0kLAMQCAAcACAnpIEkLAMQCAAgACQmTH7IxACECAAAA.Synn:BAAALgAFFAIJAwABLgAFFAgJIgAHAO4eAA==.Synpai:BAACLgAFFH8NAAMHAAQJABi8HgAQAQAHAAQJABi8HgAQAQAIAAIJQA7XeQCPAAAuAAQKfyoAAwgACQlpH0cWAKcCAAgACAlWIkcWAKcCAAcABwkvGAQsANcBAAEuAAUUCAkiAAcA7h4A.',
Ta='Taccitus:BAACLgAFFH8mAAIBAAcJ9RXdFQDCAQABAAcJ9RXdFQDCAQAuAAQKfy4AAwEACQljIZINAMUCAAEACQljIZINAMUCAAIAAwk3F8Y1AMIAAAAA.Tailzz:BAAALgAECgcJDwAAAA==.Taneronsol:BAAALgADCgYJBgAAAA==.Tankthis:BAAALgAFFAEJAwAAAA==.',
Te='Teach:BAABLgAECn8fAAMRAAgJnBpXIAC7AQARAAYJrRtXIAC7AQAkAAcJ1AxUIwC/AAAAAA==.',
Th='Thermafrost:BAAALgADCgMJAwAAAA==.Thunderwar:BAABLgAECn8bAAILAAYJDBhsIQAMAQALAAYJDBhsIQAMAQAAAA==.',
Ti='Tiazy:BAAALgAECgMJAwAAAA==.',
To='Toomato:BAAALgAECgQJBwAAAA==.Totemterror:BAEBLgAECn8lAAIbAAkJViZzAADXAwAbAAkJViZzAADXAwAAAA==.Tough:BAAALgADCgYJBgAAAA==.',
Tx='Tx:BAAALgAECgYJCwAAAA==.',
Ty='Tydradul:BAACLgAFFH8IAAISAAMJKgnzcADJAAASAAMJKgnzcADJAAAuAAQKfyoAAhIACAnxFs0/ANEBABIACAnxFs0/ANEBAAAA.Tyrisa:BAAALgAECgQJBQAAAA==.',
Ul='Ulfar:BAAALgADCgcJCwAAAA==.',
Va='Vala:BAABLgAECn82AAIXAAkJNR5qCQATAwAXAAkJNR5qCQATAwAAAA==.Valy:BAABLgAECn8cAAMeAAYJHBn9IwCLAQAeAAYJHBn9IwCLAQAfAAEJzAyRaQArAAAAAA==.',
Ve='Veladria:BAACLgAFFH8NAAIMAAYJ2RR9MgBxAQAMAAYJ2RR9MgBxAQAuAAQKfxwAAgwACQmAHN89APcBAAwACQmAHN89APcBAAAA.Vellion:BAAALgAECgEJAgAAAA==.Verio:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Verrindyss:BAAALgAECgEJAgAAAA==.',
Vi='Violetfairie:BAAALgAECgYJCgAAAA==.',
Vo='Voidchaos:BAAALgAECgIJAgAAAA==.Vora:BAAALgAECgEJAgAAAA==.',
Wa='Wanta:BAAALgAECgYJBwAAAA==.Warglaive:BAACLgAFFH8KAAIBAAUJYxrGKABXAQABAAUJYxrGKABXAQAuAAQKfxoAAgEABglwJIMlAHECAAEABglwJIMlAHECAAAA.',
We='Wetrat:BAEALgAECgEJAQABLgAFFAcJGAASAMsWAA==.',
Wh='Wheresdebeef:BAAALgAECgQJBwABLgAECgkJFQAQAF8GAA==.',
Wi='Wikkid:BAABLgAECn83AAIQAAkJzxC9HgC4AQAQAAkJzxC9HgC4AQAAAA==.Windowpain:BAAALgAECgQJBAAAAA==.Withermint:BAAALgAECgIJBQAAAA==.',
Wr='Wraithstalkr:BAAALgADCgMJAwAAAA==.',
['Wî']='Wîtchîtå:BAAALgADCgYJCQAAAA==.',
['Wù']='Wùlph:BAAALgAECgUJDgAAAA==.',
Xi='Xilliam:BAAALgADCgYJBgAAAA==.Xingxing:BAAALgAECgEJAQAAAA==.',
Xx='Xxz:BAAALgADCgIJAgAAAA==.',
Yi='Yiesus:BAABLgAFFH8IAAIOAAUJBwqoEABIAQAOAAUJBwqoEABIAQABLgAFFAgJLwABAGgkAA==.',
Ym='Ymir:BAABLgAECn8cAAMTAAgJkhP8DQDnAQATAAgJkhP8DQDnAQASAAQJDgST4wCTAAAAAA==.',
Yo='Yomato:BAACLgAFFH8JAAIXAAMJNQ+wOAC7AAAXAAMJNQ+wOAC7AAAuAAQKfzkAAhcACQmOHXEOANMCABcACQmOHXEOANMCAAAA.',
Yp='Yppah:BAABLgAECn8fAAIVAAkJ1w6+LAB4AQAVAAkJ1w6+LAB4AQAAAA==.',
Yu='Yuhmato:BAABLgAFFH8JAAIMAAIJ/BrEogCmAAAMAAIJ/BrEogCmAAAAAA==.Yunara:BAAALgAECgQJBgAAAA==.Yunjin:BAAALgAECgYJCwAAAA==.',
Za='Zaladin:BAAALgAECgUJBQAAAA==.',
Zo='Zod:BAABLgAECn8UAAQfAAgJIBBsKwCaAQAfAAcJThFsKwCaAQAeAAMJJAifaAA2AAAOAAEJhwpWYQA1AAAAAA==.Zoolater:BAAALgADCgIJAgAAAA==.Zoomiez:BAAALgADCgMJAwAAAA==.',
Zu='Zuzana:BAACLgAFFH8dAAIBAAgJPRnrCQAzAgABAAgJPRnrCQAzAgAuAAQKfyMAAgEACAnGIxgNABcDAAEACAnGIxgNABcDAAAA.',
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
