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

local lookup = {'Mage-Arcane','Mage-Frost','Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Restoration','Priest-Discipline','Druid-Guardian','Rogue-Subtlety','Hunter-BeastMastery','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','DemonHunter-Devourer','Shaman-Elemental','Warlock-Destruction','Shaman-Enhancement','Hunter-Survival','Rogue-Outlaw','DeathKnight-Blood','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Monk-Windwalker','Rogue-Assassination','Warrior-Arms','DeathKnight-Unholy','Monk-Brewmaster','DemonHunter-Havoc','Monk-Mistweaver','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aalicya:BAAANQAECgYIBwAAAA==.',
Ac='Acegoblain:BAACNQAFFH8GAAMBAAYKngcsHwACAQABAAUK1AYsHwACAQACAAEKyAqLEgBOAAA1AAQKfyIAAwIACgpVIO4GAFQCAAIABgo8Ie4GAFQCAAEACgqyFiGVAHsBAAE1AAUUBQgQAAMAFw8A.',
Ad='Adind:BAABNQAECn9iAAIEAAoKKiMAAwDbAwAEAAoKKiMAAwDbAwAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQAECgYIBgAAAA==.Aeropally:BAAANQAECgEIAQABNQAECgYIBgAFAAAAAA==.Aerorising:BAAANQADCgYIBgABNQAECgYIBgAFAAAAAA==.Aeroshaman:BAAANQADCggICAABNQAECgYIBgAFAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgcIEgAAAA==.',
Al='Alaval:BAABNQAECn8XAAMGAAkKCwr7lABWAQAGAAkKCwr7lABWAQAHAAYKHAWATQDeAAAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgIIAwABNQAECggIAgAFAAAAAA==.Alestalker:BAAANQADCgUIBQABNQAECgUIBQAFAAAAAA==.Aletheïa:BAAANQAECgEIAQAAAA==.Aliggan:BAAANQABCgUIBwAAAA==.Allthesmokee:BAAANQADCgYIBgAAAA==.Althamon:BAAANQAECgUICQAAAA==.',
An='Andromalius:BAAANQADCgUIBQAAAA==.Antamun:BAABNQAECn9GAAIIAAoK+RlSBwBAAgAIAAoK+RlSBwBAAgAAAA==.',
Ao='Aoasis:BAABNQAECn8jAAIJAAoKkBaRSQDtAQAJAAoKkBaRSQDtAQAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgkJFwAGAAsKAA==.',
Ar='Araethea:BAACNQAFFH8JAAIGAAUK9iEZDQDYAQAGAAUK9iEZDQDYAQA1AAQKfzQAAwoACgpYJesCANgCAAYACQpDJUsXABwDAAoACAr1H+sCANgCAAAA.Arasettey:BAAANQADCggICAABNQAFFAYICgALALkZAA==.Arethusa:BAAANQADCggIEAAAAA==.Arislynn:BAABNQAECn8vAAIMAAkKcQvyJwCGAQAMAAkKcQvyJwCGAQAAAA==.Arlilea:BAEANQAECgIIAwABNQAECgkJHgANAOQEAA==.Aryn:BAABNQAECn8gAAMHAAoKOBDvMACcAQAHAAkKZQ/vMACcAQAGAAQKrAQa3ACUAAAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgcIDQAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECn8rAAIOAAoKESH4GAAVAwAOAAoKESH4GAAVAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgYIDAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgUIBgAAAA==.Baromir:BAAANQADCgYIBgAAAA==.Bathin:BAABNQAECn8uAAMPAAoK0BNNBQByAgAPAAkKExVNBQByAgAQAAQKJQvVxQDFAAAAAA==.Bathwater:BAABNQAECn83AAIJAAoKfCP2DABYAwAJAAoKfCP2DABYAwAAAA==.',
Be='Bearbottom:BAAANQAECggICgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECn8oAAIRAAoKaBHemQDvAQARAAoKaBHemQDvAQAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBQABNQAECgcICgAFAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggICAAFAAAAAA==.Bigtriangle:BAABNQAECn8eAAISAAkK8h1XDwA1AgASAAkK8h1XDwA1AgABNQAFFAYICgALALkZAA==.Billiamson:BAABNQAECn8UAAISAAgKHBZCEwDxAQASAAgKHBZCEwDxAQAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECn8pAAITAAoKTxjTKgBFAgATAAoKTxjTKgBFAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcIBgAAAA==.Bloodaxe:BAAANQAECggIDgAAAA==.',
Bo='Booddha:BAAANQADCggIEAAAAA==.Bornferal:BAAANQAECggIDAAAAA==.Botasamigo:BAAANQAECgQICgAAAA==.',
Br='Brandagh:BAAANQAECggICwABNQAFFAUICQAGAPYhAA==.Breadglaive:BAABNQAECn8WAAIUAAoK8x54CgCsAgAUAAoK8x54CgCsAgAAAA==.Breezy:BAAANQAECggIAgAAAA==.Bryzx:BAACNQAFFH8VAAIJAAgKaRrzAgBqAgAJAAgKaRrzAgBqAgA1AAQKfykAAwkACgrDIs8PAEUDAAkACgrDIs8PAEUDABUAAQqtDsX3ADoAAAAA.Bryzxbless:BAAANQAECgQIAwABNQAECgcICgAFAAAAAA==.',
Bu='Bubblebee:BAABNQAECn83AAINAAoK+hfiPwBWAgANAAoK+hfiPwBWAgAAAA==.Bullan:BAAANQADCggICQAAAA==.Bun:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAABNQAECn8sAAIUAAkKgQShMwD8AAAUAAkKgQShMwD8AAAAAA==.',
Ca='Cakestripper:BAABNQAECn8aAAINAAUKNg9b2AACAQANAAUKNg9b2AACAQAAAA==.Caripaige:BAAANQAECgYICgAAAA==.Cavetard:BAAANQADCgYICgAAAA==.',
Ce='Celticdreams:BAAANQAECgYICAAAAA==.Ceravolo:BAAANQAECgEIAQAAAA==.',
Ch='Charmeine:BAAANQABCgQIBAABNQAECgoKKwAOABEhAA==.',
Cl='Clairvoyance:BAAANQAECgQIBAABNQAECgkJMAARAEgRAA==.Clêver:BAAANQADCgYIBgABNQAECggIGwABALgdAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAACNQAFFH8JAAIRAAUKrxS3FADhAAARAAUKrxS3FADhAAA1AAQKf0cAAhEACgquIbUgAEEDABEACgquIbUgAEEDAAAA.',
Cu='Cubouros:BAAANQADCggICAABNQAECgoKKwAOABEhAA==.',
Cy='Cynemon:BAABNQAECn8uAAIKAAgKnxTWBADgAQAKAAgKnxTWBADgAQAAAA==.Cynleel:BAAANQAECgUIBgABNQAECggILgAKAJ8UAA==.',
Da='Dadu:BAAANQADCgEIAQAAAA==.Daftmonk:BAAANQADCgYIBgAAAA==.Daifuku:BAABNQAECn9JAAITAAoKOiIoCgBKAwATAAoKOiIoCgBKAwAAAA==.Dakyaa:BAAANQADCgMIAwAAAA==.Darknonsence:BAAANQAECgMIBAAAAA==.',
De='Demonetizeme:BAABNQAECn80AAMPAAgK+w+PCgDMAQAPAAgK+w+PCgDMAQAWAAIKMgh3XwBmAAABNQAECgkJFwAGAAsKAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwAFAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgQIDQAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQAECgUIBQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgcIGwAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQICwAAAA==.',
['Då']='Dåmage:BAABNQAECn8lAAIRAAYKBQkIHQHuAAARAAYKBQkIHQHuAAAAAA==.',
Ed='Edric:BAABNQAECn8eAAMXAAgKCxglFwCiAQAXAAgKCxglFwCiAQAJAAQK6hMhvAChAAAAAA==.Edyion:BAABNQAECn8uAAIYAAkKNQb6CABgAQAYAAkKNQb6CABgAQAAAA==.',
Ef='Efreet:BAABNQAECn8uAAMNAAoKEyMUKwDtAgANAAoKEyMUKwDtAgADAAYKABclPQBoAQAAAA==.',
El='Elimae:BAEANQADCgYICAAAAA==.',
En='Enochian:BAAANQADCgUIBwAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAABNQAECn8YAAINAAoKOgrUgAC4AQANAAoKOgrUgAC4AQAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggICAAFAAAAAA==.Evoda:BAABNQAECn8aAAIZAAcKoQiMBgDjAAAZAAcKoQiMBgDjAAAAAA==.',
Ex='Extrodinaire:BAABNQAECn8qAAIXAAoKgBbYEgA8AgAXAAoKgBbYEgA8AgAAAA==.',
Ez='Eziopandator:BAAANQABCggILwAAAA==.',
Fa='Fabiio:BAAANQAECgMIAgABNQAECggIAgAFAAAAAA==.Fadedemon:BAABNQAECn8vAAIUAAoKrBVjHQBoAgAUAAoKrBVjHQBoAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Falkör:BAAANQAECgIIAwAAAA==.Farrahmoans:BAABNQAECn89AAMCAAkKHSEPBwCFAgACAAkKHSEPBwCFAgABAAgKjxTJegC3AQAAAA==.',
Fe='Fellvarg:BAABNQAECn8dAAMTAAcK6gxHXgAtAQATAAcK6gxHXgAtAQAaAAIKnAKyxAA/AAAAAA==.Felsgoodman:BAABNQAECn9JAAMWAAoKEyHsBADTAgAWAAgKmyDsBADTAgAQAAkKNh0kHQCiAgAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQAECgEIAQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgYICQAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgUIBwABNQAECgoKNQARAMMRAA==.',
Fo='Fotiá:BAABNQAECn8oAAIbAAoKTyEXBQAOAwAbAAoKTyEXBQAOAwABNQAFFAcIFQANALkcAA==.',
Fu='Fulgur:BAAANQAECggIEAAAAA==.Fumistra:BAAANQADCggIDgAAAA==.Furyalast:BAAANQADCggICAABNQAECgYIEwAFAAAAAA==.',
Ga='Gahïjï:BAAANQAECgQICgABNQAECgoKIwAJAJAWAA==.Galroot:BAAANQAECgcICwABNQAFFAUIEAADABcPAA==.Galsnipes:BAACNQAFFH8QAAMDAAUKFw9SDgBYAQADAAUKcA5SDgBYAQANAAEKxgzjNwBLAAA1AAQKfzsAAwMACQoqHYoYAJMCAAMACQoqHYoYAJMCAA0AAQpTDfhRAUAAAAAA.Galvakrond:BAABNQAECn8nAAIcAAkKvwwzDQB7AQAcAAkKvwwzDQB7AQAAAA==.',
Ge='Gearno:BAAANQAECgEIAQAAAA==.Geearr:BAAANQAECgUICgAAAA==.',
Gl='Glitterturds:BAAANQADCgMIAwAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAFFAEIAQABNQAFFAYICgALALkZAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAABNQAECn8tAAMRAAgKoRZgmADzAQARAAgKoRZgmADzAQAOAAYKbAuHkAAIAQAAAA==.',
Gr='Grak:BAABNQAECn8hAAIdAAgK6xD9HAD8AQAdAAgK6xD9HAD8AQABNQAFFAYICgAGAEYFAA==.Gratescott:BAABNQAECn8qAAINAAoKiRKeZwD1AQANAAoKiRKeZwD1AQAAAA==.Grateshot:BAABNQAECn8ZAAINAAcKcBEQqwBcAQANAAcKcBEQqwBcAQAAAA==.Grik:BAAANQAECgUIEQAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAABNQAECn8oAAIGAAcK4BTwdQB5AQAGAAcK4BTwdQB5AQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAABNQAECn8dAAIGAAkKHBxuMQB9AgAGAAkKHBxuMQB9AgAAAA==.Hellenita:BAAANQAECgcICwAAAA==.',
Hi='Hildebrand:BAAANQADCgcIBgAAAA==.Hitomitanaka:BAABNQAECn8oAAMEAAoKChI+HwAFAgAEAAoKChI+HwAFAgAeAAEKAABuTwAWAAAAAA==.',
Ho='Holyoshyy:BAABNQAECn84AAIRAAoK5CENJgDJAgARAAoK5CENJgDJAgAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgYIEwAAAA==.',
Hu='Hup:BAAANQAECgEIAQAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAABNQAECn8ZAAIVAAkKQgpEeQAhAQAVAAkKQgpEeQAhAQAAAA==.',
In='Inarin:BAAANQADCgcIGwAAAA==.',
Ir='Ironmaged:BAAANQAECgEIAQABNQAECgoKOQAfABoeAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgYICwAFAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAABNQAECn9IAAIgAAoK2RkpCABsAgAgAAoK2RkpCABsAgAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgYICQAAAA==.Jamezon:BAABNQAECn8YAAIIAAoKkhK/DADuAQAIAAoKkhK/DADuAQAAAA==.',
Je='Jebraxis:BAABNQAECn8mAAMhAAkKoxi/UAAMAgAhAAkKoxi/UAAMAgAIAAEKAADYNgArAAAAAA==.Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAABNQAECn8yAAIXAAkKDxEuFADUAQAXAAkKDxEuFADUAQAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAAAAA==.Johnzanpally:BAAANQAECgcIBwAAAA==.Joonbug:BAAANQABCgQIBwAAAA==.',
Ju='Juràssic:BAABNQAECn8fAAMLAAoKvxONIgBuAQALAAoKvxONIgBuAQAeAAQKIw0TMQCOAAAAAA==.',
Ka='Kaeul:BAABNQAECn8ZAAIJAAgKvCWiDgBNAwAJAAgKvCWiDgBNAwAAAA==.Kahrot:BAABNQAECn8hAAIiAAoKliVlAwC+AwAiAAoKliVlAwC+AwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAABNQAECn8yAAIbAAkKygotKgAjAQAbAAkKygotKgAjAQAAAA==.Kando:BAAANQADCgQIBAAAAA==.Kazgrom:BAAANQAECgUICQAAAA==.Kazool:BAAANQAECgUIBwAAAA==.',
Ke='Keanuleaves:BAAANQAECgQIBQABNQAECgkJPQACAB0hAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAYICgALALkZAA==.Killerheal:BAACNQAFFH8KAAILAAYKuRn3AAACAgALAAYKuRn3AAACAgA1AAQKfyQAAgsACgoWIzAFAAkDAAsACgoWIzAFAAkDAAAA.Kiralan:BAAANQADCgcICQAAAA==.Kizzu:BAABNQAECn9EAAMTAAoKYh2tGwBsAgAiAAgKaRywKwCGAgATAAoKhRytGwBsAgAAAA==.',
Kl='Klawdius:BAAANQADCgcICAAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECggIEQAAAA==.Koufeb:BAAANQADCgIIAgABNQAECgoKNQARAMMRAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgYICQAAAA==.',
['Kø']='Køteb:BAABNQAECn8wAAMaAAoK8hjmHQDCAgAaAAoK8hjmHQDCAgATAAMKzAOtkwBuAAAAAA==.',
Le='Leadshot:BAABNQAECn8gAAINAAQKEhEj/QAKAQANAAQKEhEj/QAKAQAAAA==.Leves:BAAANQAECgEIAQABNQAECgcICgAFAAAAAA==.',
Lo='Lochlynn:BAAANQADCggICAAAAA==.',
Lu='Luigimangion:BAAANQAECgUICAAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQAECgUIEQAAAA==.',
Ma='Maakha:BAABNQAECn8yAAIIAAkKSwqTEgBOAQAIAAkKSwqTEgBOAQAAAA==.Mabalzich:BAAANQADCgcIGwAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAABNQAECn8XAAMfAAgKvA+XKwC/AQAfAAgKvA+XKwC/AQAjAAEKAABmLgBKAAABNQAECgoKNQARAMMRAA==.Magicmack:BAAANQAECggICwAAAA==.Magroot:BAABNQAECn8oAAIMAAoKQBsJDQCkAgAMAAoKQBsJDQCkAgAAAA==.Maitake:BAAANQAECgYIBgAAAA==.Makula:BAABNQAECn8qAAMUAAkKGw+SIQCSAQAUAAkKGw+SIQCSAQAkAAEKAABFnQAAAAAAAA==.Mana:BAAANQAECggIDwAAAA==.Manabun:BAABNQAECn8bAAIaAAoKBhAyLgCZAQAaAAoKBhAyLgCZAQAAAA==.Manacakes:BAAANQAECgUICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECn8cAAIGAAkKmhgnNACXAgAGAAkKmhgnNACXAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAGAJoYAA==.Mapera:BAABNQAECn8yAAIlAAkKtR7WCQCzAgAlAAkKtR7WCQCzAgAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maraxx:BAABNQAECn8kAAMWAAkKaQzZDADyAAAQAAkKuAr0ZACnAQAWAAcK3QnZDADyAAAAAA==.Maray:BAAANQAECgUICgAAAA==.Marjaya:BAABNQAECn8YAAICAAgK4A+pEgBjAQACAAgK4A+pEgBjAQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQAECgcIDgAAAA==.Meloncauley:BAABNQAECn8fAAMaAAcKhxHyWACPAQAaAAcKhxHyWACPAQATAAMKRwWblwBlAAAAAA==.Merjaya:BAAANQABCgIIAgAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Milkncookies:BAAANQAECggIAgAAAA==.Mirisa:BAAANQAECgQIBAAAAA==.Mirosa:BAABNQAECn8yAAICAAkK/gs0EQB7AQACAAkK/gs0EQB7AQAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAABNQAECn8fAAIRAAcKjQotCgHaAAARAAcKjQotCgHaAAAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.Muse:BAAANQAECgUIBQABNQAECgoKQgANAN8fAA==.',
My='Mybrother:BAAANQAECgMIBgAAAA==.',
Na='Nangsa:BAABNQAECn8eAAINAAkKNgYwqwBcAQANAAkKNgYwqwBcAQAAAA==.Nastee:BAAANQADCgEIAQAAAA==.Nautisassin:BAABNQAECn8ZAAINAAgK4xKegQAJAgANAAgK4xKegQAJAgABNQAECgoKNQARAMMRAA==.',
Ne='Necrodk:BAAANQAECggIBQABNQAECgoKPgANAB8mAA==.Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAABNQAECn8bAAIDAAcKdw4QLAALAQADAAcKdw4QLAALAQAAAA==.Neçromonger:BAABNQAECn8+AAMNAAoKHyZjBADEAwANAAoKHyZjBADEAwADAAcKzRuhGgCtAQAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggIMwAAAA==.',
No='Noxz:BAABNQAECn9JAAQHAAoKSSCuEwDKAgAHAAkKhB+uEwDKAgAGAAkKcxteLQCRAgAKAAEKNxSsKQAwAAAAAA==.',
Ny='Nyiais:BAABNQAECn8yAAIUAAkKUwmFJwBeAQAUAAkKUwmFJwBeAQAAAA==.',
Ob='Obsessedwith:BAABNQAECn84AAINAAoKrx3/OABpAgANAAoKrx3/OABpAgAAAA==.',
Oh='Ohamernster:BAABNQAECn8hAAIRAAoK/xaIUQA4AgARAAoK/xaIUQA4AgAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Ou='Outlander:BAAANQAECgUICAABNQAECgUIBQAFAAAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palashell:BAAANQAECggICQAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgYICQAAAA==.Paulpitine:BAAANQABCgIIAgAAAA==.',
Pe='Persiflage:BAAANQAECgQIBQAAAA==.',
Pi='Pixielune:BAAANQAECggIAQAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAFFAYICgAGAEYFAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Rachellynn:BAAANQADCgEIAQAAAA==.Raginghavoc:BAABNQAECn8cAAIhAAoK4xPzVQD8AQAhAAoK4xPzVQD8AQAAAA==.Raichi:BAABNQAECn85AAIfAAoKGh7tGgBmAgAfAAoKGh7tGgBmAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ralas:BAAANQAECgUICAAAAA==.Ramasseur:BAAANQABCgIIAgAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAABNQAECn8sAAINAAkKFiS5DgAbAwANAAkKFiS5DgAbAwAAAA==.Reeally:BAAANQAECgcIEwABNQAECgkJLAANABYkAA==.Reelly:BAAANQADCgUIBwABNQAECgkJLAANABYkAA==.Reppitt:BAAANQADCgYICAAAAA==.',
Ri='Rik:BAAANQAECgUIDAAAAA==.Rikira:BAAANQAECgYIBgAAAA==.Rionnach:BAAANQADCgUIBAAAAA==.Riopia:BAAANQADCggIFAAAAA==.Riptheramore:BAAANQAECgYIBgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgQIBQAAAA==.Ronny:BAAANQAECgIIAwABNQAECgoKSQAmAKohAA==.Ronosaur:BAABNQAECn9JAAMmAAoKqiEMFQAfAwAmAAoKqiEMFQAfAwAEAAkKyRZbGwAwAgAAAA==.Ronrad:BAAANQAECggICAABNQAECgoKSQAmAKohAA==.Rons:BAAANQAECgYICwABNQAECgoKSQAmAKohAA==.Roulette:BAAANQADCggIDgAAAA==.Rozzinor:BAAANQAECgMIBQABNQAECgkJLgAmAA4XAA==.Rozzjung:BAAANQAECgMIBgABNQAECgkJLgAmAA4XAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggIDAABNQAFFAcIFQANALkcAA==.Ruslah:BAABNQAECn8uAAINAAcKEhkWqAC1AQANAAcKEhkWqAC1AQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECn8vAAIjAAoKhxTnDQAZAgAjAAoKhxTnDQAZAgAAAA==.Sanguinius:BAABNQAECn8qAAIOAAoKviTsBQC+AwAOAAoKviTsBQC+AwAAAA==.Savageslayer:BAABNQAECn9JAAMmAAoKlRknKgCHAgAmAAoKlRknKgCHAgALAAQKlw7ENgDtAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgUIBgAAAA==.Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQAECgUIEAAAAA==.Seventl:BAABNQAECn8uAAMgAAoKmBrmHwCCAgAgAAkKHRvmHwCCAgAMAAUKGA7JPQDKAAAAAA==.',
Sh='Shadowbloom:BAABNQAECn8fAAIRAAcKXgiv/ADvAAARAAcKXgiv/ADvAAAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAABNQAECn8iAAMJAAoKfRLiPwAVAgAJAAoKfRLiPwAVAgAVAAYKgxrDgACiAQAAAA==.Shaokhan:BAACNQAFFH8HAAIfAAQKORJcCgAeAQAfAAQKORJcCgAeAQA1AAQKfzYAAh8ACgrRHvMWAJUCAB8ACgrRHvMWAJUCAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgkJFwAGAAsKAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAABNQAECn8wAAIJAAkK0RjJLQBsAgAJAAkK0RjJLQBsAgAAAA==.Sinuouss:BAAANQAECgUIBQAAAA==.Sioux:BAAANQAECgUIBgAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECgoKKgARAN0dAA==.Starlithe:BAAANQADCgcIDgAAAA==.Steele:BAAANQAECgQIBAABNQAECgoKJAAPAHETAA==.Stoogatz:BAABNQAECn8uAAQmAAkKDherUwCLAQAmAAgKVRCrUwCLAQAEAAcKkxGePwANAQALAAMKExiBSwCQAAAAAA==.Stormiee:BAAANQADCgYICQAAAA==.',
Su='Suicidekings:BAABNQAECn8pAAMaAAkK/hElNwBoAQAaAAkK/hElNwBoAQAiAAEK4QO5kAAqAAABNQAECgoKNgAGAEEeAA==.',
['Sí']='Símbá:BAAANQAECgYICwAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECn9DAAMmAAoKGAzvMwBuAQAmAAoKGAzvMwBuAQALAAEKAADmjwAAAAAAAA==.Tallyblue:BAABNQAECn8aAAIOAAoKYwX2kwD/AAAOAAoKYwX2kwD/AAAAAA==.Tanarisfry:BAAANQAECggIDwAAAA==.Tarrfashi:BAAANQAECggICAAAAA==.Taserface:BAAANQAECgMIAwAAAA==.',
Te='Temüjin:BAABNQAECn8mAAICAAoKBBYGCQBIAgACAAoKBBYGCQBIAgAAAA==.',
Th='Tharamore:BAAANQAECgcICgAAAA==.Theeonlyone:BAABNQAECn8+AAIQAAoKURTvRgAAAgAQAAoKURTvRgAAAgAAAA==.',
Ti='Tiberlock:BAAANQAECgMIAwAAAA==.Tioshadow:BAABNQAECn8WAAIRAAcKaxJ80QB4AQARAAcKaxJ80QB4AQABNQAFFAQIBwAfADkSAA==.Tiosombra:BAAANQADCggICAABNQAFFAQIBwAfADkSAA==.Tiranii:BAABNQAECn8sAAMYAAkK5Q58CQBMAQAYAAkK5Q58CQBMAQANAAQKFgvD/wCyAAAAAA==.Titannus:BAABNQAECn81AAIRAAoKwxEOcgDqAQARAAoKwxEOcgDqAQAAAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Trejotacos:BAAANQAECgMIAwAAAA==.Tribalrage:BAABNQAECn8jAAMJAAgK2Au7eQBGAQAJAAgK2Au7eQBGAQAVAAQKOAW88gCwAAAAAA==.Trinityblood:BAABNQAECn8gAAILAAkKvRKUHgCOAQALAAkKvRKUHgCOAQAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIFgABNQAECgoKNQARAMMRAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAFFAQICgACAHAOAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Vandal:BAACNQAFFH8KAAMGAAYKRgUIFABsAQAGAAYKRgUIFABsAQAHAAEKvQebGABCAAA1AAQKfykABAcACgoFFXIdAFYCAAcACgoFFXIdAFYCAAoABgqLC40QACABAAYAAwrUEE3gAIgAAAAA.Vara:BAAANQAECgIIBQAAAA==.Varrigos:BAAANQADCgcIGwAAAA==.Vartence:BAAANQAECgEIAQAAAA==.',
Ve='Vega:BAABNQAECn8tAAMGAAoK4x6rEQA7AwAGAAoK4x6rEQA7AwAHAAkKhx2mDwBfAgAAAA==.',
Vo='Voltz:BAABNQAECn8sAAIVAAkK+w/sXABwAQAVAAkK+w/sXABwAQAAAA==.',
Vy='Vynllistar:BAAANQAECgIIAgABNQAECgoKOAARAOQhAA==.',
Wa='Wanigorp:BAAANQAECgcIBwAAAA==.',
We='Wetbread:BAABNQAECn8cAAIiAAgKLROcUQDNAQAiAAgKLROcUQDNAQAAAA==.',
Wi='Wiind:BAABNQAECn8fAAIdAAkKGxLwFwA8AgAdAAkKGxLwFwA8AgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgcIEQABNQAECgoKIwAJAJAWAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQAECgYIBQAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECn9KAAIbAAoK9x6xCAC5AgAbAAoK9x6xCAC5AgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAQIBwAfADkSAA==.',
Yo='Yomamasez:BAABNQAECn85AAIRAAkK8AdfzAA+AQARAAkK8AdfzAA+AQAAAA==.',
Ze='Zenaa:BAAANQADCggICAAAAA==.Zerith:BAAANQADCggICAAAAA==.Zeryph:BAAANQADCggIDAAAAA==.Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECn8cAAMcAAkKGxHqGAC6AQAcAAgK+BLqGAC6AQAnAAIK7QWgJAAzAAABNQAECgUIBQAFAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAABNQAECn8lAAIiAAkKnB88GAAoAgAiAAkKnB88GAAoAgAAAA==.',
Zo='Zoub:BAAANQAECggIDAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Är']='Ärc:BAAANQABCgYICAAAAA==.',
['Ëe']='Ëevee:BAAANQADCggIEAAAAA==.',
['Ða']='Ðark:BAAANQAECgUICAABNQAECgoKQgANAN8fAA==.',
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
