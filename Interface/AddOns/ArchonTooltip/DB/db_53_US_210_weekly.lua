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
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aalicya:BAAANQAECgYIBwAAAA==.',
Ac='Acegoblain:BAACNQAFFH8GAAMBAAYKngc0GgALAQABAAUK1AY0GgALAQACAAEKyArAEABOAAA1AAQKfx0AAwEACgq/G5aKAH8BAAEACgqyFpaKAH8BAAIAAgpKJQkcAN8AAAE1AAUUBQgQAAMAFw8A.',
Ad='Adind:BAABNQAECn9iAAIEAAoKKiOEAgDfAwAEAAoKKiOEAgDfAwAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCggIDAABNQAECgEIAQAFAAAAAA==.Aeropally:BAAANQAECgEIAQAAAA==.Aerorising:BAAANQADCgYIBgABNQAECgEIAQAFAAAAAA==.Aeroshaman:BAAANQADCggICAABNQAECgEIAQAFAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgcIEgAAAA==.',
Al='Alaval:BAABNQAECn8WAAMGAAkKwAn7lABWAQAGAAkKwAn7lABWAQAHAAYKHAWATQDeAAAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgIIAwABNQAECggIAgAFAAAAAA==.Alestalker:BAAANQADCgUIBQABNQAECgUIBQAFAAAAAA==.Aletheïa:BAAANQAECgEIAQAAAA==.Aliggan:BAAANQABCgUIBwAAAA==.Allthesmokee:BAAANQADCgYIBgAAAA==.Althamon:BAAANQAECgUICQAAAA==.',
An='Andromalius:BAAANQADCgUIBQAAAA==.Antamun:BAABNQAECn9GAAIIAAoK+Rl7BgBGAgAIAAoK+Rl7BgBGAgAAAA==.',
Ao='Aoasis:BAABNQAECn8jAAIJAAoKkBbnQgDxAQAJAAoKkBbnQgDxAQAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgkJFgAGAMAJAA==.',
Ar='Araethea:BAACNQAFFH8IAAIGAAQKDSQUEACIAQAGAAQKDSQUEACIAQA1AAQKfzQAAwoACgpYJesCANgCAAYACQpDJSkUACUDAAoACAr1H+sCANgCAAAA.Arasettey:BAAANQADCggICAABNQAFFAYICgALALkZAA==.Arethusa:BAAANQADCggIEAAAAA==.Arislynn:BAABNQAECn8pAAIMAAgKfAvyJwCGAQAMAAgKfAvyJwCGAQAAAA==.Arlilea:BAAANQAECgMIAwABNQAECggIGAANALQEAA==.Aryn:BAABNQAECn8gAAMHAAoKOBDvMACcAQAHAAkKZQ/vMACcAQAGAAQKrAQa3ACUAAAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgcIDQAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECn8rAAIOAAoKESH4GAAVAwAOAAoKESH4GAAVAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgYICgAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgUIBgAAAA==.Baromir:BAAANQADCgYIBgAAAA==.Bathin:BAABNQAECn8uAAMPAAoK0BNNBQByAgAPAAkKExVNBQByAgAQAAQKJQtpuwDHAAAAAA==.Bathwater:BAABNQAECn83AAIJAAoKfCP2DABYAwAJAAoKfCP2DABYAwAAAA==.',
Be='Bearbottom:BAAANQAECggICgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECn8lAAIRAAoKaBHemQDvAQARAAoKaBHemQDvAQAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBQABNQAECgcICgAFAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggICAAFAAAAAA==.Bigtriangle:BAABNQAECn8eAAISAAkK8h1XDwA1AgASAAkK8h1XDwA1AgABNQAFFAYICgALALkZAA==.Billiamson:BAABNQAECn8UAAISAAgKHBZCEwDxAQASAAgKHBZCEwDxAQAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECn8pAAITAAoKTxjTKgBFAgATAAoKTxjTKgBFAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcIBgAAAA==.Bloodaxe:BAAANQAECggIDgAAAA==.',
Bo='Booddha:BAAANQADCggIDgAAAA==.Bornferal:BAAANQAECgcIDAAAAA==.Botasamigo:BAAANQAECgQICgAAAA==.',
Br='Brandagh:BAAANQAECgUICAAAAA==.Breadglaive:BAABNQAECn8WAAIUAAoK8x5PCQC2AgAUAAoK8x5PCQC2AgAAAA==.Breezy:BAAANQAECggIAgAAAA==.Bryzx:BAACNQAFFH8VAAIJAAgKaRrzAgBqAgAJAAgKaRrzAgBqAgA1AAQKfykAAwkACgrDIs8PAEUDAAkACgrDIs8PAEUDABUAAQqtDprsADoAAAAA.Bryzxbless:BAAANQAECgQIAwABNQAECgcICgAFAAAAAA==.',
Bu='Bubblebee:BAABNQAECn83AAINAAoK+hfGNgBeAgANAAoK+hfGNgBeAgAAAA==.Bullan:BAAANQADCggICQAAAA==.Bun:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAABNQAECn8nAAIUAAkKgQRzMAD/AAAUAAkKgQRzMAD/AAAAAA==.',
Ca='Cakestripper:BAABNQAECn8aAAINAAUKNg+fygACAQANAAUKNg+fygACAQAAAA==.Caripaige:BAAANQAECgQIBAAAAA==.Cavetard:BAAANQADCgYICgAAAA==.',
Ce='Celticdreams:BAAANQAECgUIBgAAAA==.Ceravolo:BAAANQAECgEIAQAAAA==.',
Ch='Charmeine:BAAANQABCgQIBAABNQAECgoKKwAOABEhAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECgkJKgARAEgRAA==.Clêver:BAAANQADCgYIBgABNQAECgYIGQABAJYeAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAACNQAFFH8JAAIRAAUKrxTqEQDlAAARAAUKrxTqEQDlAAA1AAQKf0cAAhEACgquIbUgAEEDABEACgquIbUgAEEDAAAA.',
Cu='Cubouros:BAAANQADCggICAABNQAECgoKKwAOABEhAA==.',
Cy='Cynemon:BAABNQAECn8uAAIKAAgKnxReBADpAQAKAAgKnxReBADpAQAAAA==.Cynleel:BAAANQAECgQIBQABNQAECggILgAKAJ8UAA==.',
Da='Dadu:BAAANQADCgEIAQAAAA==.Daftmonk:BAAANQADCgYIBgAAAA==.Daifuku:BAABNQAECn9JAAITAAoKOiIoCgBKAwATAAoKOiIoCgBKAwAAAA==.Dakyaa:BAAANQADCgMIAwAAAA==.Darknonsence:BAAANQAECgEIAQAAAA==.',
De='Demonetizeme:BAABNQAECn80AAMPAAgK+w+PCgDMAQAPAAgK+w+PCgDMAQAWAAIKMgh3XwBmAAABNQAECgkJFgAGAMAJAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwAFAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgUIDQAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQAECgUIBQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgcIGwAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQICwAAAA==.',
['Då']='Dåmage:BAABNQAECn8gAAIRAAYKBQkIHQHuAAARAAYKBQkIHQHuAAAAAA==.',
Ed='Edric:BAABNQAECn8eAAMXAAgKCxhSFQClAQAXAAgKCxhSFQClAQAJAAQK6hMSswCiAAAAAA==.Edyion:BAABNQAECn8tAAIYAAgK4gXACQAqAQAYAAgK4gXACQAqAQAAAA==.',
Ef='Efreet:BAABNQAECn8tAAMNAAoKEyMUKwDtAgANAAoKEyMUKwDtAgADAAYKABclPQBoAQAAAA==.',
El='Elimae:BAEANQADCgYICAAAAA==.',
En='Enochian:BAAANQADCgUIBwAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECggIEQAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggICAAFAAAAAA==.Evoda:BAABNQAECn8aAAIZAAcKoQhQBgDjAAAZAAcKoQhQBgDjAAAAAA==.',
Ex='Extrodinaire:BAABNQAECn8qAAIXAAoKgBbYEgA8AgAXAAoKgBbYEgA8AgAAAA==.',
Ez='Eziopandator:BAAANQABCggILQAAAA==.',
Fa='Fabiio:BAAANQAECgMIAgABNQAECggIAgAFAAAAAA==.Fadedemon:BAABNQAECn8vAAIUAAoKrBVjHQBoAgAUAAoKrBVjHQBoAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAABNQAECn82AAMCAAkKHSEPBwCFAgACAAkKHSEPBwCFAgABAAEKiwfzUAE3AAAAAA==.',
Fe='Fellvarg:BAABNQAECn8dAAMTAAcK6gxHXgAtAQATAAcK6gxHXgAtAQAaAAIKnAKyxAA/AAAAAA==.Felsgoodman:BAABNQAECn9JAAMWAAoKEyHsBADTAgAWAAgKmyDsBADTAgAQAAkKNh1PGQCpAgAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQAECgEIAQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgYICQAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgUIBwABNQAECgoKLAARAJcQAA==.',
Fo='Fotiá:BAABNQAECn8eAAIbAAoK9h3oBwC8AgAbAAoK9h3oBwC8AgABNQAFFAcIFQANALkcAA==.',
Fu='Fulgur:BAAANQAECggIEAAAAA==.Fumistra:BAAANQADCggIDgAAAA==.Furyalast:BAAANQADCggICAABNQAECgYIDwAFAAAAAA==.',
Ga='Gahïjï:BAAANQAECgQICgABNQAECgoKIwAJAJAWAA==.Galroot:BAAANQAECgUIBQABNQAFFAUIEAADABcPAA==.Galsnipes:BAACNQAFFH8QAAMDAAUKFw9SDgBYAQADAAUKcA5SDgBYAQANAAEKxgzjNwBLAAA1AAQKfzsAAwMACQoqHYoYAJMCAAMACQoqHYoYAJMCAA0AAQpTDfhRAUAAAAAA.Galvakrond:BAABNQAECn8mAAIcAAgKZgwcDwA8AQAcAAgKZgwcDwA8AQAAAA==.',
Ge='Gearno:BAAANQAECgEIAQAAAA==.Geearr:BAAANQAECgUICgAAAA==.',
Gl='Glitterturds:BAAANQADCgMIAwAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAFFAEIAQABNQAFFAYICgALALkZAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAABNQAECn8tAAMRAAgKoRZgmADzAQARAAgKoRZgmADzAQAOAAYKbAt0hgAQAQAAAA==.',
Gr='Grak:BAABNQAECn8hAAIdAAgK6xD9HAD8AQAdAAgK6xD9HAD8AQABNQAFFAYICgAGAEYFAA==.Gratescott:BAABNQAECn8qAAINAAoKiRIqXQD2AQANAAoKiRIqXQD2AQAAAA==.Grateshot:BAABNQAECn8ZAAINAAcKcBF+nQBcAQANAAcKcBF+nQBcAQAAAA==.Grik:BAAANQAECgUIEQAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAABNQAECn8oAAIGAAcK4BRfbACAAQAGAAcK4BRfbACAAQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAABNQAECn8dAAIGAAkKHBwcLQB+AgAGAAkKHBwcLQB+AgAAAA==.Hellenita:BAAANQAECgQIBQABNQAECgUIBQAFAAAAAA==.',
Hi='Hildebrand:BAAANQADCgcIBgAAAA==.Hitomitanaka:BAABNQAECn8oAAMEAAoKChI8HAAIAgAEAAoKChI8HAAIAgAeAAEKAABuTwAWAAAAAA==.',
Ho='Holyoshyy:BAABNQAECn83AAIRAAoKkSF1IgDOAgARAAoKkSF1IgDOAgAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgYIDwAAAA==.',
Hu='Hup:BAAANQAECgEIAQAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgYICwAAAA==.',
In='Inarin:BAAANQADCgcIGwAAAA==.',
Ir='Ironmaged:BAAANQAECgEIAQABNQAECgoKOQAfABoeAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgYICwAFAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAABNQAECn8+AAIgAAoK1RWSCgAfAgAgAAoK1RWSCgAfAgAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgYICQAAAA==.Jamezon:BAABNQAECn8YAAIIAAoKkhK/DADuAQAIAAoKkhK/DADuAQAAAA==.',
Je='Jebraxis:BAABNQAECn8lAAMhAAkKiRV8VwDlAQAhAAkKiRV8VwDlAQAIAAEKAADYNgArAAAAAA==.Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAABNQAECn8xAAIXAAgKthCeFgCPAQAXAAgKthCeFgCPAQAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCggIGQAFAAAAAA==.Johnzanpally:BAAANQAECgYIBgAAAA==.Joonbug:BAAANQABCgQIBwAAAA==.',
Ju='Juràssic:BAABNQAECn8aAAMLAAoKOhPyHwCdAQALAAoKOhPyHwCdAQAeAAQKIw1uLACPAAAAAA==.',
Ka='Kaeul:BAABNQAECn8ZAAIJAAgKvCWiDgBNAwAJAAgKvCWiDgBNAwAAAA==.Kahrot:BAABNQAECn8hAAIiAAoKliVlAwC+AwAiAAoKliVlAwC+AwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAABNQAECn8xAAIbAAgKSgpZLQD4AAAbAAgKSgpZLQD4AAAAAA==.Kando:BAAANQADCgQIBAAAAA==.Kazgrom:BAAANQAECgUICQAAAA==.Kazool:BAAANQAECgUIBwAAAA==.',
Ke='Keanuleaves:BAAANQAECgQIBQABNQAECgkJNgACAB0hAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAYICgALALkZAA==.Killerheal:BAACNQAFFH8KAAILAAYKuRn3AAACAgALAAYKuRn3AAACAgA1AAQKfyQAAgsACgoWI8EEAAwDAAsACgoWI8EEAAwDAAAA.Kiralan:BAAANQADCgcICQAAAA==.Kizzu:BAABNQAECn8/AAMTAAoKYh2FGAB2AgAiAAgKaRywKwCGAgATAAoKhRyFGAB2AgAAAA==.',
Kl='Klawdius:BAAANQADCgcICAAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECggIEQAAAA==.Koufeb:BAAANQADCgIIAgABNQAECgoKLAARAJcQAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgYICQAAAA==.',
['Kø']='Køteb:BAABNQAECn8wAAMaAAoK8hjmHQDCAgAaAAoK8hjmHQDCAgATAAMKzAOtkwBuAAAAAA==.',
Le='Leadshot:BAABNQAECn8gAAINAAQKEhF36wC/AAANAAQKEhF36wC/AAAAAA==.Leves:BAAANQAECgEIAQABNQAECgcICgAFAAAAAA==.',
Lo='Lochlynn:BAAANQADCggICAAAAA==.',
Lu='Luigimangion:BAAANQAECgUICAAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQAECgUIEQAAAA==.',
Ma='Maakha:BAABNQAECn8xAAIIAAgKaAmPFAAYAQAIAAgKaAmPFAAYAQAAAA==.Mabalzich:BAAANQADCgcIGwAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAABNQAECn8XAAMfAAgKvA+XKwC/AQAfAAgKvA+XKwC/AQAjAAEKAABmLgBKAAABNQAECgoKLAARAJcQAA==.Magicmack:BAAANQAECggICwAAAA==.Magroot:BAABNQAECn8oAAIMAAoKQBsJDQCkAgAMAAoKQBsJDQCkAgAAAA==.Maitake:BAAANQAECgYIBgAAAA==.Makula:BAABNQAECn8pAAMUAAgKMQ5IJgBSAQAUAAgKMQ5IJgBSAQAkAAEKAACnlQAAAAAAAA==.Mana:BAAANQAECggIDwAAAA==.Manabun:BAABNQAECn8XAAIaAAcK6g/bSwD/AAAaAAcK6g/bSwD/AAAAAA==.Manacakes:BAAANQAECgUICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECn8cAAIGAAkKmhgnNACXAgAGAAkKmhgnNACXAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAGAJoYAA==.Mapera:BAABNQAECn8xAAIlAAgKGyDnCgB9AgAlAAgKGyDnCgB9AgAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maraxx:BAABNQAECn8kAAMWAAkKaQyECwD1AAAQAAkKuAogXQCpAQAWAAcK3QmECwD1AAAAAA==.Maray:BAAANQAECgUICgAAAA==.Marjaya:BAABNQAECn8YAAICAAgK4A+iEABlAQACAAgK4A+iEABlAQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQAECgYIDQAAAA==.Meloncauley:BAABNQAECn8fAAMaAAcKhxHyWACPAQAaAAcKhxHyWACPAQATAAMKRwWblwBlAAAAAA==.Merjaya:BAAANQABCgIIAgAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Milkncookies:BAAANQAECggIAgAAAA==.Mirisa:BAAANQAECgQIBAAAAA==.Mirosa:BAABNQAECn8xAAICAAgK3wu6FQBSAQACAAgK3wu6FQBSAQAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAABNQAECn8fAAIRAAcKjQpl+wDbAAARAAcKjQpl+wDbAAAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.Muse:BAAANQADCgQIBAABNQAECgoKQAANAIYfAA==.',
My='Mybrother:BAAANQAECgMIBgAAAA==.',
Na='Nangsa:BAABNQAECn8dAAINAAgKygXLuAAlAQANAAgKygXLuAAlAQAAAA==.Nastee:BAAANQADCgEIAQAAAA==.Nautisassin:BAABNQAECn8ZAAINAAgK4xKegQAJAgANAAgK4xKegQAJAgABNQAECgoKLAARAJcQAA==.',
Ne='Necrodk:BAAANQAECggIBQABNQAECgoKPgANAB8mAA==.Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAABNQAECn8bAAIDAAcKdw5TKQALAQADAAcKdw5TKQALAQAAAA==.Neçromonger:BAABNQAECn8+AAMNAAoKHyZjBADEAwANAAoKHyZjBADEAwADAAcKzRuaGACxAQAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggIMwAAAA==.',
No='Noxz:BAABNQAECn9JAAQHAAoKSSCuEwDKAgAHAAkKhB+uEwDKAgAGAAkKcxvyJwCaAgAKAAEKNxSsKQAwAAAAAA==.',
Ny='Nyiais:BAABNQAECn8xAAIUAAgKoQnJKQA0AQAUAAgKoQnJKQA0AQAAAA==.',
Ob='Obsessedwith:BAABNQAECn8yAAINAAoK2BuGRgAxAgANAAoK2BuGRgAxAgAAAA==.',
Oh='Ohamernster:BAABNQAECn8hAAIRAAoK/xZrSABBAgARAAoK/xZrSABBAgAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Ou='Outlander:BAAANQAECgUICAABNQAECgUIBQAFAAAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palashell:BAAANQAECggICQAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgYICQAAAA==.Paulpitine:BAAANQABCgIIAgAAAA==.',
Pe='Persiflage:BAAANQAECgMIBQAAAA==.',
Pi='Pixielune:BAAANQAECggIAQAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAFFAYICgAGAEYFAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Rachellynn:BAAANQADCgEIAQAAAA==.Raginghavoc:BAABNQAECn8cAAIhAAoK4xO/TgAAAgAhAAoK4xO/TgAAAgAAAA==.Raichi:BAABNQAECn85AAIfAAoKGh7tGgBmAgAfAAoKGh7tGgBmAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ralas:BAAANQAECgQIBAAAAA==.Ramasseur:BAAANQABCgIIAgAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAABNQAECn8sAAINAAkKFiRsDAAiAwANAAkKFiRsDAAiAwAAAA==.Reeally:BAAANQAECgcIEwABNQAECgkJLAANABYkAA==.Reelly:BAAANQADCgUIBwABNQAECgkJLAANABYkAA==.Reppitt:BAAANQADCgYICAAAAA==.',
Ri='Rik:BAAANQAECgUIDAAAAA==.Rikira:BAAANQAECgYIBgAAAA==.Rionnach:BAAANQADCgUIBAAAAA==.Riopia:BAAANQADCggIFAAAAA==.Riptheramore:BAAANQAECgYIBgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgQIBQAAAA==.Ronny:BAAANQAECgIIAwABNQAECgoKRgAmAKohAA==.Ronosaur:BAABNQAECn9GAAMmAAoKqiEMFQAfAwAmAAoKqiEMFQAfAwAEAAkKyRazGAAyAgAAAA==.Ronrad:BAAANQAECggICAABNQAECgoKRgAmAKohAA==.Rons:BAAANQAECgUICQABNQAECgoKRgAmAKohAA==.Roulette:BAAANQADCggIDgAAAA==.Rozzinor:BAAANQAECgMIBQABNQAECgkJJwAmAAgTAA==.Rozzjung:BAAANQAECgMIBgABNQAECgkJJwAmAAgTAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggIDAABNQAFFAcIFQANALkcAA==.Ruslah:BAABNQAECn8uAAINAAcKEhk1nABfAQANAAcKEhk1nABfAQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECn8vAAIjAAoKhxTnDQAZAgAjAAoKhxTnDQAZAgAAAA==.Sanguinius:BAABNQAECn8nAAIOAAgK1SQCFwDvAgAOAAgK1SQCFwDvAgAAAA==.Savageslayer:BAABNQAECn9JAAMmAAoKlRl/IADlAQAmAAoKlRl/IADlAQALAAQKlw5ZMgDwAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgUIBgAAAA==.Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQAECgUIEAAAAA==.Seventl:BAABNQAECn8uAAMgAAoKmBrmHwCCAgAgAAkKHRvmHwCCAgAMAAUKGA7JPQDKAAAAAA==.',
Sh='Shadowbloom:BAABNQAECn8aAAIRAAcKtQc58wDoAAARAAcKtQc58wDoAAAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAABNQAECn8iAAMJAAoKfRJeOgAYAgAJAAoKfRJeOgAYAgAVAAYKgxrDgACiAQAAAA==.Shaokhan:BAACNQAFFH8HAAIfAAQKORJcCgAeAQAfAAQKORJcCgAeAQA1AAQKfzYAAh8ACgrRHvMWAJUCAB8ACgrRHvMWAJUCAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgkJFgAGAMAJAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAABNQAECn8vAAIJAAgKpBqeMQBCAgAJAAgKpBqeMQBCAgAAAA==.Sinuouss:BAAANQAECgUIBQAAAA==.Sioux:BAAANQAECgUIBgAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECgoKKgARAN0dAA==.Starlithe:BAAANQADCgcIDgAAAA==.Steele:BAAANQAECgQIBAABNQAECgoKIAAPAOMSAA==.Stoogatz:BAABNQAECn8nAAQmAAkKCBOrUwCLAQAmAAgKVRCrUwCLAQAEAAcKkxHPOgAPAQALAAEKAACqhQAAAAAAAA==.Stormiee:BAAANQADCgYICQAAAA==.Strongbow:BAAANQADCggIGQAAAA==.',
Su='Suicidekings:BAABNQAECn8pAAMaAAkK/hG2MgBxAQAaAAkK/hG2MgBxAQAiAAEK4QNZigArAAABNQAECgoKNgAGAEEeAA==.',
['Sí']='Símbá:BAAANQAECgYICwAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECn89AAImAAoKygsMMQBoAQAmAAoKygsMMQBoAQAAAA==.Tallyblue:BAABNQAECn8aAAIOAAoKYwXhiwABAQAOAAoKYwXhiwABAQAAAA==.Tanarisfry:BAAANQAECggIDwAAAA==.Tarrfashi:BAAANQAECggICAAAAA==.Taserface:BAAANQAECgMIAwAAAA==.',
Te='Temüjin:BAABNQAECn8mAAICAAoKBBYGCQBIAgACAAoKBBYGCQBIAgAAAA==.',
Th='Tharamore:BAAANQAECgcICgAAAA==.Theeonlyone:BAABNQAECn89AAIQAAoKURS8QAADAgAQAAoKURS8QAADAgAAAA==.',
Ti='Tiberlock:BAAANQAECgMIAwAAAA==.Tioshadow:BAABNQAECn8WAAIRAAcKaxJ80QB4AQARAAcKaxJ80QB4AQABNQAFFAQIBwAfADkSAA==.Tiosombra:BAAANQADCggICAABNQAFFAQIBwAfADkSAA==.Tiranii:BAABNQAECn8mAAMYAAgKaQ3bCAC3AQAYAAgKRQ3bCAC3AQANAAQKFgtM8gCzAAAAAA==.Titannus:BAABNQAECn8sAAIRAAoKlxBPdwDLAQARAAoKlxBPdwDLAQAAAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Trejotacos:BAAANQABCgUIDAAAAA==.Tribalrage:BAABNQAECn8gAAMJAAYKMw26kADwAAAJAAYKMw26kADwAAAVAAQKOAW88gCwAAAAAA==.Trinityblood:BAABNQAECn8aAAILAAkKZBKsGwCPAQALAAkKZBKsGwCPAQAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIFgABNQAECgoKLAARAJcQAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAFFAQICgACAHAOAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Vandal:BAACNQAFFH8KAAMGAAYKRgVOEQB2AQAGAAYKRgVOEQB2AQAHAAEKvQebGABCAAA1AAQKfygABAcACgpCFHIdAFYCAAcACgpCFHIdAFYCAAoABgqLC40QACABAAYAAwrUEE3gAIgAAAAA.Vara:BAAANQAECgIIBQAAAA==.Varrigos:BAAANQADCgcIGwAAAA==.',
Ve='Vega:BAABNQAECn8tAAMGAAoK4x6rEQA7AwAGAAoK4x6rEQA7AwAHAAkKhx2BDgBfAgAAAA==.',
Vo='Voltz:BAABNQAECn8sAAIVAAkK+w8HVQBxAQAVAAkK+w8HVQBxAQAAAA==.',
Vy='Vynllistar:BAAANQAECgIIAgABNQAECgoKNwARAJEhAA==.',
Wa='Wanigorp:BAAANQAECgYIBgAAAA==.',
We='Wetbread:BAABNQAECn8cAAIiAAgKLROcUQDNAQAiAAgKLROcUQDNAQAAAA==.',
Wi='Wiind:BAABNQAECn8fAAIdAAkKGxLwFwA8AgAdAAkKGxLwFwA8AgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgcIDQABNQAECgoKIwAJAJAWAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQAECgYIBQAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECn9KAAIbAAoK9x7TBwC+AgAbAAoK9x7TBwC+AgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAQIBwAfADkSAA==.',
Yo='Yomamasez:BAABNQAECn8yAAIRAAkK0wfmxQAyAQARAAkK0wfmxQAyAQAAAA==.',
Ze='Zenaa:BAAANQADCggICAAAAA==.Zerith:BAAANQADCggICAAAAA==.Zeryph:BAAANQADCggIDAAAAA==.Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECn8cAAMcAAkKGxHqGAC6AQAcAAgK+BLqGAC6AQAnAAIK7QWgJAAzAAABNQAECgUIBQAFAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAABNQAECn8kAAIiAAgK0x9oJgCjAgAiAAgK0x9oJgCjAgAAAA==.',
Zo='Zoub:BAAANQAECggIDAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Är']='Ärc:BAAANQABCgYICAAAAA==.',
['Ða']='Ðark:BAAANQAECgQIAwABNQAECgoKQAANAIYfAA==.',
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
