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

local lookup = {'Hunter-Survival','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Unknown-Unknown','Monk-Windwalker','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Mage-Frost','Priest-Shadow','Priest-Discipline','Priest-Holy','Shaman-Elemental','Rogue-Assassination','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Mage-Arcane','Mage-Fire','DemonHunter-Havoc',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abberleigh:BAAALgAECgUJBwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAAALgAFFAMJBAAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAAALgAECgUJEQABLgAECggJPwABAMggAA==.Alarlia:BAABLgAECn8jAAICAAgJvgszKQDoAAACAAgJvgszKQDoAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgAECgMJAwABLgAECggJKQADACoFAA==.Alliesofevil:BAABLgAECn8jAAIEAAgJKhQZIwDGAQAEAAgJKhQZIwDGAQAAAA==.Allsar:BAABLgAECn8aAAICAAkJnB0WBQCiAgACAAkJnB0WBQCiAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgACAJwdAA==.Alssar:BAAALgAECgYJCgAAAA==.',
Am='Amathushhg:BAACLgAFFH8HAAMFAAMJ8QRxDAC2AAAFAAMJywRxDAC2AAAGAAIJwgRlngB2AAAuAAQKf1IABAUACQnNF6oGANUBAAUACAnEGKoGANUBAAYACQn5E2BAAM8BAAcAAgnSDyQnAGYAAAAA.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAAALgAECggJEgAAAA==.Andreth:BAAALgAECgYJDQAAAA==.Anoxyn:BAAALgAECgcJBwAAAA==.Anthe:BAAALgAECgIJAgAAAA==.Anzul:BAABLgAECn8yAAMIAAkJVCB2HgB4AgAIAAkJQh92HgB4AgAJAAUJxB0RFwBMAQAAAA==.',
Ar='Araestirra:BAABLgAECn8dAAMFAAYJUA5nFADuAAAFAAYJTQ5nFADuAAAGAAYJrgOZ5wB2AAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAQJFAAGAD8EAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMKAAgJ6hSYCwCjAQAKAAgJ6hSYCwCjAQALAAEJagNtGwEbAAABLgAECgkJGgACAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAIMAAgJGB9REwBhAgAMAAgJGB9REwBhAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCQABLgAECgkJGgACAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAINAAkJOgqaRQB7AQANAAkJOgqaRQB7AQAAAA==.',
Az='Azerix:BAAALgAECgUJBQABLgAECgkJJQAOAFsXAA==.Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8TAAIPAAQJJBs9FAAdAQAPAAQJJBs9FAAdAQAuAAQKfzAAAg8ACQmtHLgMACYCAA8ACQmtHLgMACYCAAAA.Barbaydos:BAAALgADCggJCQAAAA==.Basement:BAABLgAECn8bAAILAAcJax6RLAAAAgALAAcJax6RLAAAAgAAAA==.',
Be='Beastnite:BAAALgADCggJHQABLgAECgYJDgAQAAAAAA==.Bellaburger:BAABLgAFFH8IAAIRAAQJsgZ9GgDiAAARAAQJsgZ9GgDiAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgQJBQABLgAECgkJPAAHACsfAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn8oAAIEAAgJLQdpQgAkAQAEAAgJLQdpQgAkAQAAAA==.Biped:BAABLgAECn8yAAIHAAkJPhOlBgDvAQAHAAkJPhOlBgDvAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAIOAAIJSgmyygCBAAAOAAIJSgmyygCBAAAuAAQKfyEAAg4ACAlRFVViAMwBAA4ACAlRFVViAMwBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Boomstique:BAABLgAECn8oAAISAAgJVBbGNwDnAQASAAgJVBbGNwDnAQAAAA==.Boondocka:BAABLgAECn8dAAISAAgJdBesMwD3AQASAAgJdBesMwD3AQAAAA==.',
Br='Brewco:BAACLgAFFH8MAAITAAQJoRZ8JQAYAQATAAQJoRZ8JQAYAQAuAAQKfzYABBMACAnRHqYUAJACABMACAnRHqYUAJACABQABgnDG48PAJoBAAIABQl6Dx0zALUAAAAA.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8lAAISAAkJFhJzNAD0AQASAAkJFhJzNAD0AQAAAA==.',
Bt='Btrain:BAABLgAECn8eAAMJAAYJ3ArALACgAAAIAAYJzQY84gC8AAAJAAUJgAzALACgAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQBAAcJwx/hGwCvAQABAAcJrh3hGwCvAQASAAQJNx5HXgBNAQAVAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn88AAMHAAkJKx9uAQDTAgAHAAkJPx5uAQDTAgAGAAkJWBjLNAD5AQAAAA==.',
Ce='Cedric:BAAALgADCgMJAwAAAA==.Cenobité:BAABLgAECn8mAAIWAAkJ0RNZCADaAQAWAAkJ0RNZCADaAQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJGwALAGseAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIXAAMJlBUmDQAVAQAXAAMJlBUmDQAVAQAAAA==.Charmeleon:BAAALgAECggJEQAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgMJAwAAAA==.Chip:BAAALgAECgMJAwAAAA==.',
Ci='Cirax:BAABLgAECn8kAAISAAgJBhUTOwDbAQASAAgJBhUTOwDbAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn9MAAMJAAkJZAtoGAA/AQAJAAkJ0gloGAA/AQAIAAgJCQijnwAdAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8NAAILAAQJNhmiMgAyAQALAAQJNhmiMgAyAQAuAAQKfy4AAgsACAkpIm8VAIQCAAsACAkpIm8VAIQCAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn8jAAISAAgJLRF3UgCTAQASAAgJLRF3UgCTAQAAAA==.',
Cy='Cyris:BAAALgAECgMJAwABLgAECggJJgAYAAQEAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJGwALAGseAA==.',
Da='Daemonfaust:BAAALgAECgYJDgAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgEJAQAAAA==.Dak:BAABLgAECn8lAAIOAAkJWxfXKQBGAgAOAAkJWxfXKQBGAgAAAA==.Dalsar:BAAALgAECggJDgAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECggJKAAJAFAbAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8UAAIGAAQJPwTRXgDtAAAGAAQJPwTRXgDtAAAuAAQKfzsAAwYACAl1EdxaAIIBAAYACAl1EdxaAIIBAAUAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJAgAAAA==.Darthbluto:BAAALgAECgUJCQAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8eAAIIAAgJ4xQvbAB8AQAIAAgJ4xQvbAB8AQAAAA==.',
De='Deadazz:BAAALgADCgYJBwAAAA==.Deadmangalad:BAABLgAECn8jAAMWAAgJQwdgFQACAQAWAAgJQwdgFQACAQAPAAEJFARIXwAXAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8WAAIZAAYJhgZCTwCzAAAZAAYJhgZCTwCzAAAAAA==.Demonbo:BAABLgAECn8ZAAILAAgJiBTFWgBfAQALAAgJiBTFWgBfAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8SAAMEAAQJUx4YDACBAQAEAAQJUx4YDACBAQAaAAMJMBSAHgDRAAAuAAQKfzoAAwQACQkmJN4CADMDAAQACQkmJN4CADMDABoAAgmSDUdXAFkAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8nAAMSAAgJYhlFJwAcAgASAAgJYhlFJwAcAgABAAUJYQsMOQDbAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgMJAwAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIbAAMJ7gN8fwC7AAAbAAMJ7gN8fwC7AAAuAAQKfxUAAhsACAnCDch1AHMBABsACAnCDch1AHMBAAAA.',
Do='Dogminos:BAAALgADCgIJAgAAAA==.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECgUJCwAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJEgAEAFMeAA==.Drphilyobody:BAABLgAECn8cAAIOAAcJCQiHnwAXAQAOAAcJCQiHnwAXAQAAAA==.Drui:BAABLgAECn8dAAIZAAgJsQ4dNgBkAQAZAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAABLgAECn8eAAIcAAcJbwqvOQAJAQAcAAcJbwqvOQAJAQAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8bAAMBAAkJwgbqHQCeAQABAAkJwgbqHQCeAQAVAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn8yAAIbAAgJExT+WgC0AQAbAAgJExT+WgC0AQAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgIJAgABLgAECgUJCAAQAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgADCgcJEQAAAA==.Elaric:BAAALgAECgEJAQAAAA==.',
Ep='Epikrate:BAABLgAECn8eAAMGAAgJURnnOQDlAQAGAAcJIRnnOQDlAQAFAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn80AAIWAAgJhROdDAB+AQAWAAgJhROdDAB+AQAAAA==.',
Ex='Extrema:BAAALgAECgUJCwAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJEwAbAGsfAA==.Fallenembers:BAACLgAFFH8TAAIbAAQJax/ONABtAQAbAAQJax/ONABtAQAuAAQKfzkAAhsACQlJJSIFAEwDABsACQlJJSIFAEwDAAAA.Famine:BAABLgAECn8dAAMOAAgJ0AUAqAAKAQAOAAgJwwQAqAAKAQAWAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAgAQAAAAAA==.',
Fh='Fhait:BAAALgAECgMJAwABLgAECggJKgARAHMKAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIXAAIJJg3PLACQAAAXAAIJJg3PLACQAAAuAAQKfx4AAhcACQnaE7oRAAMCABcACQnaE7oRAAMCAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgAECgIJAgABLgAECggJIwAWAEMHAA==.Gaskelmarg:BAAALgAECgMJAwAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQdAAkJIRWaGwDQAQAdAAkJsRGaGwDQAQAeAAcJpAuKTgD+AAAcAAEJcAFQiAAZAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJBQAFANENAA==.',
Gi='Gigaweed:BAAALgAFFAMJAwABLgAFFAMJBQAFANENAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8fAAIUAAgJWxYMDADWAQAUAAgJWxYMDADWAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8kAAIGAAcJxxkdQgDJAQAGAAcJxxkdQgDJAQAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgADCggJDQABLgAECggJKAAJAFAbAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAECgMJAwAQAAAAAA==.Hettokal:BAAALgAECgQJBAAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8cAAILAAkJchEPQACxAQALAAkJchEPQACxAQAAAA==.Hondojoe:BAACLgAFFH8SAAIeAAQJNx5fDwA0AQAeAAQJNx5fDwA0AQAuAAQKfzQAAx4ACQnuICAJAMICAB4ACQnuICAJAMICAB0AAgnYBgBnADoAAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn8pAAIDAAgJKgVoQgAhAQADAAgJKgVoQgAhAQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn8oAAIKAAgJBArlEgAFAQAKAAgJBArlEgAFAQABLgAECggJKgARAHMKAA==.Huhu:BAABLgAECn8ZAAIEAAkJrxTRJQC0AQAEAAkJrxTRJQC0AQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJBwASALkMAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8pAAIaAAkJ9gpUGgBwAQAaAAkJ9gpUGgBwAQAAAA==.',
Ic='Icyhot:BAAALgADCgUJCAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgAECgUJDAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAILAAkJyRd8KQAOAgALAAkJyRd8KQAOAgAAAA==.Ivylyn:BAAALgADCgkJDwAAAA==.',
Ix='Ixiyá:BAABLgAECn87AAMNAAkJMSOUAwBvAwANAAkJMSOUAwBvAwAfAAEJzgjulgAtAAAAAA==.Ixií:BAAALgADCgUJBQAAAA==.Ixì:BAABLgAECn8WAAITAAcJ1x02HwA5AgATAAcJ1x02HwA5AgAAAA==.',
Ja='Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBAAQAAAAAA==.Jakota:BAAALgADCggJDAAAAA==.Jakskeleton:BAABLgAECn8VAAIPAAcJMhboGgBrAQAPAAcJMhboGgBrAQAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEQAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgcJCgAAAA==.',
Jo='Joemacho:BAAALgAECgcJDQABLgAFFAQJEgAeADceAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.',
Ju='Judax:BAABLgAECn89AAIfAAkJtBtaEABbAgAfAAkJtBtaEABbAgAAAA==.Justagirl:BAABLgAECn8qAAIRAAgJcwqfLwAyAQARAAgJcwqfLwAyAQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgADCggJCAAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAABLgAECn8eAAISAAgJfRUbTwCcAQASAAgJfRUbTwCcAQAAAA==.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIXAAgJISMwCAANAwAXAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8UAAMPAAgJQhoaGACIAQAPAAgJQhoaGACIAQAOAAIJtQToLgFQAAAAAA==.Karen:BAAALgADCgcJGAAAAA==.Karne:BAAALgADCgYJBgAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8cAAIPAAYJzxotIgAmAQAPAAYJzxotIgAmAQAAAA==.Keelay:BAABLgAECn83AAIDAAgJyh6dDgCVAgADAAgJyh6dDgCVAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIIAAgJjRhqTwDzAQAIAAgJjRhqTwDzAQABLgAECgkJJQAOAFsXAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwAQAAAAAA==.Kimiko:BAAALgAECgcJCwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAXACEjAA==.',
Ko='Koffcmorbius:BAAALgADCgYJDAAAAA==.Koriban:BAABLgAECn8lAAIbAAkJaA5AXwCpAQAbAAkJaA5AXwCpAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAbAGgOAA==.',
Kr='Kraken:BAACLgAFFH8FAAIFAAMJ0Q3oCQDSAAAFAAMJ0Q3oCQDSAAAuAAQKfyoAAgUACQlzIrwAAAgDAAUACQlzIrwAAAgDAAAA.',
Ku='Kubb:BAABLgAECn8mAAIYAAgJBARtGwD9AAAYAAgJBARtGwD9AAAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8PAAIUAAQJ7iJQAgCUAQAUAAQJ7iJQAgCUAQAuAAQKfy0AAxQACQk6IxoFAMACABQACQk6IxoFAMACABkABQkbDsk/APMAAAAA.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8iAAMHAAgJuwXkEgAaAQAHAAgJuwXkEgAaAQAFAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8KAAILAAUJwBN+NAArAQALAAUJwBN+NAArAQAAAA==.Laurlynn:BAAALgAECgMJAwAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJCgABLgAECgYJJwAeAOoOAA==.Lettuceprey:BAABLgAECn8jAAIeAAgJXA/HJwByAQAeAAgJXA/HJwByAQAAAA==.',
Li='Lierise:BAAALgAECgUJBQAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgMJAQAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.',
Lo='Lockatute:BAAALgAECggJCgAAAA==.Lockdeath:BAAALgAECgQJBwAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAAALgAECggJDgAAAA==.',
Lu='Lucille:BAAALgAFFAEJBAAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8ZAAMUAAgJ1hcZDADVAQAUAAgJ1hcZDADVAQATAAEJGwYk2gAjAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgMJAwAAAA==.Magicdance:BAABLgAECn8vAAMNAAkJ1RDiQgCGAQANAAgJexHiQgCGAQAfAAkJKgkHOgAyAQAAAA==.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIUAAgJchK/CwACAgAUAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8ZAAIfAAgJNRb/HQDZAQAfAAgJNRb/HQDZAQAAAA==.Maki:BAAALgAECggJEwAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJGwALAGseAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAQAAAA==.',
Mc='Mctowlie:BAAALgAECgYJBwAAAA==.',
Me='Mehänemäntä:BAAALgAECgUJCwAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMWAAcJqBUoEABAAQAOAAYJJRKQlABXAQAWAAUJWBUoEABAAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAECgkJLwANANUQAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAACLgAFFH8QAAIRAAQJUySwBQCcAQARAAQJUySwBQCcAQAuAAQKfzsAAhEACQkYJi0BAGcDABEACQkYJi0BAGcDAAAA.Misstreater:BAAALgAECgcJEgAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIGAAkJvgjDYwBsAQAGAAkJvgjDYwBsAQAAAA==.Monbow:BAAALgAECgMJBgABLgAECggJGQALAIgUAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8RAAIXAAQJQxZ0EwBQAQAXAAQJQxZ0EwBQAQAuAAQKf0IAAxcACQkxIxQDAAwDABcACQkxIxQDAAwDACAAAQkJFkQiAD0AAAAA.Morthis:BAABLgAECn8jAAMVAAgJHwlVEgAgAQAVAAgJ/AhVEgAgAQABAAMJWgPRUABOAAAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Myris:BAACLgAFFH8FAAIOAAMJtw/ZiADVAAAOAAMJtw/ZiADVAAAuAAQKfygAAg4ACQkJGuAlAFgCAA4ACQkJGuAlAFgCAAAA.',
Na='Narcan:BAAALgAECgQJBAAAAA==.Naturalchi:BAABLgAECn8wAAMRAAkJByXsAQBLAwARAAkJiiTsAQBLAwAhAAgJ8x4ICwByAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAAALgAFFAIJAwAAAA==.Nemas:BAABLgAECn8hAAIJAAgJrxnADADeAQAJAAgJrxnADADeAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8hAAQiAAcJ6BSQMABWAQAiAAcJJhKQMABWAQAjAAYJJRPODQAfAQAkAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgMJAwABLgAECggJKAAJAFAbAA==.Nineadin:BAACLgAFFH8LAAIDAAMJ2RZZKQDFAAADAAMJ2RZZKQDFAAAuAAQKfyUAAgMACQmYHU0TAHgCAAMACQmYHU0TAHgCAAAA.Ninetoads:BAAALgAECgcJDQAAAA==.Nirvanas:BAABLgAECn8YAAIUAAgJ9gbbHgDqAAAUAAgJ9gbbHgDqAAAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8nAAMeAAYJ6g6wNwAIAQAeAAYJ6g6wNwAIAQAcAAQJmQZZSwCsAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAAALgAECgQJEgAAAA==.Nullspace:BAABLgAECn8mAAIeAAkJXhqlEQA8AgAeAAkJXhqlEQA8AgAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
Ny='Nyxe:BAAALgADCgkJCQABLgAECgkJJQAOAFsXAA==.',
['Ní']='Níght:BAABLgAECn85AAICAAgJKRfrEQCsAQACAAgJKRfrEQCsAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJBQAFANENAA==.',
Pa='Pakeydk:BAAALgAFFAIJBAAAAA==.Palacia:BAAALgAECgcJDAAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgQJBQAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Petrichorica:BAAALgAECgcJCwAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAABLgAECn8XAAISAAkJlQWGaABaAQASAAkJlQWGaABaAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJBAABLgAECggJKAAJAFAbAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQAQAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8eAAIeAAcJtA6uMAAzAQAeAAcJtA6uMAAzAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAAQAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAgAAAA==.Quiescent:BAABLgAECn8fAAILAAcJGxveNQDYAQALAAcJGxveNQDYAQAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8oAAMHAAgJ9CR+AQDPAgAHAAgJ9CR+AQDPAgAGAAEJAxEJIgE3AAABLgAFFAYJFQAKAGkkAA==.Ramanas:BAAALgAECggJEgAAAA==.Randomizwe:BAABLgAECn8uAAIIAAkJtB4wHQB/AgAIAAkJtB4wHQB/AgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8oAAIGAAkJAg3cSAC0AQAGAAkJAg3cSAC0AQAAAA==.Relyn:BAAALgAECggJCAAAAA==.Resurgencê:BAABLgAECn8oAAIJAAgJUBu9CQAXAgAJAAgJUBu9CQAXAgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8gAAMIAAgJGxQKgwBOAQAIAAcJChQKgwBOAQAJAAEJfxTZRAA7AAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJGwALAGseAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8YAAMNAAgJ3wO2hACxAAANAAcJdAO2hACxAAAfAAcJ4ASkZQCXAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn8rAAIPAAgJBBbcEwC6AQAPAAgJBBbcEwC6AQAAAA==.',
Ry='Rynzia:BAACLgAFFH8TAAMiAAQJMhmxHABCAQAiAAQJMhmxHABCAQAjAAMJowiSBgDQAAAuAAQKf0MABCIACQmGIegKAJECACIACQnJIOgKAJECACMABwlOIPoDADECACQABwnnEqERAJsBAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgUJCgAAAA==.Santose:BAAALgAECgEJAQAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAIOAAkJExAlRADjAQAOAAkJExAlRADjAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECggJPwABAMggAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgUJCwAAAA==.Seta:BAABLgAECn8bAAILAAgJ3xNeQwDmAQALAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBAAQAAAAAA==.Shamarha:BAAALgAECggJEwAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9AAAQGAAgJwSN1OgDkAQAGAAYJmiF1OgDkAQAFAAQJ+CMLIABSAQAHAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJDgAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAAQAAAAAA==.Siggismund:BAABLgAECn8pAAIIAAkJsQrDbQB5AQAIAAkJsQrDbQB5AQAAAA==.Simichaelton:BAACLgAFFH8IAAIbAAMJzRBPbgDlAAAbAAMJzRBPbgDlAAAuAAQKfxkAAhsACQmwFEVAAAUCABsACQmwFEVAAAUCAAAA.Sinpal:BAABLgAFFH8FAAIIAAMJYRM/UwDmAAAIAAMJYRM/UwDmAAABLgAFFAQJBgAGACUbAA==.Sioce:BAAALgADCgkJFAAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBgABLgAECgcJHwANAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIIAAgJ/BxdSQAGAgAIAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8lAAISAAgJDhfHMgD7AQASAAgJDhfHMgD7AQAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8mAAIWAAkJKBD6DAB4AQAWAAkJKBD6DAB4AQAAAA==.Spookems:BAAALgAECgIJAgABLgAECgkJEQAQAAAAAA==.Spycy:BAABLgAECn8UAAIbAAkJ3BBJdgByAQAbAAkJ3BBJdgByAQAAAA==.',
St='Stagerrind:BAAALgAECgMJAwAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMDAAkJOwzwLwCEAQADAAkJOwzwLwCEAQAIAAEJ9QeaiQEpAAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIIAAMJxQywagCwAAAIAAMJxQywagCwAAAuAAQKfyEAAggACAkGIdIaAIsCAAgACAkGIdIaAIsCAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwAQAAAAAA==.Stubmcbean:BAAALgADCgEJAQABLgAECggJJgAYAAQEAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIbAAkJOgtwpwCKAQAbAAkJOgtwpwCKAQAAAA==.Suka:BAAALgAECgMJBgAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8UAAIHAAcJxQfwEwALAQAHAAcJxQfwEwALAQABLgAECgkJJQASABYSAA==.Sylentstorm:BAAALgAECgYJDgABLgAECgkJJQASABYSAA==.Syleta:BAABLgAECn8/AAQBAAgJyCBPCgBtAgABAAcJnR9PCgBtAgASAAcJwxwNMADwAQAVAAYJCRNpRABEAQAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8eAAMlAAgJ6xM+BACiAQAlAAgJ6xM+BACiAQAbAAEJ8QHHYgEdAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8jAAMIAAkJTBmbKwA6AgAIAAkJTBmbKwA6AgAJAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAABLgAECn8bAAIWAAgJUw5TDwBMAQAWAAgJUw5TDwBMAQAAAA==.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAQJDAATAKEWAA==.Thelegendáry:BAACLgAFFH8LAAINAAQJbhCuLwABAQANAAQJbhCuLwABAQAuAAQKfxkAAg0ABgmWF0FKAFkBAA0ABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn8uAAMZAAcJZBtoGwDVAQAZAAcJZBtoGwDVAQATAAcJZgkpfgCuAAAAAA==.Tireck:BAAALgADCgEJAQAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8cAAIfAAkJHQkmNwBAAQAfAAkJHQkmNwBAAQAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgADCgIJAgAAAA==.Trisstan:BAABLgAECn8mAAMbAAgJ9wdXlAA1AQAbAAgJ9wdXlAA1AQAmAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMbAAkJshskNQAsAgAbAAkJkBgkNQAsAgAlAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8FAAIIAAMJswzJXgDRAAAIAAMJswzJXgDRAAAuAAQKfyAAAggACQlPE3JHANgBAAgACQlPE3JHANgBAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJAwAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECggJJgAYAAQEAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAhAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMhAAkJWRpkIgCFAQAhAAkJWRpkIgCFAQARAAEJyhJYfgBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAINAAgJxxbxLwDIAQANAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8UAAIbAAQJ7RYCSQA8AQAbAAQJ7RYCSQA8AQAuAAQKfysAAhsACAnPIlcxADwCABsACAnPIlcxADwCAAAA.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMSAAkJtRv4IABLAgASAAkJtRv4IABLAgABAAIJewTpKgBVAAABLgAECggJIQAnAO4iAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgAIAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECggJHwAUAFsWAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECggJHwAUAFsWAA==.Warthog:BAAALgADCgYJCQAAAA==.Waterbender:BAABLgAECn8ZAAINAAkJRRrSFQCCAgANAAkJRRrSFQCCAgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECggJDQAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8XAAIIAAcJBA9ElgAsAQAIAAcJBA9ElgAsAQAAAA==.Wilshaman:BAAALgAECgUJAwAAAA==.Window:BAAALgADCgUJBQABLgAECgcJGwALAGseAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8mAAICAAkJNhe7DwDKAQACAAkJNhe7DwDKAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgMJAwAAAA==.',
Wr='Wrekkit:BAAALgAECggJCAAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMSAAgJIhvAHQBTAgASAAgJIhvAHQBTAgAVAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIUAAgJuRqDCQANAgAUAAgJuRqDCQANAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAECgkJJQAOAFsXAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8bAAIOAAcJzx42VAC0AQAOAAcJzx42VAC0AQAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8kAAMYAAgJfxP0EQB1AQAYAAcJuBT0EQB1AQANAAMJVgi+owBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8SAAMOAAQJ/xzrOgBcAQAOAAQJ/xzrOgBcAQAWAAIJYgUvGQB5AAAuAAQKf0YAAw4ACQmiJZ0FAEIDAA4ACQmiJZ0FAEIDABYACAlQIQkDAJkCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAAQAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAAALgAECgQJBwABLgAFFAMJCAAbAM0QAA==.',
Zp='Zpersephone:BAABLgAECn8VAAIGAAcJRxFoagBcAQAGAAcJRxFoagBcAQABLgAFFAQJEgAOAP8cAA==.',
Zr='Zrii:BAAALgAECgUJBgAAAA==.',
Zu='Zultan:BAACLgAFFH8LAAIGAAQJawcnWAD/AAAGAAQJawcnWAD/AAAuAAQKfzcAAwYACQkCGTccAG0CAAYACQkCGTccAG0CAAUAAQkAAOpKAAAAAAAA.Zurrik:BAACLgAFFH8FAAIZAAQJhQJJKwCwAAAZAAQJhQJJKwCwAAAuAAQKfzsAAxkACQkMEpYcAMsBABkACQnwEZYcAMsBAAIAAQmbFy1WAEUAAAAA.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAIhAAMJqBTYEgDjAAAhAAMJqBTYEgDjAAAuAAQKfycAAyEACAmEHzsJAPUCACEACAmEHzsJAPUCABEAAwkjGeWGADcAAAAA.',
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
