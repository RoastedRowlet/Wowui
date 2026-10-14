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

local lookup = {'Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Priest-Discipline','Priest-Holy','Druid-Guardian','Rogue-Subtlety','Priest-Shadow','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Destruction','Shaman-Enhancement','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Monk-Windwalker','Rogue-Assassination','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','Monk-Brewmaster','Hunter-Survival','Shaman-Elemental','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aalicya:BAAANQAECgUIBgAAAA==.',
Ac='Acegoblain:BAAANQAECggIDgABNQAFFAUIEAABABcPAA==.',
Ad='Adind:BAABNQAECn8zAAICAAkKOB92CQAsAwACAAkKOB92CQAsAwAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCggIDAAAAA==.Aeropally:BAAANQADCgYICwABNQADCggIDAADAAAAAA==.Aerorising:BAAANQADCgYIBgABNQADCggIDAADAAAAAA==.Aeroshaman:BAAANQADCggICAABNQADCggIDAADAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgYIEQAAAA==.',
Al='Alaval:BAAANQAECgcIEAAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgIIAQABNQAECggIAgADAAAAAA==.Alestalker:BAAANQADCgUIBQABNQAECgUIBQADAAAAAA==.Aletheïa:BAAANQADCggIDgAAAA==.Allthesmokee:BAAANQADCgYIBgAAAA==.Althamon:BAAANQAECgUIBQAAAA==.',
An='Andromalius:BAAANQADCgMIAwAAAA==.Antamun:BAABNQAECn8oAAIEAAkK5hbDCABSAgAEAAkK5hbDCABSAgAAAA==.',
Ao='Aoasis:BAAANQAECgYIEgAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgcIEAADAAAAAA==.',
Ar='Araethea:BAABNQAECn8lAAMFAAkKTyHkAgDXAgAFAAgK9R/kAgDXAgAGAAYKjyMRPgBuAgAAAA==.Arasettey:BAAANQADCggICAABNQAFFAYICgAHALkZAA==.Arethusa:BAAANQADCggIEAAAAA==.Arislynn:BAABNQAECn8cAAIIAAcKYQqDJwCGAQAIAAcKYQqDJwCGAQAAAA==.Arlilea:BAAANQAECgEIAQABNQAECgIIAwADAAAAAA==.Aryn:BAABNQAECn8ZAAMJAAgKsRN+MACcAQAJAAcKXhJ+MACcAQAGAAMKRQQe2QCUAAAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgcIDQAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECn8kAAIKAAgKZCKdGAAVAwAKAAgKZCKdGAAVAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgUICAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgEIAQAAAA==.Baromir:BAAANQADCgYIBgAAAA==.Bathin:BAABNQAECn8nAAMLAAgKnxc8BQByAgALAAgKaRc8BQByAgAMAAEKmAySNwE+AAAAAA==.Bathwater:BAABNQAECn8rAAINAAkKnSK8DABZAwANAAkKnSK8DABZAwAAAA==.',
Be='Bearbottom:BAAANQADCgYIBgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECn8cAAIOAAgKjBFjlwDwAQAOAAgKjBFjlwDwAQAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBAABNQAECgYICAADAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggJCAADAAAAAA==.Bigtriangle:BAABNQAECn8bAAIPAAgKVx4cDwA2AgAPAAgKVx4cDwA2AgABNQAFFAYICgAHALkZAA==.Billiamson:BAAANQAECgUIBwAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECn8iAAIQAAgKIRzyKQBGAgAQAAgKIRzyKQBGAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcJBQAAAA==.Bloodaxe:BAAANQAECgEIAgAAAA==.',
Bo='Booddha:BAAANQADCgYICgAAAA==.Bornferal:BAAANQAECgUJBQAAAA==.Botasamigo:BAAANQAECgQIBAAAAA==.',
Br='Breezy:BAAANQAECggIAgAAAA==.Bryzx:BAACNQAFFH8TAAINAAcKzBvNAgBuAgANAAcKzBvNAgBuAgA1AAQKfx4AAg0ACQqAIoUPAEYDAA0ACQqAIoUPAEYDAAAA.Bryzxbless:BAAANQAECgIIAQABNQAECgYICAADAAAAAA==.',
Bu='Bubblebee:BAABNQAECn8fAAIRAAkKPBLiUwBzAgARAAkKPBLiUwBzAgAAAA==.Bullan:BAAANQADCggICQAAAA==.Bun:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAAANQAECgQIEQAAAA==.',
Ca='Cakestripper:BAAANQAECgQIDgAAAA==.Caripaige:BAAANQADCgcIBwAAAA==.Cavetard:BAAANQADCgEIAQAAAA==.',
Ce='Ceravolo:BAAANQAECgEIAQAAAA==.',
Ch='Charmeine:BAAANQABCgQIBAABNQAECggIJAAKAGQiAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECggIHwAOAJ4PAA==.Clêver:BAAANQADCgYIBgABNQAECgUICwADAAAAAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAABNQAECn8uAAIOAAkKOCDnHwBCAwAOAAkKOCDnHwBCAwAAAA==.',
Cy='Cynemon:BAAANQAECgYIDwAAAA==.Cynleel:BAAANQAECgEIAQABNQAECgYIDwADAAAAAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daftmonk:BAAANQADCgYIBgAAAA==.Daifuku:BAABNQAECn8vAAIQAAkKvCHhCQBLAwAQAAkKvCHhCQBLAwAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.',
De='Demonetizeme:BAABNQAECn8ZAAMLAAcKmg98CgDMAQALAAcKmg98CgDMAQASAAIKMgj2XgBmAAABNQAECgcIEAADAAAAAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwADAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgMIBgAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQAECgUIBQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgcIGwAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQIBwAAAA==.',
['Då']='Dåmage:BAAANQAECgQIDgAAAA==.',
Ed='Edric:BAAANQAECgUIDAAAAA==.Edyion:BAAANQAECgYIEAAAAA==.',
Ef='Efreet:BAABNQAECn8eAAMRAAcKwiRYKgDuAgARAAcKwiRYKgDuAgABAAUKHxliPABpAQAAAA==.',
El='Elimae:BAEANQADCgQIBgAAAA==.Elvenfury:BAAANQADCggIDwAAAA==.',
En='Enochian:BAAANQADCgQIBgAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgQIBwAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.Evoda:BAAANQAECgUICgAAAA==.',
Ex='Extrodinaire:BAABNQAECn8fAAITAAgKzRefEgA8AgATAAgKzRefEgA8AgAAAA==.',
Ez='Eziopandator:BAAANQABCggIHAAAAA==.',
Fa='Fabiio:BAAANQAECgIIAgABNQAECggIAgADAAAAAA==.Fadedemon:BAABNQAECn8oAAIUAAgKkBj9HABpAgAUAAgKkBj9HABpAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAABNQAECn8eAAIVAAcKNx/1BgCGAgAVAAcKNx/1BgCGAgAAAA==.',
Fe='Fellvarg:BAAANQAECgUIDgAAAA==.Felsgoodman:BAABNQAECn8rAAMSAAkKtR7kBADUAgASAAgKmyDkBADUAgAMAAgKnxdWXgA5AgAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQAECgEIAQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgQIBwAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgUIBwABNQAECgcIEwADAAAAAA==.',
Fu='Fulgur:BAAANQAECgIIAgAAAA==.Fumistra:BAAANQADCggIDgAAAA==.',
Ga='Gahïjï:BAAANQAECgQIBAABNQAECgYIEgADAAAAAA==.Galroot:BAAANQADCgUICAABNQAFFAUIEAABABcPAA==.Galsnipes:BAACNQAFFH8QAAMBAAUKFw8FDgBYAQABAAUKcA4FDgBYAQARAAEKxgzWNgBLAAA1AAQKfywAAwEACArqHjYYAJQCAAEACArqHjYYAJQCABEAAQpTDctMAUEAAAAA.Galvakrond:BAAANQAECgYIDwAAAA==.',
Ge='Gearno:BAAANQAECgEIAQAAAA==.Geearr:BAAANQADCggIFgAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAECgcICAABNQAFFAYICgAHALkZAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAAANQAECgYIDwAAAA==.',
Gr='Grak:BAABNQAECn8hAAIWAAgK6xDWHAD8AQAWAAgK6xDWHAD8AQABNQAECgkJIAAJABYRAA==.Gratescott:BAAANQAECgYIEgAAAA==.Grateshot:BAAANQAECgQIBQAAAA==.Grik:BAAANQAECgUIEQAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAAANQAECgUIEQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAAANQAECgYICwAAAA==.Hellenita:BAAANQADCgIIAgAAAA==.',
Hi='Hildebrand:BAAANQADCgYJBgAAAA==.Hitomitanaka:BAAANQAECgcIEgAAAA==.',
Ho='Holyoshyy:BAABNQAECn8dAAIOAAgKiCEiQADRAgAOAAgKiCEiQADRAgAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQICQAAAA==.',
Hu='Hup:BAAANQADCggIDwAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgQIBAAAAA==.',
In='Inarin:BAAANQADCgcIGwAAAA==.',
Ir='Ironmaged:BAAANQAECgEIAQABNQAECgkJKwAXALIaAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgUICwADAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAABNQAECn8aAAIYAAcKZhNeOADvAQAYAAcKZhNeOADvAQAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgQIBwAAAA==.Jamezon:BAAANQAECgcIEAAAAA==.',
Je='Jebraxis:BAAANQAECgYIBgAAAA==.Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAAANQAECgYIEAAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgYIFwADAAAAAA==.Johnzanpally:BAAANQABCggICwAAAA==.Joonbug:BAAANQABCgQIBwAAAA==.',
Ju='Juràssic:BAAANQAECgYIDgAAAA==.',
Ka='Kaeul:BAABNQAECn8ZAAINAAgKvCVQDgBNAwANAAgKvCVQDgBNAwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAAANQAECgYIEAAAAA==.Kando:BAAANQADCgMIAwAAAA==.Kazgrom:BAAANQAECgUIBQAAAA==.Kazool:BAAANQAECgUIBwAAAA==.',
Ke='Keanuleaves:BAAANQADCgYIBgABNQAECgcIHgAVADcfAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAYICgAHALkZAA==.Killerheal:BAACNQAFFH8KAAIHAAYKuRnyAAACAgAHAAYKuRnyAAACAgA1AAQKfxgAAgcACQqQIaUGACEDAAcACQqQIaUGACEDAAAA.Kiralan:BAAANQADCgcJCQAAAA==.Kizzu:BAABNQAECn8hAAMZAAkK9xs6KwCGAgAZAAgKaRw6KwCGAgAQAAgKkBkmLgArAgAAAA==.',
Kl='Klawdius:BAAANQADCgcICAAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECggIEQAAAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgQIBwAAAA==.',
['Kø']='Køteb:BAABNQAECn8pAAMaAAkKDhuNHQDCAgAaAAkKDhuNHQDCAgAQAAMKzAOakABuAAAAAA==.',
Le='Leadshot:BAABNQAECn8VAAIRAAQKqhA1+gAKAQARAAQKqhA1+gAKAQAAAA==.Leves:BAAANQADCggICAABNQAECgYICAADAAAAAA==.',
Lu='Luigimangion:BAAANQAECgEIAQAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQAECgUICQAAAA==.',
Ma='Maakha:BAAANQAECgYIEAAAAA==.Mabalzich:BAAANQADCgcIGwAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAAANQAECgcIEwAAAA==.Magroot:BAABNQAECn8hAAIIAAgKTh3dDAClAgAIAAgKTh3dDAClAgAAAA==.Makula:BAAANQAECgYIDgAAAA==.Mana:BAAANQAECggIDAAAAA==.Manabun:BAAANQAECgQICAAAAA==.Manacakes:BAAANQAECgUICQAAAA==.Manamuffins:BAAANQADCgYICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECn8cAAIGAAkKmhhJMwCYAgAGAAkKmhhJMwCYAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAGAJoYAA==.Mapera:BAAANQAECgYIEAAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maraxx:BAAANQAECgYIDQAAAA==.Maray:BAAANQAECgQIBAAAAA==.Marjaya:BAAANQAECgUIBQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQAECgEIAQAAAA==.Meloncauley:BAABNQAECn8bAAMaAAYKnRMeWACQAQAaAAYKnRMeWACQAQAQAAMKRwV8lABlAAAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Mirisa:BAAANQAECgMIAwAAAA==.Mirosa:BAAANQAECgYIEAAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAAANQAECgUICgAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgMIBgAAAA==.',
Na='Nangsa:BAAANQAECgQICQAAAA==.Nastee:BAAANQADCgEIAQAAAA==.Nautisassin:BAAANQAECgYIDwABNQAECgcIEwADAAAAAA==.',
Ne='Necrodk:BAAANQAECggIBQABNQAECgkJJwARAA4mAA==.Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAAANQAECgYIEgAAAA==.Neçromonger:BAABNQAECn8nAAMRAAkKDiZLBADFAwARAAkKDiZLBADFAwABAAMKfCFBSwADAQAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggILQAAAA==.',
No='Noxz:BAABNQAECn8rAAQJAAkKkh5yEwDKAgAJAAkKkh5yEwDKAgAGAAgKIRN6YAD8AQAFAAEKNxQrKQAwAAAAAA==.',
Ny='Nyiais:BAAANQAECgYIEAAAAA==.',
Ob='Obsessedwith:BAABNQAECn8cAAIRAAcK1SD8VABwAgARAAcK1SD8VABwAgAAAA==.',
Oh='Ohamernster:BAAANQAECgIIAQAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palashell:BAAANQAECgEIAQAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgQIBwAAAA==.',
Pe='Persiflage:BAAANQADCggIIgAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAECgkJIAAJABYRAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Raginghavoc:BAAANQAECgYICQAAAA==.Raichi:BAABNQAECn8rAAIXAAkKshqaGgBmAgAXAAkKshqaGgBmAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAABNQAECn8bAAIRAAgK+xsdPwCrAgARAAgK+xsdPwCrAgAAAA==.Reeally:BAAANQAECgUIDgABNQAECggIGwARAPsbAA==.Reelly:BAAANQADCgUIBwABNQAECggIGwARAPsbAA==.Reppitt:BAAANQADCgQIBgAAAA==.',
Ri='Rik:BAAANQAECgUICQAAAA==.Rionnach:BAAANQADCgQIBAAAAA==.Riopia:BAAANQADCgYIEgAAAA==.Riptheramore:BAAANQAECgYIBgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgMIBAAAAA==.Ronny:BAAANQAECgEIAgABNQAECgkJLwAbAKUhAA==.Ronosaur:BAABNQAECn8vAAMbAAkKpSHGFAAfAwAbAAkKpSHGFAAfAwACAAQK/xkIPQA2AQAAAA==.Ronrad:BAAANQADCggICAABNQAECgkJLwAbAKUhAA==.Rons:BAAANQAECgUICAABNQAECgkJLwAbAKUhAA==.Roulette:BAAANQADCggIDwAAAA==.Rozzinor:BAAANQAECgIIAwABNQAECgcIGQAbACMOAA==.Rozzjung:BAAANQAECgMIBQABNQAECgcIGQAbACMOAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggJDAABNQAFFAQIDQARABoiAA==.Ruslah:BAAANQAECgUIEQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgABNQADCggIDAADAAAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECn8oAAIcAAgKhRW/DQAaAgAcAAgKhRW/DQAaAgAAAA==.Sanguinius:BAABNQAECn8YAAIKAAcKOSSXIgDgAgAKAAcKOSSXIgDgAgAAAA==.Savageslayer:BAABNQAECn8rAAMbAAkKtRqtKQCHAgAbAAkKtRqtKQCHAgAHAAEKiwfNaAAiAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgIIAgAAAA==.Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQAECgMIBQAAAA==.Seventl:BAABNQAECn8nAAMYAAgKTxxIHwCCAgAYAAgKTxxIHwCCAgAIAAQKqQn4PADKAAAAAA==.',
Sh='Shadowbloom:BAAANQAECgQIBwAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAAANQAECgYICgAAAA==.Shaokhan:BAACNQAFFH8HAAIXAAQKORIgCgAeAQAXAAQKORIgCgAeAQA1AAQKfysAAhcACQohHq8WAJUCABcACQohHq8WAJUCAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgcIEAADAAAAAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAAANQAECgYIDwAAAA==.Sioux:BAAANQAECgUIBQAAAA==.',
Sp='Spheres:BAAANQADCggIDAAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECggIHwAOAIUeAA==.Starlithe:BAAANQADCgYIBgAAAA==.Steele:BAAANQAECgQIBAAAAA==.Stoogatz:BAABNQAECn8ZAAMbAAcKIw7eUgCLAQAbAAcKIw7eUgCLAQACAAMKEBQGUwC4AAAAAA==.Stormiee:BAAANQADCgQIBwAAAA==.Strongbow:BAAANQADCgYIFwAAAA==.',
Su='Suicidekings:BAAANQAECgYIEgABNQAECgkJFQAGAPYUAA==.',
['Sí']='Símbá:BAAANQAECgUICwAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECn8lAAIbAAkKXwsCQQDxAQAbAAkKXwsCQQDxAQAAAA==.Tallyblue:BAAANQAECgYIDwAAAA==.Tanarisfry:BAAANQAECgYIDgAAAA==.Taserface:BAAANQADCgQJBwAAAA==.',
Te='Temüjin:BAABNQAECn8iAAIVAAgKYxfbCABJAgAVAAgKYxfbCABJAgAAAA==.',
Th='Tharamore:BAAANQAECgUIBgABNQAECgYICAADAAAAAA==.Theeonlyone:BAABNQAECn8kAAIMAAgK+BJ2ZwAhAgAMAAgK+BJ2ZwAhAgAAAA==.',
Ti='Tiberlock:BAAANQADCgQIBgAAAA==.Tioshadow:BAAANQAECgcIEwABNQAFFAQIBwAXADkSAA==.Tiosombra:BAAANQADCggICAABNQAFFAQIBwAXADkSAA==.Tiranii:BAABNQAECn8aAAIdAAcKLQ7NCAC3AQAdAAcKLQ7NCAC3AQAAAA==.Titannus:BAAANQAECgYIEQABNQAECgcIEwADAAAAAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Tribalrage:BAAANQAECgUIDQAAAA==.Trinityblood:BAAANQAECggICAAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIDgABNQAECgcIEwADAAAAAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAECgkJMgAVAFsZAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Vandal:BAABNQAECn8gAAQJAAkKFhEmHQBWAgAJAAkKFhEmHQBWAgAFAAYKiwt1EAAgAQAGAAIKSQ8z3QCIAAAAAA==.Varrigos:BAAANQADCgcIGwAAAA==.Vartence:BAAANQADCgIIAgAAAA==.',
Ve='Vega:BAAANQAECggIEAAAAA==.',
Vo='Voltz:BAABNQAECn8VAAIeAAgK1w05dQC9AQAeAAgK1w05dQC9AQAAAA==.',
We='Wetbread:BAABNQAECn8cAAIZAAgKLRPUUADNAQAZAAgKLRPUUADNAQAAAA==.',
Wi='Wiind:BAABNQAECn8fAAIWAAkKGxKyFwA9AgAWAAkKGxKyFwA9AgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgEIAgABNQAECgYIEgADAAAAAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQAECgUIBQAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECn8sAAIfAAkKWxz5DwCcAgAfAAkKWxz5DwCcAgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAQIBwAXADkSAA==.',
Yo='Yomamasez:BAABNQAECn8bAAIOAAcKtQY28QAzAQAOAAcKtQY28QAzAQAAAA==.',
Ze='Zeryph:BAAANQADCgYIBQAAAA==.Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECn8aAAMgAAcKWxTDGAC6AQAgAAcKWxTDGAC6AQAhAAEKAAAoJAAzAAABNQAECgUIBQADAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAAANQAECgcIDwAAAA==.',
Zo='Zoub:BAAANQAECgQIBAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Är']='Ärc:BAAANQABCgYICAAAAA==.',
['Ëe']='Ëevee:BAAANQADCgQIBAAAAA==.',
['Ða']='Ðark:BAAANQADCgUIBgABNQAECgkJKAARAFsfAA==.',
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
