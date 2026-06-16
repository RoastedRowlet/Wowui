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

local lookup = {'Paladin-Retribution','Paladin-Protection','Hunter-Survival','Druid-Guardian','Paladin-Holy','Warrior-Fury','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','DemonHunter-Vengeance','DemonHunter-Devourer','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','Unknown-Unknown','Monk-Windwalker','Warrior-Protection','DeathKnight-Unholy','Hunter-BeastMastery','Druid-Restoration','Druid-Feral','Hunter-Marksmanship','DeathKnight-Frost','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Mage-Frost','Priest-Shadow','Priest-Discipline','Priest-Holy','Shaman-Elemental','Mage-Arcane','Rogue-Assassination','Monk-Brewmaster','Evoker-Devastation','Mage-Fire',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abberleigh:BAAALgAFFAMJAwAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgAECgMJAwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Ak='Akshhan:BAABLgAFFH8IAAIBAAUJlxBpRgAaAQABAAUJlxBpRgAaAQAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAABLgAECn8gAAMCAAcJkyHuCABCAgACAAcJkyHuCABCAgABAAIJ4xW0LgF8AAABLgAECgkJRQADAN0fAA==.Alarlia:BAABLgAECn8jAAIEAAgJvgskMADlAAAEAAgJvgskMADlAAAAAA==.Alathor:BAAALgAECgEJAQAAAA==.Algonq:BAAALgAECgQJCgABLgAECggJMQAFAAIGAA==.Alliesofevil:BAABLgAECn8kAAIGAAgJlxRcJQDLAQAGAAgJlxRcJQDLAQAAAA==.Allsar:BAABLgAECn8aAAIEAAkJnB0RBgCeAgAEAAkJnB0RBgCeAgAAAA==.Alsar:BAAALgAECgQJBwABLgAECgkJGgAEAJwdAA==.Alssar:BAAALgAECgYJCgAAAA==.Alstar:BAAALgAECgEJAgAAAA==.',
Am='Amathushhg:BAACLgAFFH8JAAMHAAUJkQTkDwCxAAAHAAQJywTkDwCxAAAIAAMJUgQYigCrAAAuAAQKf2cABAcACQlmGt4DAEkCAAcACQkaGt4DAEkCAAgACQn5E1VGAMYBAAkABAmnDwsbAOEAAAAA.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAABLgAECn8XAAIKAAgJZwtSJwA7AQAKAAgJZwtSJwA7AQAAAA==.Andreth:BAAALgAECgcJEQAAAA==.Anoxyn:BAAALgAECgcJBwAAAA==.Anthe:BAAALgAECgQJBgAAAA==.Anzul:BAABLgAECn8yAAMBAAkJVCDdIwB0AgABAAkJQh/dIwB0AgACAAUJxB2uGQBJAQAAAA==.',
Ar='Araestirra:BAABLgAECn8oAAMHAAcJcg3NFgDpAAAHAAYJTQ7NFgDpAAAIAAcJcwbprQDnAAAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAUJGgAIAHEEAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8XAAMLAAgJ6hSYCwCjAQALAAgJ6hSYCwCjAQAMAAEJagNcNQEbAAABLgAECgkJGgAEAJwdAA==.Arntdorn:BAAALgADCgEJAQAAAA==.Arroes:BAABLgAECn8ZAAINAAgJGB9PFgBhAgANAAgJGB9PFgBhAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
At='Atlas:BAAALgAECggJCgABLgAECgkJGgAEAJwdAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgAECgMJAwAAAA==.',
Ay='Ayroona:BAABLgAECn8pAAIOAAkJOgoeTQB4AQAOAAkJOgoeTQB4AQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8ZAAIPAAQJmB0rFABIAQAPAAQJmB0rFABIAQAuAAQKfzMAAg8ACQkzHfUNACkCAA8ACQkzHfUNACkCAAAA.Balka:BAAALgADCgYJCAAAAA==.Barbaydos:BAAALgADCggJCQAAAA==.Barenjager:BAAALgAECgEJAQAAAA==.Basement:BAABLgAECn8bAAIMAAcJax52MAABAgAMAAcJax52MAABAgAAAA==.',
Be='Beastnite:BAAALgADCgkJJQABLgAECgYJEgAQAAAAAA==.Bellaburger:BAABLgAFFH8IAAIRAAQJsgYHIQDOAAARAAQJsgYHIQDOAAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgYJDwABLgAECgkJRgAJALYgAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAABLgAECn8vAAMGAAgJNwomPwBHAQAGAAgJ/AkmPwBHAQASAAMJgwzTOwB/AAAAAA==.Biped:BAABLgAECn8zAAIJAAkJPhMdCADlAQAJAAkJPhMdCADlAQAAAA==.Birill:BAAALgAECgEJAgAAAA==.Bishul:BAAALgAECgYJBgAAAA==.',
Bl='Blackdeath:BAACLgAFFH8FAAITAAIJSgk95QCBAAATAAIJSgk95QCBAAAuAAQKfycAAhMACAlwGHtgAKUBABMACAlwGHtgAKUBAAAA.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Bone:BAAALgAECgEJAQAAAA==.Boomstique:BAABLgAECn8wAAIUAAgJMxftOQDzAQAUAAgJMxftOQDzAQAAAA==.Boondocka:BAABLgAECn8yAAIUAAkJfBn1GwB5AgAUAAkJfBn1GwB5AgAAAA==.',
Br='Brewco:BAACLgAFFH8PAAIVAAQJoRaQLAD9AAAVAAQJoRaQLAD9AAAuAAQKfzgABBUACQkEHKYUAJACABUACQkEHKYUAJACABYABgnDG+YRAJYBAAQABQl6D2k7ALIAAAAA.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAABLgAECn8oAAIUAAkJFhKmPQDmAQAUAAkJFhKmPQDmAQAAAA==.',
Bt='Btrain:BAABLgAECn8hAAMCAAYJ3AriMACfAAABAAYJzQa+7wDHAAACAAUJgAziMACfAAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8bAAQDAAcJwx9+HgCoAQADAAcJrh1+HgCoAQAUAAQJNx5HXgBNAQAXAAEJPgJtmAAeAAAAAA==.',
Ca='Camaryn:BAAALgADCgIJAgAAAA==.Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cattnip:BAAALgAECgEJAQAAAA==.Cavisch:BAABLgAECn9GAAMJAAkJtiAPAQABAwAJAAkJtiAPAQABAwAIAAkJWBg3OgDwAQAAAA==.',
Ce='Cedric:BAAALgADCgMJAwABLgAECgYJBgAQAAAAAA==.Cenobité:BAABLgAECn8qAAIYAAkJOxSsCQDmAQAYAAkJOxSsCQDmAQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgAECgYJCAABLgAECgcJGwAMAGseAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIZAAMJlBUmDQAVAQAZAAMJlBUmDQAVAQAAAA==.Charmeleon:BAABLgAECn8UAAMaAAgJCRIGQAAmAQAaAAgJCRIGQAAmAQAbAAIJfAxsMwBWAAAAAA==.Charmin:BAAALgADCgUJBQAAAA==.Chiff:BAAALgADCgUJAwAAAA==.Chilledog:BAAALgADCgQJBAAAAA==.Chip:BAAALgAECgMJBgAAAA==.',
Ci='Cirax:BAABLgAECn8pAAIUAAgJ6xWtPADpAQAUAAgJ6xWtPADpAQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Cleetess:BAAALgAECgEJAQAAAA==.Clenton:BAABLgAECn9eAAMCAAkJpwxTGABXAQACAAkJRgtTGABXAQABAAgJCQgUrAAiAQAAAA==.Clipper:BAAALgADCgYJBgAAAA==.',
Co='Cobrakai:BAAALgAECgIJAgAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8TAAIMAAQJ9RkMPAAuAQAMAAQJ9RkMPAAuAQAuAAQKfzEAAgwACQm0IUkMAOECAAwACQm0IUkMAOECAAAA.Cronnan:BAAALgAECgUJBQAAAA==.Crowford:BAABLgAECn8vAAIUAAgJdBMoTQC2AQAUAAgJdBMoTQC2AQAAAA==.',
Cy='Cyris:BAAALgAECgMJAwABLgAECggJMAAcAIsFAA==.',
['Cá']='Cástle:BAAALgAECgEJAQABLgAECgcJGwAMAGseAA==.',
Da='Daemonfaust:BAAALgAECgYJDwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dahtty:BAAALgAECgYJBwAAAA==.Dak:BAABLgAECn8lAAITAAkJWxfLLwA9AgATAAkJWxfLLwA9AgABLgAECggJGwABAI0YAA==.Daksclaw:BAAALgAECgYJBgABLgAECggJGwABAI0YAA==.Daksmash:BAAALgAECgUJBQAAAA==.Dakstab:BAAALgADCgkJCQAAAA==.Dalsar:BAAALgAECggJDgAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECggJLAACAM0bAA==.Darkfes:BAAALgAECgEJAQAAAA==.Darkmiza:BAACLgAFFH8aAAIIAAUJcQT6awDlAAAIAAUJcQT6awDlAAAuAAQKfzsAAwgACAl1EVtjAHgBAAgACAl1EVtjAHgBAAcAAglDC0lYAGYAAAAA.Darkseer:BAAALgAFFAIJAwAAAA==.Darthbluto:BAAALgAECgUJDQABLgAECgYJDwAQAAAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8iAAIBAAkJHRasSADqAQABAAkJHRasSADqAQAAAA==.',
De='Deadazz:BAAALgADCgYJCgAAAA==.Deadmangalad:BAABLgAECn8qAAMYAAgJWAn6FAAwAQAYAAgJWAn6FAAwAQAPAAEJFAQOaQAWAAAAAA==.Deathnotes:BAAALgADCgEJAQAAAA==.Deathquina:BAAALgAECgMJAwAAAA==.Deathtickle:BAAALgAECgcJAwAAAA==.Deedees:BAABLgAECn8eAAIdAAgJ5QYRQgABAQAdAAgJ5QYRQgABAQAAAA==.Demonbo:BAABLgAECn8aAAIMAAgJiBSxYgBfAQAMAAgJiBSxYgBfAQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8YAAMGAAQJGiDnEAB6AQAGAAQJGiDnEAB6AQAeAAMJMBQaJwDLAAAuAAQKfzwAAwYACQkmJNYDACkDAAYACQkmJNYDACkDAB4AAgmSDZFhAFoAAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8tAAMUAAgJYhlFJwAcAgAUAAgJYhlFJwAcAgADAAUJYQuFPQDVAAAAAA==.Dessirius:BAAALgAECgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Dies:BAAALgAECgkJBAAAAA==.Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgAECgQJBwAAAA==.Diskbänk:BAAALgAECgUJBwAAAA==.',
Dk='Dkho:BAACLgAFFH8FAAIfAAMJ7gPojwC4AAAfAAMJ7gPojwC4AAAuAAQKfxUAAh8ACAnCDRl+AHgBAB8ACAnCDRl+AHgBAAAA.',
Dr='Drago:BAAALgAECgEJBAAAAA==.Dragontoast:BAAALgAECgcJDgAAAA==.Dral:BAEALgADCgkJKAAAAA==.Draygun:BAAALgAECgcJBwABLgAFFAQJGAAGABogAA==.Drphilyobody:BAABLgAECn8cAAITAAcJCQiFrgATAQATAAcJCQiFrgATAQAAAA==.Drui:BAABLgAECn8dAAIdAAgJsQ4dNgBkAQAdAAgJsQ4dNgBkAQAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAABLgAECn8jAAIgAAcJVQsYPgAWAQAgAAcJVQsYPgAWAQAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAABLgAECn8iAAMDAAkJugi+HAC2AQADAAkJugi+HAC2AQAXAAUJRANPYgC3AAAAAA==.Eatmyfrontal:BAABLgAECn85AAIfAAgJIBoXPgAgAgAfAAgJIBoXPgAgAgAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgMJAwABLgAECgcJCwAQAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgAECgMJAwAAAA==.Elaric:BAAALgAECgYJBgAAAA==.',
En='Engi:BAAALgAECgUJCQAAAA==.',
Ep='Epikrate:BAABLgAECn8eAAMIAAgJURkePwDfAQAIAAcJIRkePwDfAQAHAAMJ4hiqSACUAAAAAA==.',
Es='Escaper:BAABLgAECn82AAIYAAkJcxIxCwDDAQAYAAkJcxIxCwDDAQAAAA==.',
Ex='Extrema:BAAALgAECgcJDgAAAA==.',
Ez='Ezsdruid:BAAALgAECgkJCQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAQJFgAfAGsfAA==.Fallenembers:BAACLgAFFH8WAAIfAAQJax+wQgBoAQAfAAQJax+wQgBoAQAuAAQKfzsAAh8ACQlJJWoGAEwDAB8ACQlJJWoGAEwDAAAA.Famine:BAABLgAECn8dAAMTAAgJ0AXJuAAFAQATAAgJwwTJuAAFAQAYAAUJzAf7DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQABLgAECgkJAgAQAAAAAA==.',
Fh='Fhait:BAAALgAECgUJCAABLgAECggJMgARACcMAA==.',
Fi='Firsttimepvp:BAACLgAFFH8HAAIZAAIJJg1oNACJAAAZAAIJJg1oNACJAAAuAAQKfx4AAhkACQnaEzkUAP0BABkACQnaEzkUAP0BAAAA.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgUJDAAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Galadan:BAAALgAECgUJCgABLgAECggJKgAYAFgJAA==.Gaskelmarg:BAAALgAECgQJBgAAAA==.',
Gh='Ghosty:BAABLgAECn8hAAQhAAkJIRXlHgDTAQAhAAkJsRHlHgDTAQAiAAcJpAuKTgD+AAAgAAEJcAEEmQAXAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAFFAMJBwANAPELAA==.',
Gi='Gigaweed:BAABLgAFFH8HAAINAAMJ8QuIQgCOAAANAAMJ8QuIQgCOAAAAAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtusk:BAABLgAECn8fAAIWAAgJWxYaDgDPAQAWAAgJWxYaDgDPAQAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAABLgAECn8mAAIIAAkJlReAJgBCAgAIAAkJlReAJgBCAgAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Grimsly:BAAALgAECgEJAQAAAA==.Grundler:BAAALgAFFAEJAQAAAA==.Gryphone:BAAALgADCgkJEAAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAgAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgAECgMJAwABLgAECggJLAACAM0bAA==.',
Ha='Hakmud:BAAALgADCgYJCwAAAA==.Halsin:BAAALgADCgMJAwABLgAECggJIAAjAEwYAA==.Hamshammy:BAAALgAECgEJAQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hela:BAAALgADCgcJBwAAAA==.Hercyderc:BAAALgAECgEJAQABLgAFFAIJBQAMADYgAA==.Hettokal:BAAALgAECgQJBAAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAABLgAECn8cAAIMAAkJchEdRAC3AQAMAAkJchEdRAC3AQAAAA==.Hondojoe:BAACLgAFFH8YAAIiAAQJvx6zDgBdAQAiAAQJvx6zDgBdAQAuAAQKfzcAAyIACQnuIEoLAJsCACIACQnuIEoLAJsCACEAAgnYBtRsAE0AAAAA.Honeydrake:BAAALgAECgYJCAAAAA==.Hopewell:BAABLgAECn8xAAIFAAgJAgYERQAqAQAFAAgJAgYERQAqAQAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAABLgAECn8sAAILAAgJvQoZEwAcAQALAAgJvQoZEwAcAQABLgAECggJMgARACcMAA==.Huhu:BAABLgAECn8ZAAIGAAkJrxSAKgCsAQAGAAkJrxSAKgCsAQAAAA==.Huma:BAAALgAECgYJEAABLgAFFAQJCgAUAAAOAA==.Hundreg:BAAALgADCgYJBQAAAA==.',
Ib='Ibn:BAABLgAECn8sAAIeAAkJBwt7HgBlAQAeAAkJBwt7HgBlAQAAAA==.',
Ic='Icyhot:BAAALgAECgEJAgAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
Il='Illaris:BAAALgADCgIJAgAAAA==.',
In='Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgAECgUJDAAAAA==.',
Is='Ishanllin:BAAALgAECgIJAgAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8iAAIMAAkJyRdGLgALAgAMAAkJyRdGLgALAgAAAA==.Ivylyn:BAAALgADCgkJDwAAAA==.',
Ix='Ixiyá:BAABLgAECn88AAMOAAkJNCNCBABxAwAOAAkJNCNCBABxAwAjAAEJzgiIqQAqAAAAAA==.Ixií:BAAALgAECgEJAgAAAA==.Ixì:BAABLgAECn8WAAIVAAcJ1x2aIQA4AgAVAAcJ1x2aIQA4AgAAAA==.',
Ja='Jakeyprogue:BAAALgAFFAIJAwABLgAFFAIJBgATAL4cAA==.Jakota:BAAALgADCgkJFAAAAA==.Jakskeleton:BAABLgAECn8fAAIPAAgJ2xrDDwANAgAPAAgJ2xrDDwANAgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jaynamir:BAAALgAECgYJEwAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgcJCgAAAA==.',
Jo='Joemacho:BAAALgAECgcJDQABLgAFFAQJGAAiAL8eAA==.Joshtee:BAAALgAECgMJBQAAAA==.Joslyn:BAAALgAECgQJBQAAAA==.Jourdan:BAAALgADCgcJDAAAAA==.',
Ju='Judax:BAACLgAFFH8GAAIjAAMJsQ67NQCwAAAjAAMJsQ67NQCwAAAuAAQKfz0AAiMACQm0G9ISAFUCACMACQm0G9ISAFUCAAAA.Justagirl:BAABLgAECn8yAAIRAAgJJwyYMgA2AQARAAgJJwyYMgA2AQAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.Juti:BAAALgAECgMJBgAAAA==.',
Jy='Jymion:BAAALgADCgEJAQAAAA==.',
Ka='Kadooka:BAABLgAECn8fAAIUAAgJFxf7TQC0AQAUAAgJFxf7TQC0AQAAAA==.Kahlyn:BAAALgAECgYJCwAAAA==.Kajax:BAABLgAECn8qAAIZAAgJISMwCAANAwAZAAgJISMwCAANAwAAAA==.Kaldaran:BAABLgAECn8UAAMPAAgJQhpaGwB/AQAPAAgJQhpaGwB/AQATAAIJtQSHTAFPAAAAAA==.Karen:BAAALgADCgcJGAAAAA==.Karne:BAAALgADCgYJBgAAAA==.Katira:BAAALgADCggJCAAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8cAAIPAAYJzxrvJQAhAQAPAAYJzxrvJQAhAQAAAA==.Keelay:BAABLgAECn9BAAIFAAkJQR4wCgDmAgAFAAkJQR4wCgDmAgAAAA==.',
Kh='Kheegorn:BAABLgAECn8bAAIBAAgJjRhqTwDzAQABAAgJjRhqTwDzAQAAAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwAQAAAAAA==.Kimiko:BAAALgAECgcJCwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgAZACEjAA==.',
Ko='Koffcmorbius:BAAALgAECgMJAwAAAA==.Koriban:BAABLgAECn8lAAIfAAkJaA4raACpAQAfAAkJaA4raACpAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECgkJJQAfAGgOAA==.',
Kr='Kra:BAAALgAECgEJAgABLgAFFAMJBwANAPELAA==.Kraken:BAACLgAFFH8FAAIHAAMJ0Q3ADADPAAAHAAMJ0Q3ADADPAAAuAAQKfysAAgcACQlzIucAAAYDAAcACQlzIucAAAYDAAEuAAUUAwkHAA0A8QsA.',
Ku='Kubb:BAABLgAECn8wAAIcAAgJiwU2HQANAQAcAAgJiwU2HQANAQAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAACLgAFFH8XAAIWAAYJlh+LAQDaAQAWAAYJlh+LAQDaAQAuAAQKfy0AAxYACQk6IxoFAMACABYACQk6IxoFAMACAB0ABQkbDqZFAPEAAAAA.',
['Kê']='Kêlsen:BAAALgAECgUJBwAAAA==.',
La='Lachupacabra:BAAALgAECgEJAQAAAA==.Larrissa:BAABLgAECn8mAAMJAAgJzgZPEwAzAQAJAAgJzgZPEwAzAQAHAAEJggPhewAlAAAAAA==.Larry:BAABLgAFFH8RAAIMAAUJ0RbVOwAvAQAMAAUJ0RbVOwAvAQAAAA==.Laurlynn:BAAALgAECgUJCwAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lenwe:BAAALgAECgYJCgABLgAECgcJLQAiAGwOAA==.Lettuceprey:BAABLgAECn8qAAIiAAgJNBA3KgBxAQAiAAgJNBA3KgBxAQAAAA==.',
Li='Lierise:BAAALgAECgUJDAAAAA==.Lies:BAAALgADCgkJCQAAAA==.Lightsnipe:BAAALgAECgQJBAAAAA==.Lilkelp:BAAALgAECgYJBwAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.Lithiri:BAAALgAECgUJBgABLgAECggJHQATAK0fAA==.',
Lo='Lockatute:BAAALgAECggJDgAAAA==.Lockdeath:BAAALgAECgQJCQAAAA==.Loric:BAAALgADCgkJCQAAAA==.Loxia:BAAALgAECggJEwAAAA==.',
Lu='Lucille:BAABLgAECn8aAAIfAAgJOwyXfwB1AQAfAAgJOwyXfwB1AQAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAABLgAECn8gAAMWAAgJNBqUCgASAgAWAAgJNBqUCgASAgAVAAEJGwZI5gAjAAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Madischa:BAAALgAECgcJCQAAAA==.Magicdance:BAACLgAFFH8JAAIjAAQJxQJ8NgCtAAAjAAQJxQJ8NgCtAAAuAAQKfzIAAw4ACQkoEQJKAIMBAA4ACAl7EQJKAIMBACMACQnSCX4/ADIBAAAA.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIWAAgJchK/CwACAgAWAAgJchK/CwACAgAAAA==.Majicbob:BAABLgAECn8gAAIjAAgJTBimHQDxAQAjAAgJTBimHQDxAQAAAA==.Maki:BAAALgAECggJEwAAAA==.Mansion:BAAALgADCgQJBgABLgAECgcJGwAMAGseAA==.Marilune:BAAALgADCggJCQAAAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgAECgEJAQAAAA==.',
Mc='Mctowlie:BAAALgAECgYJBwAAAA==.',
Me='Mehänemäntä:BAAALgAECgcJDgAAAA==.Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAABLgAECn8aAAMYAAcJqBVaEwBBAQATAAYJJRKQlABXAQAYAAUJWBVaEwBBAQAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mf='Mfdkidney:BAAALgAECgIJAgAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAFFAQJCQAjAMUCAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAACLgAFFH8QAAIRAAQJUyRDCACOAQARAAQJUyRDCACOAQAuAAQKfzwAAhEACQkYJowBAF8DABEACQkYJowBAF8DAAAA.Misstreater:BAABLgAECn8fAAMkAAgJdgbrCQDpAAAfAAcJZAVaywD1AAAkAAcJyQbrCQDpAAAAAA==.',
Mo='Momentomori:BAABLgAECn8gAAIIAAkJvghGbQBgAQAIAAkJvghGbQBgAQAAAA==.Monbow:BAAALgAECgMJBwABLgAECggJGgAMAIgUAA==.Monocerotis:BAAALgAECgQJBAAAAA==.Morishima:BAACLgAFFH8XAAIZAAQJ6xmIFQBZAQAZAAQJ6xmIFQBZAQAuAAQKf0UAAxkACQkHJNwCACQDABkACQkHJNwCACQDACUAAQkJFkIlAD0AAAAA.Morthis:BAABLgAECn8qAAMXAAgJvgr/EgAqAQAXAAgJvgr/EgAqAQADAAMJWgMjVwBMAAAAAA==.',
Mu='Multipàss:BAAALgADCgcJCgAAAA==.',
My='Mydarling:BAAALgAFFAIJAwAAAA==.Mymoon:BAAALgAECgIJAgAAAA==.Myris:BAACLgAFFH8FAAITAAMJtw/AogDQAAATAAMJtw/AogDQAAAuAAQKfysAAhMACQlSG6omAGYCABMACQlSG6omAGYCAAAA.',
Na='Narcan:BAAALgAECgQJCAAAAA==.Naturalchi:BAABLgAECn8wAAMRAAkJByV5AgBDAwARAAkJiiR5AgBDAwAmAAgJ8x5LDABvAgAAAA==.',
Nb='Nbi:BAAALgAECgEJAQAAAA==.',
Ne='Nefilion:BAABLgAFFH8GAAITAAIJ7wuM4QCDAAATAAIJ7wuM4QCDAAAAAA==.Nemas:BAABLgAECn8hAAICAAgJrxmlDgDVAQACAAgJrxmlDgDVAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAABLgAECn8lAAQnAAcJ6BQHDwAWAQAaAAcJJhKSNQBYAQAnAAYJJRMHDwAWAQAbAAIJuQ2jQABlAAAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nightrunnêr:BAAALgAECgQJBwABLgAECggJLAACAM0bAA==.Nineadin:BAACLgAFFH8PAAMBAAQJnwsEVQAAAQABAAQJnwsEVQAAAQAFAAMJ2RZtLwCzAAAuAAQKfycAAwUACQmYHU0TAHgCAAUACQmYHU0TAHgCAAEAAgkjHQUFAa4AAAAA.Nineshots:BAAALgAFFAMJBAABLgAFFAQJDwABAJ8LAA==.Ninetoads:BAAALgAECgcJDQABLgAFFAQJDwABAJ8LAA==.Nirvanas:BAABLgAECn8cAAIWAAgJngvzHAAdAQAWAAgJngvzHAAdAQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8tAAMiAAcJbA6nNgAgAQAiAAcJbA6nNgAgAQAgAAYJ1QfaYQCOAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.North:BAAALgAECggJCAAAAA==.',
Nu='Nuke:BAAALgAECgQJEgAAAA==.Nullspace:BAABLgAECn8mAAIiAAkJXhpqFAAwAgAiAAkJXhpqFAAwAgAAAA==.Nunskee:BAAALgAECgQJBAAAAA==.',
['Ní']='Níght:BAABLgAECn85AAIEAAgJKRfMFACpAQAEAAgJKRfMFACpAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCgAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Oh='Ohhk:BAAALgAECgMJAwAAAA==.',
Om='Ommû:BAAALgAECgMJCAAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAFFAMJBwANAPELAA==.',
Pa='Pakeydk:BAABLgAFFH8GAAITAAIJvhyIvwCjAAATAAIJvhyIvwCjAAAAAA==.Palacia:BAAALgAECggJDgAAAA==.Pancakedealr:BAAALgAECgUJEAAAAA==.Pancakeeater:BAAALgAECgUJCgAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Petrichorica:BAAALgAECgcJEQAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAABLgAECn8XAAIUAAkJlQUFdQBRAQAUAAkJlQUFdQBRAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJBQAAAA==.',
Pr='Preachêr:BAAALgAECgQJCAABLgAECggJLAACAM0bAA==.Prohteus:BAAALgAECgEJAQABLgAECgMJBQAQAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8eAAIiAAcJtA7RNQAlAQAiAAcJtA7RNQAlAQAAAA==.',
Qu='Quan:BAEALgADCgcJCQABLgADCgkJKAAQAAAAAA==.Quelaag:BAAALgADCgQJBAAAAA==.Quenthel:BAAALgAECgkJAgAAAA==.Quiescent:BAABLgAECn8pAAIMAAgJdRpUKQAhAgAMAAgJdRpUKQAhAgAAAA==.Quina:BAAALgADCgUJBQAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAABLgAECn8qAAMJAAgJkCWqAQDXAgAJAAgJkCWqAQDXAgAIAAEJAxF2NwE1AAABLgAFFAYJFQALAGkkAA==.Ramanas:BAABLgAECn8XAAMgAAgJdA51NQA/AQAgAAcJhA91NQA/AQAhAAYJnBGILQAxAQAAAA==.Ramrod:BAAALgAECgIJAwAAAA==.Randomizwe:BAABLgAECn8uAAIBAAkJtB6eIgB5AgABAAkJtB6eIgB5AgAAAA==.Raspet:BAAALgADCgIJAgAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAABLgAECn8tAAIIAAkJJg1wUACpAQAIAAkJJg1wUACpAQAAAA==.Relyn:BAAALgAECggJDwAAAA==.Resurgencê:BAABLgAECn8sAAICAAgJzRtCCgAkAgACAAgJzRtCCgAkAgAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAABLgAECn8kAAMBAAgJ6BSTjgBSAQABAAcJChSTjgBSAQACAAQJ9xNWJQDnAAAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgcJGwAMAGseAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJEwAAAA==.Rotandroll:BAAALgAECgcJDwAAAA==.Rothema:BAABLgAECn8cAAMjAAgJJAn8VgDbAAAjAAcJ9Af8VgDbAAAOAAcJdANxkQCvAAAAAA==.Routh:BAAALgAECgEJAQAAAA==.',
Rw='Rwlmaster:BAABLgAECn85AAIPAAgJsBpnDwASAgAPAAgJsBpnDwASAgAAAA==.',
Ry='Rynzia:BAACLgAFFH8ZAAMnAAQJMhnyAwAvAQAaAAQJMhnHJQAzAQAnAAQJMxPyAwAvAQAuAAQKf0YABCcACQngIaUBANECACcACQktH6UBANECABoACQnJIDwMAJYCABsABwnnEo4SAJwBAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgcJDQAAAA==.Santose:BAAALgAECgIJAgAAAA==.Sarya:BAAALgAECgQJBAABLgAECgkJAgAQAAAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAABLgAECn8mAAITAAkJExBnTADaAQATAAkJExBnTADaAQAAAA==.Schmerz:BAAALgADCgUJBQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgkJRQADAN0fAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgcJDgAAAA==.Seta:BAABLgAECn8bAAIMAAgJ3xNeQwDmAQAMAAgJ3xNeQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJBgATAL4cAA==.Shamarha:BAABLgAECn8cAAIOAAgJaBokMgDnAQAOAAgJaBokMgDnAQAAAA==.Shaolin:BAAALgAECgQJBAAAAA==.Sharriavolf:BAABLgAECn9CAAQIAAgJwSOtPwDdAQAIAAYJmiGtPwDdAQAHAAQJ+CMLIABSAQAJAAEJAAB7IwBkAAAAAA==.Shato:BAAALgAECgYJCQAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shiori:BAAALgAECgcJEAAAAA==.Shortmedic:BAAALgAECgQJBAAAAA==.Shotzys:BAAALgAECgUJDQAAAA==.Shrieve:BAAALgAECgMJAwAAAA==.Shurg:BAAALgAECgQJBAAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAAQAAAAAA==.Siggismund:BAABLgAECn8rAAIBAAkJKgvPdQCAAQABAAkJKgvPdQCAAQAAAA==.Simichaelton:BAACLgAFFH8MAAIfAAUJCBAlXgAvAQAfAAUJCBAlXgAvAQAuAAQKfxoAAh8ACQnDFAtIAAACAB8ACQnDFAtIAAACAAAA.Sinpal:BAABLgAFFH8IAAIBAAMJTxnLXQDtAAABAAMJTxnLXQDtAAABLgAFFAQJCgAIABIcAA==.Sinthea:BAAALgAECgkJAQAAAA==.Sioce:BAAALgADCgkJIgAAAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slickacitic:BAAALgAECgYJBwABLgAECgcJHwAOAAwLAA==.Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgAECgcJCAAAAA==.',
Sm='Smorroy:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8eAAIBAAgJ/BxdSQAGAgABAAgJ/BxdSQAGAgAAAA==.Sophrosyne:BAABLgAECn8qAAIUAAgJcBqWLgAeAgAUAAgJcBqWLgAeAgAAAA==.Souless:BAAALgAECgYJBgAAAA==.',
Sp='Sparkness:BAAALgAECgMJAwAAAA==.Spartaaxd:BAABLgAECn8oAAIYAAkJkRDJDgCFAQAYAAkJkRDJDgCFAQAAAA==.Spookems:BAAALgAECgIJAgABLgAFFAIJAgAQAAAAAA==.Spycy:BAABLgAECn8UAAIfAAkJ3BAvgwBuAQAfAAkJ3BAvgwBuAQAAAA==.',
St='Stagerrind:BAAALgAECgQJCAAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8qAAMFAAkJOwzgMwCBAQAFAAkJOwzgMwCBAQABAAEJ9Qf5rgEnAAAAAA==.Stinkyfrog:BAACLgAFFH8GAAIBAAMJxQyWggClAAABAAMJxQyWggClAAAuAAQKfyMAAgEACQk+IogLAAcDAAEACQk+IogLAAcDAAAA.Stovetop:BAAALgAECgEJAQABLgAECgUJBwAQAAAAAA==.Stubmcbean:BAAALgADCggJCQABLgAECggJMAAcAIsFAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8mAAIfAAkJOgs6ogA0AQAfAAkJOgs6ogA0AQAAAA==.Suka:BAAALgAECgUJCwAAAA==.Surok:BAAALgAECgYJDwAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgcJDAAAAA==.',
Sy='Sylentcurse:BAABLgAECn8hAAIJAAgJDQs1EQBLAQAJAAgJDQs1EQBLAQABLgAECgkJKAAUABYSAA==.Sylentstorm:BAABLgAECn8YAAMOAAcJXwOagQDXAAAOAAcJXwOagQDXAAAjAAEJAADCxAAAAAABLgAECgkJKAAUABYSAA==.Syleta:BAABLgAECn9FAAQDAAkJ3R+zBQDJAgADAAgJEB+zBQDJAgAUAAcJwxwNMADwAQAXAAYJCRNpRABEAQAAAA==.',
Ta='Tabraxis:BAAALgAECgEJAQAAAA==.Tagalorc:BAABLgAECn8fAAMkAAkJPRU1AwD3AQAkAAkJPRU1AwD3AQAfAAEJ8QFQfAEcAAAAAA==.Takamaki:BAAALgAECgEJAwAAAA==.Tanksbacon:BAABLgAECn8kAAMBAAkJTBk2MgA1AgABAAkJTBk2MgA1AgACAAQJtxKSLwCWAAAAAA==.Taylith:BAAALgAECgYJEgAAAA==.',
Te='Teana:BAABLgAECn8iAAIYAAgJ5A/hDwB0AQAYAAgJ5A/hDwB0AQAAAA==.Teannev:BAAALgADCgYJBgAAAA==.Tempestas:BAAALgAECgEJAQAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAFFAQJDwAVAKEWAA==.Thechadd:BAABLgAFFH8HAAIjAAcJaAMENgCvAAAjAAcJaAMENgCvAAAAAA==.Thelegendáry:BAACLgAFFH8NAAIOAAQJbhAZOgDzAAAOAAQJbhAZOgDzAAAuAAQKfxoAAg4ABgmWF0FKAFkBAA4ABgmWF0FKAFkBAAAA.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgYJCwAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAABLgAECn83AAMdAAkJuRu9EgA9AgAdAAgJtxy9EgA9AgAVAAkJFQuSUwA/AQAAAA==.Tireck:BAAALgADCgIJAgAAAA==.',
To='Toriee:BAAALgAECgkJCQAAAA==.Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAABLgAECn8gAAIjAAkJZAnEOwBDAQAjAAkJZAnEOwBDAQAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Tremor:BAAALgADCgIJAgAAAA==.Trisstan:BAABLgAECn8qAAMfAAgJngk3kABUAQAfAAgJngk3kABUAQAoAAMJawEvDQBVAAAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.Tundie:BAAALgAFFAEJAQAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8iAAMfAAkJshsZOwAqAgAfAAkJkBgZOwAqAgAkAAUJHyAJBgDAAQAAAA==.Tyster:BAACLgAFFH8NAAIBAAQJqhMHOwAwAQABAAQJqhMHOwAwAQAuAAQKfyMAAwEACQl0FRFDAPoBAAEACQnGFBFDAPoBAAIAAQkbFuBIAEEAAAAA.',
['Tø']='Tørmëntëd:BAAALgAECgMJBAAAAA==.',
Ug='Ugotdusted:BAAALgADCgYJBgAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgIJAgAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJGwABLgAECggJMAAcAIsFAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECgkJJAAmAFkaAA==.',
Uz='Uzu:BAABLgAECn8kAAMmAAkJWRomJQCBAQAmAAkJWRomJQCBAQARAAEJyhJIiwBDAAAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Valorr:BAAALgAECgQJBAAAAA==.Vamp:BAABLgAECn8YAAIOAAgJxxbxLwDIAQAOAAgJxxbxLwDIAQAAAA==.Vandaldor:BAAALgAECgYJEQAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8aAAIfAAQJYhmtTgBIAQAfAAQJYhmtTgBIAQAuAAQKfy4AAh8ACQlDImohAJYCAB8ACQlDImohAJYCAAAA.Vexnyx:BAAALgADCgcJCAAAAA==.',
Vh='Vhitahni:BAAALgAECgMJAwAAAA==.',
Vi='Viggle:BAAALgADCggJCAABLgAECggJLAACAM0bAA==.Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8nAAMUAAkJtRvzJwA7AgAUAAkJtRvzJwA7AgADAAIJewTpKgBVAAAAAA==.',
Vo='Voodoomike:BAAALgAECgIJAgAAAA==.',
Vy='Vynlorin:BAAALgAECgYJBgABLgAECgkJMgABAFQgAA==.',
Wa='Wanawa:BAAALgAECgMJAwABLgAECggJHwAWAFsWAA==.Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECggJHwAWAFsWAA==.Warthog:BAAALgADCggJEQAAAA==.Waterbender:BAABLgAECn8ZAAIOAAkJRRoEGQB/AgAOAAkJRRoEGQB/AgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wifeotusk:BAAALgAECggJDQAAAA==.Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAABLgAECn8hAAIBAAgJ2hYoTwDYAQABAAgJ2hYoTwDYAQAAAA==.Wilshaman:BAAALgAECgUJBgAAAA==.Window:BAAALgADCgUJBQABLgAECgcJGwAMAGseAA==.',
Wm='Wmdplague:BAAALgADCgYJBgAAAA==.',
Wo='Wolf:BAABLgAECn8oAAIEAAkJNhfCEgDAAQAEAAkJNhfCEgDAAQAAAA==.Wolfton:BAAALgAECgMJAwAAAA==.Woodtique:BAAALgAECgMJBgAAAA==.',
Wr='Wrekkit:BAAALgAECggJDQAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMUAAgJIhvAHQBTAgAUAAgJIhvAHQBTAgAXAAMJrAJgdABtAAAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAABLgAECn8eAAIWAAgJuRr4CgAJAgAWAAgJuRr4CgAJAgAAAA==.',
Xy='Xyro:BAAALgAECgUJBQABLgAECggJGwABAI0YAA==.',
Ya='Yamato:BAAALgAECgcJDQAAAA==.',
Za='Zaledron:BAABLgAECn8dAAITAAgJrR8ENQAoAgATAAgJrR8ENQAoAgAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAABLgAECn8mAAMcAAgJ7xNIEACqAQAcAAgJ7xNIEACqAQAOAAMJVggyswBeAAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8bAAMTAAUJXB1TQABvAQATAAUJXB1TQABvAQAYAAMJhxRQEwDqAAAuAAQKf0YAAxMACQmiJUYHADsDABMACQmiJUYHADsDABgACAlQIeMDAJkCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAAQAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.Zomby:BAABLgAFFH8FAAITAAMJEA5UowDPAAATAAMJEA5UowDPAAABLgAFFAUJDAAfAAgQAA==.',
Zp='Zpersephone:BAABLgAECn8VAAIIAAcJRxFndQBOAQAIAAcJRxFndQBOAQABLgAFFAUJGwATAFwdAA==.',
Zr='Zrii:BAAALgAECgcJCQAAAA==.',
Zu='Zultan:BAACLgAFFH8RAAIIAAQJaweKZgDzAAAIAAQJaweKZgDzAAAuAAQKfzoAAwgACQkCGW4fAGYCAAgACQkCGW4fAGYCAAcAAglmBL5GABkAAAAA.Zurrik:BAACLgAFFH8LAAMdAAQJTwanLwC+AAAdAAQJEgSnLwC+AAAEAAMJYQa9JwB2AAAuAAQKfz4AAx0ACQm0EgggAMQBAB0ACQnwEQggAMQBAAQAAgn+E0RLAHcAAAAA.',
Zy='Zynofhealth:BAAALgADCgUJAwAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8GAAImAAMJqBTYEgDjAAAmAAMJqBTYEgDjAAAuAAQKfycAAyYACAmEHzsJAPUCACYACAmEHzsJAPUCABEAAwkjGQ+WADYAAAAA.',
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
