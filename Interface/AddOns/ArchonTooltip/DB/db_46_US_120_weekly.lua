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

local lookup = {'Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','Unknown-Unknown','Monk-Windwalker','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Mage-Frost','Priest-Shadow','Priest-Discipline','Priest-Holy','Shaman-Elemental','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abberleigh:BAAALgAECgYJCAAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAABLgAFFH8HAAIBAAQJlxDbPwAdAQABAAQJlxDbPwAdAQAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8XAAMCAAYJtiFSDQDhAQACAAYJtiFSDQDhAQABAAIJ4xU+JAF8AAABLgAECgkJQQADAKofAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgtVLQDlAAAEAAgJvgtVLQDlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgAECgQJCgABLgAECggJKQAFACoFAA==.Alliesofevil:BAABLgAECn8kAAIGAAgJlxQLJADOAQAGAAgJlxQLJADOAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB2sBQCfAgAEAAkJnB2sBQCfAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCgAAAA==.',
Am='Amathushhg:BAACLgAFFH8JAAMHAAUJkQR1DgCzAAAHAAQJywR1DgCzAAAIAAMJUgQRgwCtAAAuAAQKf18ABAcACQkOGLgFAAACAAcACAk3GrgFAAACAAgACQn5E0NDAMwBAAkAAwl0DeIiAJQAAAAA.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAAALgAECggJEgAAAA==.Andreth:BAAALgAECgYJDgAAAA==.Anoxyn:BAAALgAECgcJBwAAAA==.Anthe:BAAALgAECgIJAwAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCB9IQB3AgABAAkJQh99IQB3AgACAAUJxB2dGABKAQAAAA==.',
Ar='Araestirra:BAABLgAECn8mAAMHAAcJcg22FQDsAAAHAAYJTQ62FQDsAAAIAAcJcAYLqQDqAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAUJGAAIAHEEAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMKAAgJ6hSYCwCjAQAKAAgJ6hSYCwCjAQALAAEJagOrKQEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAIMAAgJGB/5FABhAgAMAAgJGB/5FABhAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAINAAkJOgrkSQB6AQANAAkJOgrkSQB6AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8WAAIOAAQJmB3QEgBDAQAOAAQJmB3QEgBDAQAuAAQKfzIAAg4ACQkzHf8MAC8CAA4ACQkzHf8MAC8CAAAA.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8bAAILAAcJax5zLgACAgALAAcJax5zLgACAgAAAA==.',
Be='Beastnite:BAAALgADCggJHQABLgAECgYJDgAPAAAAAA==.Bellaburger:BAABLgAFFH8IAAIQAAQJsgbHHQDcAAAQAAQJsgbHHQDcAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgQJBQABLgAECgkJRAAJAJAgAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn8rAAMGAAgJhwnsRQAkAQAGAAgJLQfsRQAkAQARAAMJgwylOQB/AAAAAA==.Biped:BAABLgAECn8zAAIJAAkJPhOVBwDmAQAJAAkJPhOVBwDmAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAISAAIJSglX2wCBAAASAAIJSglX2wCBAAAuAAQKfyYAAhIACAlwGKhjAJgBABIACAlwGKhjAJgBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Boomstique:BAABLgAECn8oAAITAAgJVBYVPQDhAQATAAgJVBYVPQDhAQAAAA==.Boondocka:BAABLgAECn8qAAITAAgJ8htIJQBBAgATAAgJ8htIJQBBAgAAAA==.',
Br='Brewco:BAACLgAFFH8PAAIUAAQJoRZ1KQANAQAUAAQJoRZ1KQANAQAuAAQKfzgABBQACQkEHKYUAJACABQACQkEHKYUAJACABUABgnDG+MQAJgBAAQABQl6D9o3ALIAAAAA.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8mAAITAAkJFhJLOQDuAQATAAkJFhJLOQDuAQAAAA==.',
Bt='Btrain:BAABLgAECn8hAAMCAAYJ3AohLwCfAAABAAYJzQaM5wDHAAACAAUJgAwhLwCfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQDAAcJwx9sHQCsAQADAAcJrh1sHQCsAQATAAQJNx5HXgBNAQAWAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9EAAMJAAkJkCA9AQDuAgAJAAkJpB89AQDuAgAIAAkJWBhMOADzAQAAAA==.',
Ce='Cedric:BAAALgADCgMJAwAAAA==.Cenobité:BAABLgAECn8mAAIXAAkJ0RNXCQDeAQAXAAkJ0RNXCQDeAQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJGwALAGseAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIYAAMJlBUmDQAVAQAYAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMZAAgJCRJmPQApAQAZAAgJCRJmPQApAQAaAAIJfAz4MABcAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.',
Ci='Cirax:BAABLgAECn8lAAITAAgJBhXIPwDXAQATAAgJBhXIPwDXAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn9VAAMCAAkJTQyaFwBVAQACAAkJ6wqaFwBVAQABAAgJCQh9pQAjAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8QAAILAAQJ9RkyOAAvAQALAAQJ9RkyOAAvAQAuAAQKfzAAAgsACQm0IaELAOICAAsACQm0IaELAOICAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn8nAAITAAgJLRF6WACOAQATAAgJLRF6WACOAQAAAA==.',
Cy='Cyris:BAAALgAECgMJAwABLgAECggJLQAbAGgFAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJGwALAGseAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgEJAQAAAA==.Dak:BAABLgAECn8lAAISAAkJWxfxLABDAgASAAkJWxfxLABDAgAAAA==.Daksclaw:BAAALgAECgYJBgABLgAECgkJJQASAFsXAA==.Daksmash:BAAALgAECgUJBQAAAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAAALgAECggJDgAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECggJKAACAFAbAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8YAAIIAAUJcQSdZQDoAAAIAAUJcQSdZQDoAAAuAAQKfzsAAwgACAl1EdtfAHwBAAgACAl1EdtfAHwBAAcAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJAwAAAA==.Darthbluto:BAAALgAECgUJCgABLgAECgYJDwAPAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8eAAIBAAgJ4xQYbwCFAQABAAgJ4xQYbwCFAQAAAA==.',
De='Deadazz:BAAALgADCgYJBwAAAA==.Deadmangalad:BAABLgAECn8jAAMXAAgJQwcAFgAaAQAXAAgJQwcAFgAaAQAOAAEJFAQiZQAWAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8dAAIcAAcJ7wYcSADdAAAcAAcJ7wYcSADdAAAAAA==.Demonbo:BAABLgAECn8ZAAILAAgJiBQsYABdAQALAAgJiBQsYABdAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8VAAMGAAQJUx5aDwB4AQAGAAQJUx5aDwB4AQAdAAMJMBRVIwDMAAAuAAQKfzsAAwYACQkmJGkDAC4DAAYACQkmJGkDAC4DAB0AAgmSDWtdAFkAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMTAAgJYhlFJwAcAgATAAgJYhlFJwAcAgADAAUJYQt1OwDaAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Dies:BAAALgAECgkJBAAAAA==.Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgQJBwAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIeAAMJ7gOgiAC5AAAeAAMJ7gOgiAC5AAAuAAQKfxUAAh4ACAnCDX93AIMBAB4ACAnCDX93AIMBAAAA.',
Do='Dogminos:BAAALgADCgIJAgAAAA==.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECgYJDAAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJFQAGAFMeAA==.Drphilyobody:BAABLgAECn8cAAISAAcJCQifpwAXAQASAAcJCQifpwAXAQAAAA==.Drui:BAABLgAECn8dAAIcAAgJsQ4dNgBkAQAcAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAABLgAECn8jAAIfAAcJVQtROgAhAQAfAAcJVQtROgAhAQAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8eAAMDAAkJdQdcHQCtAQADAAkJdQdcHQCtAQAWAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn8yAAIeAAgJExRMYAC5AQAeAAgJExRMYAC5AQAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgIJAgABLgAECgYJCgAPAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgADCgkJFAAAAA==.Elaric:BAAALgAECgEJAQAAAA==.',
En='Engi:BAAALgAECgQJBAAAAA==.',
Ep='Epikrate:BAABLgAECn8eAAMIAAgJURlHPQDhAQAIAAcJIRlHPQDhAQAHAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn80AAIXAAgJhRPmDQCGAQAXAAgJhRPmDQCGAQAAAA==.',
Ex='Extrema:BAAALgAECgYJDAAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAeAGsfAA==.Fallenembers:BAACLgAFFH8WAAIeAAQJax9uOwBuAQAeAAQJax9uOwBuAQAuAAQKfzsAAh4ACQlJJdQFAFEDAB4ACQlJJdQFAFEDAAAA.Famine:BAABLgAECn8dAAMSAAgJ0AWbsAAKAQASAAgJwwSbsAAKAQAXAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAgAPAAAAAA==.',
Fh='Fhait:BAAALgAECgQJBAABLgAECggJLgAQAGELAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIYAAIJJg3RMACOAAAYAAIJJg3RMACOAAAuAAQKfx4AAhgACQnaEy4TAP4BABgACQnaEy4TAP4BAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgAECgQJCQABLgAECggJIwAXAEMHAA==.Gaskelmarg:BAAALgAECgQJBgAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQgAAkJIRWDHQDTAQAgAAkJsRGDHQDTAQAhAAcJpAuKTgD+AAAfAAEJcAGHkQAZAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJBwAMAPELAA==.',
Gi='Gigaweed:BAABLgAFFH8HAAIMAAMJ8QtYOwCVAAAMAAMJ8QtYOwCVAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8fAAIVAAgJWxYWDQDUAQAVAAgJWxYWDQDUAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIIAAkJlRcOJQBFAgAIAAkJlRcOJQBFAgAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgMJAwABLgAECggJKAACAFAbAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQALADYgAA==.Hettokal:BAAALgAECgQJBAAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8cAAILAAkJchHYQQC2AQALAAkJchHYQQC2AQAAAA==.Hondojoe:BAACLgAFFH8VAAIhAAQJSB6HEAA2AQAhAAQJSB6HEAA2AQAuAAQKfzYAAyEACQnuIEoLAJsCACEACQnuIEoLAJsCACAAAgnYBoRnAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn8pAAIFAAgJKgUpRQAgAQAFAAgJKgUpRQAgAQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn8oAAIKAAgJBAonFAABAQAKAAgJBAonFAABAQABLgAECggJLgAQAGELAA==.Huhu:BAABLgAECn8ZAAIGAAkJrxQUKACzAQAGAAkJrxQUKACzAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJBwATALkMAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8qAAIdAAkJ9gqnHABrAQAdAAkJ9gqnHABrAQAAAA==.',
Ic='Icyhot:BAAALgADCgUJCAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgAECgUJDAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAILAAkJyRd/LAAKAgALAAkJyRd/LAAKAgAAAA==.Ivylyn:BAAALgADCgkJDwAAAA==.',
Ix='Ixiyá:BAABLgAECn88AAMNAAkJNCPbAwBzAwANAAkJNCPbAwBzAwAiAAEJzginoQAqAAAAAA==.Ixií:BAAALgAECgEJAQAAAA==.Ixì:BAABLgAECn8WAAIUAAcJ1x23IAA4AgAUAAcJ1x23IAA4AgAAAA==.',
Ja='Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBAAPAAAAAA==.Jakota:BAAALgADCggJDAAAAA==.Jakskeleton:BAABLgAECn8cAAIOAAgJTBnjEADxAQAOAAgJTBnjEADxAQAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgcJCgAAAA==.',
Jo='Joemacho:BAAALgAECgcJDQABLgAFFAQJFQAhAEgeAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.',
Ju='Judax:BAABLgAECn89AAIiAAkJtBu1EQBXAgAiAAkJtBu1EQBXAgAAAA==.Justagirl:BAABLgAECn8uAAIQAAgJYQtDMQA0AQAQAAgJYQtDMQA0AQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgAECgMJAwAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAABLgAECn8eAAITAAgJfRXUVQCVAQATAAgJfRXUVQCVAQAAAA==.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIYAAgJISMwCAANAwAYAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8UAAMOAAgJQhrlGQCFAQAOAAgJQhrlGQCFAQASAAIJtQTaPgFQAAAAAA==.Karen:BAAALgADCgcJGAAAAA==.Karne:BAAALgADCgYJBgAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8cAAIOAAYJzxpwJAAkAQAOAAYJzxpwJAAkAQAAAA==.Keelay:BAABLgAECn85AAIFAAkJ7R2XCgDYAgAFAAkJ7R2XCgDYAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQABLgAECgkJJQASAFsXAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwAPAAAAAA==.Kimiko:BAAALgAECgcJCwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAYACEjAA==.',
Ko='Koffcmorbius:BAAALgAECgMJAwAAAA==.Koriban:BAABLgAECn8lAAIeAAkJaA40YgC0AQAeAAkJaA40YgC0AQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAeAGgOAA==.',
Kr='Kraken:BAACLgAFFH8FAAIHAAMJ0Q2DCwDQAAAHAAMJ0Q2DCwDQAAAuAAQKfyoAAgcACQlzItAAAAQDAAcACQlzItAAAAQDAAEuAAUUAwkHAAwA8QsA.',
Ku='Kubb:BAABLgAECn8tAAIbAAgJaAWTGwAQAQAbAAgJaAWTGwAQAQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8SAAIVAAUJ7iK+AgCWAQAVAAUJ7iK+AgCWAQAuAAQKfy0AAxUACQk6IxoFAMACABUACQk6IxoFAMACABwABQkbDjRDAPEAAAAA.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8iAAMJAAgJuwWAFAAYAQAJAAgJuwWAFAAYAQAHAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8OAAILAAUJ0RbINQA3AQALAAUJ0RbINQA3AQAAAA==.Laurlynn:BAAALgAECgQJBwAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJCgABLgAECgYJJwAhAOoOAA==.Lettuceprey:BAABLgAECn8pAAIhAAgJNBDPKABzAQAhAAgJNBDPKABzAQAAAA==.',
Li='Lierise:BAAALgAECgUJCAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJBwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgEJAQABLgAECggJHQASAK0fAA==.',
Lo='Lockatute:BAAALgAECggJCgAAAA==.Lockdeath:BAAALgAECgQJCAAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAAALgAECggJDgAAAA==.',
Lu='Lucille:BAAALgAFFAEJBAAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8fAAMVAAgJNBr3CQATAgAVAAgJNBr3CQATAgAUAAEJGwYE4QAjAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgYJCAAAAA==.Magicdance:BAACLgAFFH8GAAIiAAMJEQPqOQCQAAAiAAMJEQPqOQCQAAAuAAQKfzEAAw0ACQkoER1HAIQBAA0ACAl7ER1HAIQBACIACQmICV89AC8BAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIVAAgJchK/CwACAgAVAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8eAAIiAAgJtBalHgDgAQAiAAgJtBalHgDgAQAAAA==.Maki:BAAALgAECggJEwAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJGwALAGseAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAQAAAA==.',
Mc='Mctowlie:BAAALgAECgYJBwAAAA==.',
Me='Mehänemäntä:BAAALgAECgYJDAAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMXAAcJqBUqEgBDAQASAAYJJRKQlABXAQAXAAUJWBUqEgBDAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAMJBgAiABEDAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAACLgAFFH8QAAIQAAQJUyQNBwCWAQAQAAQJUyQNBwCWAQAuAAQKfzwAAhAACQkYJmQBAGEDABAACQkYJmQBAGEDAAAA.Misstreater:BAABLgAECn8YAAMjAAcJyQY8CQDuAAAjAAcJyQY8CQDuAAAeAAYJYATg5wDIAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIIAAkJvgjDaABnAQAIAAkJvgjDaABnAQAAAA==.Monbow:BAAALgAECgMJBwABLgAECggJGQALAIgUAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8UAAIYAAQJiBhMFABYAQAYAAQJiBhMFABYAQAuAAQKf0QAAxgACQkHJNICAB0DABgACQkHJNICAB0DACQAAQkJFuUjAD0AAAAA.Morthis:BAABLgAECn8pAAMWAAgJ5wm3EgAmAQAWAAgJ5wm3EgAmAQADAAMJWgM0VABOAAAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8FAAISAAMJtw/vlgDUAAASAAMJtw/vlgDUAAAuAAQKfysAAhIACQlSG20kAGsCABIACQlSG20kAGsCAAAA.',
Na='Narcan:BAAALgAECgQJCAAAAA==.Naturalchi:BAABLgAECn8wAAMQAAkJByUzAgBGAwAQAAkJiiQzAgBGAwAlAAgJ8x7BCwBxAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAISAAIJ7wvB0QCHAAASAAIJ7wvB0QCHAAAAAA==.Nemas:BAABLgAECn8hAAICAAgJrxn6DQDXAQACAAgJrxn6DQDXAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8hAAQmAAcJ6BR7DgAYAQAZAAcJJhI6MwBcAQAmAAYJJRN7DgAYAQAaAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgQJBwABLgAECggJKAACAFAbAA==.Nineadin:BAACLgAFFH8OAAMBAAMJWw6yZgDQAAABAAMJWw6yZgDQAAAFAAMJ2RaiLAC8AAAuAAQKfycAAwUACQmYHU0TAHgCAAUACQmYHU0TAHgCAAEAAgkjHVn7AK8AAAAA.Ninetoads:BAAALgAECgcJDQABLgAFFAMJDgABAFsOAA==.Nirvanas:BAABLgAECn8cAAIVAAgJnguKGwAcAQAVAAgJnguKGwAcAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8nAAMhAAYJ6g6HOgD/AAAhAAYJ6g6HOgD/AAAfAAQJmQZZSwCsAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAAALgAECgQJEgAAAA==.Nullspace:BAABLgAECn8mAAIhAAkJXhoyEwAzAgAhAAkJXhoyEwAzAgAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn85AAIEAAgJKReUEwCqAQAEAAgJKReUEwCqAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJBwAMAPELAA==.',
Pa='Pakeydk:BAAALgAFFAIJBAAAAA==.Palacia:BAAALgAECggJDgAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgQJBQAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Petrichorica:BAAALgAECgcJEQAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAABLgAECn8XAAITAAkJlQUcbwBWAQATAAkJlQUcbwBWAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJBAABLgAECggJKAACAFAbAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQAPAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8eAAIhAAcJtA7uMwAnAQAhAAcJtA7uMwAnAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAAPAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAgAAAA==.Quiescent:BAABLgAECn8oAAILAAgJdRqVJwAhAgALAAgJdRqVJwAhAgAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8qAAMJAAgJkCWBAQDaAgAJAAgJkCWBAQDaAgAIAAEJAxG5LgE1AAABLgAFFAYJFQAKAGkkAA==.Ramanas:BAAALgAECggJEgAAAA==.Ramrod:BAAALgAECgIJAwAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB5AIAB9AgABAAkJtB5AIAB9AgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8tAAIIAAkJJg0iTACxAQAIAAkJJg0iTACxAQAAAA==.Relyn:BAAALgAECggJCQAAAA==.Resurgencê:BAABLgAECn8oAAICAAgJUBuMCgAUAgACAAgJUBuMCgAUAgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8kAAMBAAgJ6BTKiABTAQABAAcJChTKiABTAQACAAQJ9xPpIwDoAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJGwALAGseAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8YAAMNAAgJ3wPeiwCwAAANAAcJdAPeiwCwAAAiAAcJ4ASRbACSAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn80AAIOAAgJHxpTDwAJAgAOAAgJHxpTDwAJAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8WAAMmAAQJMhmYAwA2AQAZAAQJMhm/IQA5AQAmAAQJbBKYAwA2AQAuAAQKf0UABCYACQngIeYBALQCACYACQkAHeYBALQCABkACQnJIMcLAJYCABoABwnnEkESAJwBAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgYJCwAAAA==.Santose:BAAALgAECgEJAQAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAISAAkJExD8RwDiAQASAAkJExD8RwDiAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgkJQQADAKofAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgYJDAAAAA==.Seta:BAABLgAECn8bAAILAAgJ3xNeQwDmAQALAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBAAPAAAAAA==.Shamarha:BAABLgAECn8YAAINAAgJaBrzLwDnAQANAAgJaBrzLwDnAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9BAAQIAAgJwSN3PQDgAQAIAAYJmiF3PQDgAQAHAAQJ+CMLIABSAQAJAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shrieve:BAAALgAECgIJAgAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAAPAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKgutcACCAQABAAkJKgutcACCAQAAAA==.Simichaelton:BAACLgAFFH8IAAIeAAMJzRBGdwDiAAAeAAMJzRBGdwDiAAAuAAQKfxoAAh4ACQnDFKFEAAcCAB4ACQnDFKFEAAcCAAAA.Sinpal:BAABLgAFFH8GAAIBAAMJTxn+VQDwAAABAAMJTxn+VQDwAAABLgAFFAQJBwAIACUbAA==.Sioce:BAAALgADCgkJIgAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwANAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8qAAITAAgJcBr3KwAiAgATAAgJcBr3KwAiAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8mAAIXAAkJKBAbDgCCAQAXAAkJKBAbDgCCAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAIJAgAPAAAAAA==.Spycy:BAABLgAECn8UAAIeAAkJ3BCcgABwAQAeAAkJ3BCcgABwAQAAAA==.',
St='Stagerrind:BAAALgAECgQJBwAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMFAAkJOwxKMgCCAQAFAAkJOwxKMgCCAQABAAEJ9QdTmgEpAAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQzzdwCpAAABAAMJxQzzdwCpAAAuAAQKfyEAAgEACAkGIakdAIoCAAEACAkGIakdAIoCAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwAPAAAAAA==.Stubmcbean:BAAALgADCgEJAQABLgAECggJLQAbAGgFAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIeAAkJOguLmwA+AQAeAAkJOguLmwA+AQAAAA==.Suka:BAAALgAECgQJCgAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8aAAIJAAcJDAqgEwAiAQAJAAcJDAqgEwAiAQABLgAECgkJJgATABYSAA==.Sylentstorm:BAAALgAECgYJEQABLgAECgkJJgATABYSAA==.Syleta:BAABLgAECn9BAAQDAAkJqh80BgC5AgADAAgJpB40BgC5AgATAAcJwxwNMADwAQAWAAYJCRNpRABEAQAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8eAAMjAAgJ6xOVBACdAQAjAAgJ6xOVBACdAQAeAAEJ8QHxcQEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8jAAMBAAkJTBl2LwA4AgABAAkJTBl2LwA4AgACAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAABLgAECn8iAAIXAAgJ5A/SDgB3AQAXAAgJ5A/SDgB3AQAAAA==.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAQJDwAUAKEWAA==.Thelegendáry:BAACLgAFFH8LAAINAAQJbhBaNQD1AAANAAQJbhBaNQD1AAAuAAQKfxoAAg0ABgmWF0FKAFkBAA0ABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn8zAAMcAAgJGhriFgALAgAcAAgJGhriFgALAgAUAAgJmQokYQAIAQAAAA==.Tireck:BAAALgADCgMJAwAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8cAAIiAAkJHQkZOwA6AQAiAAkJHQkZOwA6AQAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgADCgIJAgAAAA==.Trisstan:BAABLgAECn8mAAMeAAgJ9wdxkwBMAQAeAAgJ9wdxkwBMAQAnAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMeAAkJshvmOAAuAgAeAAkJkBjmOAAuAgAjAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8JAAIBAAQJkBDJOgAmAQABAAQJkBDJOgAmAQAuAAQKfyMAAwEACQl0Fbw/AP0BAAEACQnGFLw/AP0BAAIAAQkbFi1GAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECggJLQAbAGgFAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAlAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMlAAkJWRoTJACDAQAlAAkJWRoTJACDAQAQAAEJyhIbhQBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAINAAgJxxbxLwDIAQANAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8XAAIeAAQJ7RaUUgA3AQAeAAQJ7RaUUgA3AQAuAAQKfy0AAh4ACQlDIkgfAJwCAB4ACQlDIkgfAJwCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMTAAkJtRvOJABDAgATAAkJtRvOJABDAgADAAIJewTpKgBVAAAAAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECggJHwAVAFsWAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECggJHwAVAFsWAA==.Warthog:BAAALgADCgYJCQAAAA==.Waterbender:BAABLgAECn8ZAAINAAkJRRquFwCAAgANAAkJRRquFwCAAgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECggJDQAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8eAAIBAAgJqxQYVgC+AQABAAgJqxQYVgC+AQAAAA==.Wilshaman:BAAALgAECgUJBgAAAA==.Window:BAAALgADCgUJBQABLgAECgcJGwALAGseAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8mAAIEAAkJNhePEQDBAQAEAAkJNhePEQDBAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgMJBgAAAA==.',
Wr='Wrekkit:BAAALgAECggJCAAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMTAAgJIhvAHQBTAgATAAgJIhvAHQBTAgAWAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIVAAgJuRpbCgALAgAVAAgJuRpbCgALAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAECgkJJQASAFsXAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8dAAISAAgJrR/MMgArAgASAAgJrR/MMgArAgAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8mAAMbAAgJ7xM/DwCwAQAbAAgJ7xM/DwCwAQANAAMJVghXrABeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8XAAMSAAUJ/xw1RgBVAQASAAUJ/xw1RgBVAQAXAAMJhxSzEADsAAAuAAQKf0YAAxIACQmiJXwGAD8DABIACQmiJXwGAD8DABcACAlQIX8DAJ0CAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAAPAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAAALgAFFAMJAwABLgAFFAMJCAAeAM0QAA==.',
Zp='Zpersephone:BAABLgAECn8VAAIIAAcJRxHsbwBWAQAIAAcJRxHsbwBWAQABLgAFFAUJFwASAP8cAA==.',
Zr='Zrii:BAAALgAECgYJBwAAAA==.',
Zu='Zultan:BAACLgAFFH8OAAIIAAQJawd1YAD1AAAIAAQJawd1YAD1AAAuAAQKfzkAAwgACQkCGRweAGkCAAgACQkCGRweAGkCAAcAAglmBAlEABkAAAAA.Zurrik:BAACLgAFFH8IAAMEAAQJyAUMIwB4AAAcAAQJhQKZLwCvAAAEAAMJYQYMIwB4AAAuAAQKfz0AAxwACQm0Ep8eAMYBABwACQnwEZ8eAMYBAAQAAgn+E7xGAHYAAAAA.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAIlAAMJqBTYEgDjAAAlAAMJqBTYEgDjAAAuAAQKfycAAyUACAmEHzsJAPUCACUACAmEHzsJAPUCABAAAwkjGUePADYAAAAA.',
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
