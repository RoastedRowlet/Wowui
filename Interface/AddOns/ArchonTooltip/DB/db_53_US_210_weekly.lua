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

local lookup = {'Mage-Arcane','Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Restoration','Priest-Discipline','Druid-Guardian','Rogue-Subtlety','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Destruction','Shaman-Enhancement','Hunter-Survival','Rogue-Outlaw','Mage-Frost','DeathKnight-Blood','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Monk-Windwalker','Rogue-Assassination','DeathKnight-Unholy','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','Warrior-Arms','Druid-Balance','Shaman-Elemental','Evoker-Augmentation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aalicya:BAAANQAECgYIBwAAAA==.',
Ac='Acegoblain:BAACNQAFFH8FAAIBAAUK1AbSDgAbAQABAAUK1AbSDgAbAQA1AAQKfxYAAgEACQrdFInLAO8BAAEACQrdFInLAO8BAAE1AAUUBQgQAAIAFw8A.',
Ad='Adind:BAABNQAECn9PAAIDAAoKKSLlAwBdAwADAAoKKSLlAwBdAwAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCggIDAAAAA==.Aeropally:BAAANQADCgYICwABNQADCggIDAAEAAAAAA==.Aerorising:BAAANQADCgYIBgABNQADCggIDAAEAAAAAA==.Aeroshaman:BAAANQADCggICAABNQADCggIDAAEAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgcIEgAAAA==.',
Al='Alaval:BAABNQAECn8UAAMFAAkKnwn7lABWAQAFAAkKnwn7lABWAQAGAAYKHAWATQDeAAAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgIIAgABNQAECggIAgAEAAAAAA==.Alestalker:BAAANQADCgUIBQABNQAECgUIBQAEAAAAAA==.Aletheïa:BAAANQAECgEIAQAAAA==.Allthesmokee:BAAANQADCgYIBgAAAA==.Althamon:BAAANQAECgUICQAAAA==.',
An='Andromalius:BAAANQADCgQIBAAAAA==.Antamun:BAABNQAECn80AAIHAAoK6xfWCABTAgAHAAoK6xfWCABTAgAAAA==.',
Ao='Aoasis:BAABNQAECn8aAAIIAAcKexhVZwDWAQAIAAcKexhVZwDWAQAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgkJFAAFAJ8JAA==.',
Ar='Araethea:BAACNQAFFH8IAAIFAAQKDSRXCQCYAQAFAAQKDSRXCQCYAQA1AAQKfzIAAwUACgr5JBELAC8DAAUACQraJBELAC8DAAkACAr1H+sCANgCAAAA.Arasettey:BAAANQADCggICAABNQAFFAYICgAKALkZAA==.Arethusa:BAAANQADCggIEAAAAA==.Arislynn:BAABNQAECn8iAAILAAgKfAvyJwCGAQALAAgKfAvyJwCGAQAAAA==.Arlilea:BAAANQAECgEIAQABNQAECgYIEgAEAAAAAA==.Aryn:BAABNQAECn8gAAMGAAoKOBDvMACcAQAGAAkKZQ/vMACcAQAFAAQKrAQa3ACUAAAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgcIDQAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECn8rAAIMAAoKESH4GAAVAwAMAAoKESH4GAAVAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgUICAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgQIBQAAAA==.Baromir:BAAANQADCgYIBgAAAA==.Bathin:BAABNQAECn8uAAMNAAoK0BNNBQByAgANAAkKExVNBQByAgAOAAQKJQt+jwDRAAAAAA==.Bathwater:BAABNQAECn83AAIIAAoKfCP2DABYAwAIAAoKfCP2DABYAwAAAA==.',
Be='Bearbottom:BAAANQAECgYIBwAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECn8iAAIPAAkKORHemQDvAQAPAAkKORHemQDvAQAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBQABNQAECgcICgAEAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggICAAEAAAAAA==.Bigtriangle:BAABNQAECn8eAAIQAAkK8h1XDwA1AgAQAAkK8h1XDwA1AgABNQAFFAYICgAKALkZAA==.Billiamson:BAAANQAECgcIDAAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECn8pAAIRAAoKTxjTKgBFAgARAAoKTxjTKgBFAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcIBgAAAA==.Bloodaxe:BAAANQAECgcICwAAAA==.',
Bo='Booddha:BAAANQADCgcICwAAAA==.Bornferal:BAAANQAECgUIBQAAAA==.Botasamigo:BAAANQAECgQICgAAAA==.',
Br='Breadglaive:BAAANQAECggICAAAAA==.Breezy:BAAANQAECggIAgAAAA==.Bryzx:BAACNQAFFH8VAAIIAAgKaRrzAgBqAgAIAAgKaRrzAgBqAgA1AAQKfyMAAggACgrDIs8PAEUDAAgACgrDIs8PAEUDAAAA.Bryzxbless:BAAANQAECgIIAQABNQAECgYICQAEAAAAAA==.',
Bu='Bubblebee:BAABNQAECn8rAAISAAoKkBNPVQByAgASAAoKkBNPVQByAgAAAA==.Bullan:BAAANQADCggICQAAAA==.Bun:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAABNQAECn8bAAITAAYKtgPWNQCAAAATAAYKtgPWNQCAAAAAAA==.',
Ca='Cakestripper:BAABNQAECn8aAAISAAUKNg+xkgAMAQASAAUKNg+xkgAMAQAAAA==.Caripaige:BAAANQAECgQIBAAAAA==.Cavetard:BAAANQADCgYICgAAAA==.',
Ce='Ceravolo:BAAANQAECgEIAQAAAA==.',
Ch='Charmeine:BAAANQABCgQIBAABNQAECgoKKwAMABEhAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECgkJKAAPAEgRAA==.Clêver:BAAANQADCgYIBgABNQAECgUIEwAEAAAAAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAABNQAECn9AAAIPAAoKcB+1IABBAwAPAAoKcB+1IABBAwAAAA==.',
Cy='Cynemon:BAABNQAECn8gAAIJAAcK5ROXAwCbAQAJAAcK5ROXAwCbAQAAAA==.Cynleel:BAAANQAECgQIBQABNQAECgcIIAAJAOUTAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daftmonk:BAAANQADCgYIBgAAAA==.Daifuku:BAABNQAECn86AAIRAAoKyCAoCgBKAwARAAoKyCAoCgBKAwAAAA==.Dakyaa:BAAANQADCgMIAwAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.',
De='Demonetizeme:BAABNQAECn8kAAMNAAgKkw6PCgDMAQANAAgKkw6PCgDMAQAUAAIKMgh3XwBmAAABNQAECgkJFAAFAJ8JAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwAEAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgUICQAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQAECgUIBQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgcIGwAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgUIBwAAAA==.',
['Då']='Dåmage:BAABNQAECn8ZAAIPAAYKBQkIHQHuAAAPAAYKBQkIHQHuAAAAAA==.',
Ed='Edric:BAABNQAECn8YAAMVAAgKCxilDgCiAQAVAAgKCxilDgCiAQAIAAEKJh/hCQFUAAAAAA==.Edyion:BAABNQAECn8eAAIWAAcKVASuCwAyAQAWAAcKVASuCwAyAQAAAA==.',
Ef='Efreet:BAABNQAECn8mAAMSAAkKFCQUKwDtAgASAAkKFCQUKwDtAgACAAUKHxklPQBoAQAAAA==.',
El='Elimae:BAEANQADCgUIBwAAAA==.',
En='Enochian:BAAANQADCgQIBgAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgYIDQAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggICAAEAAAAAA==.Evoda:BAABNQAECn8UAAIXAAYKKgdhBgCoAAAXAAYKKgdhBgCoAAAAAA==.',
Ex='Extrodinaire:BAABNQAECn8mAAIVAAoKgBbYEgA8AgAVAAoKgBbYEgA8AgAAAA==.',
Ez='Eziopandator:BAAANQABCggIKQAAAA==.',
Fa='Fabiio:BAAANQAECgIIAgABNQAECggIAgAEAAAAAA==.Fadedemon:BAABNQAECn8vAAITAAoKrBVjHQBoAgATAAoKrBVjHQBoAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAABNQAECn8tAAMYAAgKECAPBwCFAgAYAAgKECAPBwCFAgABAAEKiwf4JgE6AAAAAA==.',
Fe='Fellvarg:BAABNQAECn8XAAMRAAcK6gxHXgAtAQARAAcK6gxHXgAtAQAZAAIKnAKyxAA/AAAAAA==.Felsgoodman:BAABNQAECn83AAMUAAoK2CDsBADTAgAUAAgKmyDsBADTAgAOAAkKpRrTXwA4AgAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQAECgEIAQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgUICAAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgUIBwABNQAECggIGQASAOMSAA==.',
Fo='Fotiá:BAAANQAECggIDAABNQAFFAYIFAASAAoeAA==.',
Fu='Fulgur:BAAANQAECggIDQAAAA==.Fumistra:BAAANQADCggIDgAAAA==.Furyalast:BAAANQADCggICAABNQAECgQICQAEAAAAAA==.',
Ga='Gahïjï:BAAANQAECgQICQABNQAECgcIGgAIAHsYAA==.Galroot:BAAANQAECgIIAgABNQAFFAUIEAACABcPAA==.Galsnipes:BAACNQAFFH8QAAMCAAUKFw9SDgBYAQACAAUKcA5SDgBYAQASAAEKxgzjNwBLAAA1AAQKfzcAAwIACQpVG4oYAJMCAAIACQpVG4oYAJMCABIAAQpTDfhRAUAAAAAA.Galvakrond:BAABNQAECn8XAAIaAAcKYQuhHgBpAQAaAAcKYQuhHgBpAQAAAA==.',
Ge='Gearno:BAAANQAECgEIAQAAAA==.Geearr:BAAANQAECgUICgAAAA==.',
Gl='Glitterturds:BAAANQADCgMIAwAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAFFAEIAQABNQAFFAYICgAKALkZAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAABNQAECn8dAAIPAAcK7BhgmADzAQAPAAcK7BhgmADzAQAAAA==.',
Gr='Grak:BAABNQAECn8hAAIbAAgK6xD9HAD8AQAbAAgK6xD9HAD8AQABNQAFFAMIBwAFAAYHAA==.Gratescott:BAABNQAECn8fAAISAAkKXRC+bQBcAQASAAkKXRC+bQBcAQAAAA==.Grateshot:BAAANQAECgQICgAAAA==.Grik:BAAANQAECgUIEQAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAABNQAECn8iAAIFAAcKBhSeVgBZAQAFAAcKBhSeVgBZAQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAAANQAECgcIEgAAAA==.Hellenita:BAAANQAECgMIAwAAAA==.',
Hi='Hildebrand:BAAANQADCgcIBgAAAA==.Hitomitanaka:BAABNQAECn8fAAMDAAoKyg7wHAB7AQADAAoKyg7wHAB7AQAcAAEKAABuTwAWAAAAAA==.',
Ho='Holyoshyy:BAABNQAECn8tAAIPAAkKayB3MAA5AgAPAAkKayB3MAA5AgAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQICQAAAA==.',
Hu='Hup:BAAANQAECgEIAQAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgYIBgAAAA==.',
In='Inarin:BAAANQADCgcIGwAAAA==.',
Ir='Ironmaged:BAAANQAECgEIAQABNQAECgoKOAAdABoeAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgYICwAEAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAABNQAECn8rAAIeAAkK0hXPCQDrAQAeAAkK0hXPCQDrAQAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgUICAAAAA==.Jamezon:BAABNQAECn8YAAIHAAoKkhK/DADuAQAHAAoKkhK/DADuAQAAAA==.',
Je='Jebraxis:BAAANQAECgYIEQAAAA==.Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAABNQAECn8hAAIVAAgKww1nEQBwAQAVAAgKww1nEQBwAQAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgcIGAAEAAAAAA==.Johnzanpally:BAAANQADCgYIDQAAAA==.Joonbug:BAAANQABCgQIBwAAAA==.',
Ju='Juràssic:BAAANQAECgcIDwAAAA==.',
Ka='Kaeul:BAABNQAECn8ZAAIIAAgKvCWiDgBNAwAIAAgKvCWiDgBNAwAAAA==.Kahrot:BAABNQAECn8gAAIfAAoKdSVlAwC+AwAfAAoKdSVlAwC+AwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAABNQAECn8hAAIgAAcK6QmCJwDIAAAgAAcK6QmCJwDIAAAAAA==.Kando:BAAANQADCgQIBAAAAA==.Kazgrom:BAAANQAECgUICQAAAA==.Kazool:BAAANQAECgUIBwAAAA==.',
Ke='Keanuleaves:BAAANQAECgQIBAABNQAECggILQAYABAgAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAYICgAKALkZAA==.Killerheal:BAACNQAFFH8KAAIKAAYKuRn3AAACAgAKAAYKuRn3AAACAgA1AAQKfyIAAgoACgrGItsCABUDAAoACgrGItsCABUDAAAA.Kiralan:BAAANQADCgcJCQAAAA==.Kizzu:BAABNQAECn8xAAMfAAoKpRuwKwCGAgAfAAgKaRywKwCGAgARAAoKhhoiGwD0AQAAAA==.',
Kl='Klawdius:BAAANQADCgcICAAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECggIEQAAAA==.Koufeb:BAAANQADCgIIAgABNQAECggIGQASAOMSAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgUICAAAAA==.',
['Kø']='Køteb:BAABNQAECn8wAAMZAAoK8hjmHQDCAgAZAAoK8hjmHQDCAgARAAMKzAOtkwBuAAAAAA==.',
La='Laerin:BAAANQABCgIIBAAAAA==.',
Le='Leadshot:BAABNQAECn8dAAISAAQKEhGvtQDEAAASAAQKEhGvtQDEAAAAAA==.Leves:BAAANQAECgEIAQABNQAECgcICgAEAAAAAA==.',
Lo='Lochlynn:BAAANQADCggICAAAAA==.',
Lu='Luigimangion:BAAANQAECgQIBQAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQAECgYIDQAAAA==.',
Ma='Maakha:BAABNQAECn8hAAIHAAcKEwhsFgA1AQAHAAcKEwhsFgA1AQAAAA==.Mabalzich:BAAANQADCgcIGwAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAABNQAECn8XAAMdAAgKvA+XKwC/AQAdAAgKvA+XKwC/AQAhAAEKAABmLgBKAAABNQAECggIGQASAOMSAA==.Magicmack:BAAANQAECgcICAABNQAECgoKHAAUAIcOAA==.Magroot:BAABNQAECn8oAAILAAoKQBsJDQCkAgALAAoKQBsJDQCkAgAAAA==.Maitake:BAAANQAECgIIAgAAAA==.Makula:BAABNQAECn8bAAITAAcKUgvnOQB2AQATAAcKUgvnOQB2AQAAAA==.Mana:BAAANQAECggIDwAAAA==.Manabun:BAAANQAECgUIEAAAAA==.Manacakes:BAAANQAECgUICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECn8cAAIFAAkKmhgnNACXAgAFAAkKmhgnNACXAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAFAJoYAA==.Mapera:BAABNQAECn8hAAIiAAcKuh9RCgAHAgAiAAcKuh9RCgAHAgAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maraxx:BAABNQAECn8cAAMUAAkK8AlyBwD/AAAUAAcK3QlyBwD/AAAOAAkKFQdigAD1AAAAAA==.Maray:BAAANQAECgUICQAAAA==.Marjaya:BAAANQAECgUICQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQAECgYIBwAAAA==.Meloncauley:BAABNQAECn8fAAMZAAcKhxHyWACPAQAZAAcKhxHyWACPAQARAAMKRwWblwBlAAAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Mirisa:BAAANQAECgMIAwAAAA==.Mirosa:BAABNQAECn8hAAIYAAcKRwy6FQBSAQAYAAcKRwy6FQBSAQAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAAANQAECgUIEgAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgMIBgAAAA==.',
Na='Nangsa:BAABNQAECn8VAAISAAYKogSeyAChAAASAAYKogSeyAChAAAAAA==.Nastee:BAAANQADCgEIAQAAAA==.Nautisassin:BAABNQAECn8ZAAISAAgK4xITWQCSAQASAAgK4xITWQCSAQAAAA==.',
Ne='Necrodk:BAAANQAECggIBQABNQAECgoKMwASABsmAA==.Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAABNQAECn8VAAICAAcK3A3NOgB6AQACAAcK3A3NOgB6AQAAAA==.Neçromonger:BAABNQAECn8zAAMSAAoKGyZjBADEAwASAAoKGyZjBADEAwACAAMKfCEIIwDmAAAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggIMwAAAA==.',
No='Noxz:BAABNQAECn83AAQGAAoKSSCuEwDKAgAGAAkKhB+uEwDKAgAFAAkKdxWrYQD8AQAJAAEKNxSsKQAwAAAAAA==.',
Ny='Nyiais:BAABNQAECn8hAAITAAcKrQj0JwDnAAATAAcKrQj0JwDnAAAAAA==.',
Ob='Obsessedwith:BAABNQAECn8kAAISAAkKOh7iVgBuAgASAAkKOh7iVgBuAgAAAA==.',
Oh='Ohamernster:BAAANQAECgQIAQAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Ou='Outlander:BAAANQAECgMIAwABNQAECgUIBQAEAAAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palashell:BAAANQAECggICQAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgUICAAAAA==.',
Pe='Persiflage:BAAANQADCggIKgAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAFFAMIBwAFAAYHAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Rachellynn:BAAANQADCgEIAQAAAA==.Raginghavoc:BAABNQAECn8YAAIjAAoK9BK5NwD0AQAjAAoK9BK5NwD0AQAAAA==.Raichi:BAABNQAECn84AAIdAAoKGh7tGgBmAgAdAAoKGh7tGgBmAgAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ralas:BAAANQAECgQIBAAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAABNQAECn8nAAISAAkKNh+dKAA/AgASAAkKNh+dKAA/AgAAAA==.Reeally:BAAANQAECgcIEwABNQAECgkJJwASADYfAA==.Reelly:BAAANQADCgUIBwABNQAECgkJJwASADYfAA==.Reppitt:BAAANQADCgUIBwAAAA==.',
Ri='Rik:BAAANQAECgUICQAAAA==.Rionnach:BAAANQADCgQIBAAAAA==.Riopia:BAAANQADCgcIEwAAAA==.Riptheramore:BAAANQAECgYIBgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgMIBAAAAA==.Ronny:BAAANQAECgEIAgABNQAECgoKOwAkAKohAA==.Ronosaur:BAABNQAECn87AAMkAAoKqiEMFQAfAwAkAAoKqiEMFQAfAwADAAQKbxurPQA2AQAAAA==.Ronrad:BAAANQADCggICAABNQAECgoKOwAkAKohAA==.Rons:BAAANQAECgUICAABNQAECgoKOwAkAKohAA==.Roulette:BAAANQADCggIDwAAAA==.Rozzinor:BAAANQAECgIIAwABNQAECggIIgAkAPgRAA==.Rozzjung:BAAANQAECgMIBgABNQAECggIIgAkAPgRAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggIDAABNQAFFAYIFAASAAoeAA==.Ruslah:BAABNQAECn8iAAISAAcKEhnQZwBrAQASAAcKEhnQZwBrAQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECn8vAAIhAAoKhxTnDQAZAgAhAAoKhxTnDQAZAgAAAA==.Sanguinius:BAABNQAECn8gAAIMAAgKSyR9EwCsAgAMAAgKSyR9EwCsAgAAAA==.Savageslayer:BAABNQAECn83AAMkAAoKdhknKgCHAgAkAAoKdhknKgCHAgAKAAQKlw6iIQD8AAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgUIBgAAAA==.Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQAECgUICwAAAA==.Seventl:BAABNQAECn8uAAMeAAoKmBrmHwCCAgAeAAkKHRvmHwCCAgALAAUKGA7JPQDKAAAAAA==.',
Sh='Shadowbloom:BAAANQAECgUIDwAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAABNQAECn8ZAAMlAAkKeRrDgACiAQAlAAYKgxrDgACiAQAIAAUKLxK3YwASAQAAAA==.Shaokhan:BAACNQAFFH8HAAIdAAQKORJcCgAeAQAdAAQKORJcCgAeAQA1AAQKfzYAAh0ACgrRHvMWAJUCAB0ACgrRHvMWAJUCAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgkJFAAFAJ8JAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAABNQAECn8fAAIIAAcKShl5NwC+AQAIAAcKShl5NwC+AQAAAA==.Sioux:BAAANQAECgUIBgAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECgkJJAAPADodAA==.Starlithe:BAAANQADCgcIDgAAAA==.Steele:BAAANQAECgQIBAABNQAECgoKFQANAPIPAA==.Stoogatz:BAABNQAECn8iAAMkAAgK+BGrUwCLAQAkAAcKKxCrUwCLAQADAAYKshIpMADmAAAAAA==.Stormiee:BAAANQADCgUICAAAAA==.Strongbow:BAAANQADCgcIGAAAAA==.',
Su='Suicidekings:BAABNQAECn8dAAIZAAgK3RBrMwAbAQAZAAgK3RBrMwAbAQABNQAECgoKJgAFANQdAA==.',
['Sí']='Símbá:BAAANQAECgYICwAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECn8vAAIkAAoKUQtYJgBSAQAkAAoKUQtYJgBSAQAAAA==.Tallyblue:BAAANQAECggIEAAAAA==.Tanarisfry:BAAANQAECggIDwAAAA==.Taserface:BAAANQAECgMIAwAAAA==.',
Te='Temüjin:BAABNQAECn8mAAIYAAoKBBYGCQBIAgAYAAoKBBYGCQBIAgAAAA==.',
Th='Tharamore:BAAANQAECgcICgAAAA==.Theeonlyone:BAABNQAECn80AAIOAAkKABXSNADXAQAOAAkKABXSNADXAQAAAA==.',
Ti='Tiberlock:BAAANQADCgUIBwAAAA==.Tioshadow:BAABNQAECn8WAAIPAAcKaxJ80QB4AQAPAAcKaxJ80QB4AQABNQAFFAQIBwAdADkSAA==.Tiosombra:BAAANQADCggICAABNQAFFAQIBwAdADkSAA==.Tiranii:BAABNQAECn8fAAMWAAgKQw3bCAC3AQAWAAgKHw3bCAC3AQASAAQKFgvSvAC3AAAAAA==.Titannus:BAABNQAECn8eAAIPAAcKHxJNwQCaAQAPAAcKHxJNwQCaAQABNQAECggIGQASAOMSAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Tribalrage:BAABNQAECn8VAAMIAAUK6xAQoQB2AAAIAAQKNw0QoQB2AAAlAAQKOAX9lgBxAAAAAA==.Trinityblood:BAAANQAECggIEAAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIFgABNQAECggIGQASAOMSAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAECgoKQAAYAH4bAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Vandal:BAACNQAFFH8HAAMFAAMKBgdeGAC8AAAFAAMKBgdeGAC8AAAGAAEKvQebGABCAAA1AAQKfycABAYACgpCFHIdAFYCAAYACgpCFHIdAFYCAAkABgqLC40QACABAAUAAwrUEE3gAIgAAAAA.Varrigos:BAAANQADCgcIGwAAAA==.Vartence:BAAANQADCgIIAgAAAA==.',
Ve='Vega:BAABNQAECn8kAAMFAAoK4x6rEQA7AwAFAAoK4x6rEQA7AwAGAAkKhx2RCAB3AgAAAA==.',
Vo='Voltz:BAABNQAECn8kAAIlAAkKzg9QNgB9AQAlAAkKzg9QNgB9AQAAAA==.',
Vy='Vynllistar:BAAANQAECgIIAgABNQAECgkJLQAPAGsgAA==.',
We='Wetbread:BAABNQAECn8cAAIfAAgKLROcUQDNAQAfAAgKLROcUQDNAQAAAA==.',
Wi='Wiind:BAABNQAECn8fAAIbAAkKGxLwFwA8AgAbAAkKGxLwFwA8AgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgUIBwABNQAECgcIGgAIAHsYAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQAECgYIBQAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECn84AAIgAAoKpB00EACbAgAgAAoKpB00EACbAgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAQIBwAdADkSAA==.',
Yo='Yomamasez:BAABNQAECn8pAAIPAAgKtQeYqwAAAQAPAAgKtQeYqwAAAQAAAA==.',
Ze='Zenaa:BAAANQADCggICAAAAA==.Zeryph:BAAANQADCggIDAAAAA==.Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECn8cAAMaAAkKGxHqGAC6AQAaAAgK+BLqGAC6AQAmAAIK7QWgJAAzAAABNQAECgUIBQAEAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAABNQAECn8cAAIfAAcKfiFoJgCjAgAfAAcKfiFoJgCjAgAAAA==.',
Zo='Zoub:BAAANQAECgQIBAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Är']='Ärc:BAAANQABCgYICAAAAA==.',
['Ëe']='Ëevee:BAAANQADCggICwAAAA==.',
['Ða']='Ðark:BAAANQADCgUIBgABNQAECgoKOAASABUfAA==.',
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
