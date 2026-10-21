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

local lookup = {'Mage-Arcane','Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warrior-Fury','Priest-Discipline','Druid-Guardian','Rogue-Subtlety','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Destruction','Hunter-Survival','Shaman-Enhancement','Mage-Frost','Monk-Windwalker','Evoker-Preservation','Druid-Feral','Rogue-Assassination','DeathKnight-Unholy','Paladin-Protection','DeathKnight-Blood','Monk-Brewmaster','Monk-Mistweaver','Druid-Balance','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aalicya:BAAANQAECgUIBgAAAA==.',
Ac='Acegoblain:BAABNQAECn8UAAIBAAkK4RP7QQA4AQABAAkK4RP7QQA4AQABNQAFFAUIEAACABcPAA==.',
Ad='Adind:BAABNQAECn8+AAIDAAoK5yBOAQAuAwADAAoK5yBOAQAuAwAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aeromage:BAAANQADCggIDAAAAA==.Aerorising:BAAANQADCgYIBgABNQADCggIDAAEAAAAAA==.Aeroshaman:BAAANQADCggICAABNQADCggIDAAEAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgcIEgAAAA==.',
Al='Alaval:BAABNQAECn8UAAMFAAkKnwn7lABWAQAFAAkKnwn7lABWAQAGAAYKHAWATQDeAAAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgMIAQABNQAECggIAgAEAAAAAA==.Alestalker:BAAANQADCgUIBQABNQAECgUIBQAEAAAAAA==.Aletheïa:BAAANQAECgEIAQAAAA==.Allthesmokee:BAAANQADCgYIBgAAAA==.Althamon:BAAANQAECgUIBQAAAA==.',
An='Andromalius:BAAANQADCgQIBAAAAA==.Antamun:BAABNQAECn8wAAIHAAoK8BbWCABTAgAHAAoK8BbWCABTAgAAAA==.',
Ao='Aoasis:BAAANQAECgYIEgAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgkJFAAFAJ8JAA==.',
Ar='Araethea:BAACNQAFFH8HAAIFAAMKfiXACABBAQAFAAMKfiXACABBAQA1AAQKfykAAwgACgo+IusCANgCAAgACAr1H+sCANgCAAUABwqSJPI+AG4CAAAA.Arasettey:BAAANQADCggICAABNQAFFAYICgAJALkZAA==.Arethusa:BAAANQADCggIEAAAAA==.Arislynn:BAABNQAECn8cAAIKAAcKYQryJwCGAQAKAAcKYQryJwCGAQAAAA==.Arlilea:BAAANQAECgEIAQABNQAECgUIDAAEAAAAAA==.Aryn:BAABNQAECn8cAAMGAAkK7g3vMACcAQAGAAkK7g3vMACcAQAFAAMKRQQa3ACUAAAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICAAAAA==.',
Az='Azirra:BAAANQADCgcIDQAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECn8nAAILAAkK+SH4GAAVAwALAAkK+SH4GAAVAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgUICAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgEIAQAAAA==.Baromir:BAAANQADCgYIBgAAAA==.Bathin:BAABNQAECn8qAAMMAAkKQhVNBQByAgAMAAkKExVNBQByAgANAAEKmAy0tgA5AAAAAA==.Bathwater:BAABNQAECn8zAAIOAAoKMiP2DABYAwAOAAoKMiP2DABYAwAAAA==.',
Be='Bearbottom:BAAANQAECgIIAQAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECn8fAAIPAAkK8A/emQDvAQAPAAkK8A/emQDvAQAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQIBQABNQAECgcICQAEAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggICAAEAAAAAA==.Bigtriangle:BAABNQAECn8dAAIQAAkKOR1XDwA1AgAQAAkKOR1XDwA1AgABNQAFFAYICgAJALkZAA==.Billiamson:BAAANQAECgYICAAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECn8lAAIRAAkK2BjTKgBFAgARAAkK2BjTKgBFAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcIBgAAAA==.Bloodaxe:BAAANQAECggICQAAAA==.',
Bo='Booddha:BAAANQADCgcICwAAAA==.Bornferal:BAAANQAECgUIBQAAAA==.Botasamigo:BAAANQAECgQICAAAAA==.',
Br='Breezy:BAAANQAECggIAgAAAA==.Bryzx:BAACNQAFFH8VAAIOAAgKaRrzAgBqAgAOAAgKaRrzAgBqAgA1AAQKfyEAAg4ACgrDIs8PAEUDAA4ACgrDIs8PAEUDAAAA.Bryzxbless:BAAANQAECgIIAQABNQAECgYICAAEAAAAAA==.',
Bu='Bubblebee:BAABNQAECn8mAAISAAoKAhOmLgBlAQASAAoKAhOmLgBlAQAAAA==.Bullan:BAAANQADCggICQAAAA==.Bun:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAABNQAECn8XAAITAAYKtgM1JACRAAATAAYKtgM1JACRAAAAAA==.',
Ca='Cakestripper:BAABNQAECn8WAAISAAUKOwsGYADrAAASAAUKOwsGYADrAAAAAA==.Caripaige:BAAANQADCgcIBwAAAA==.Cavetard:BAAANQADCgYIBwAAAA==.',
Ce='Ceravolo:BAAANQAECgEIAQAAAA==.',
Ch='Charmeine:BAAANQABCgQIBAABNQAECgkJJwALAPkhAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECggIJAAPAJ4PAA==.Clêver:BAAANQADCgYIBgABNQAECgUIEAAEAAAAAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAABNQAECn82AAIPAAkKOCC1IABBAwAPAAkKOCC1IABBAwAAAA==.',
Cy='Cynemon:BAABNQAECn8ZAAIIAAcKLhKaAQB3AQAIAAcKLhKaAQB3AQAAAA==.Cynleel:BAAANQAECgEIAQABNQAECgcIGQAIAC4SAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daftmonk:BAAANQADCgYIBgAAAA==.Daifuku:BAABNQAECn80AAIRAAoKZSAoCgBKAwARAAoKZSAoCgBKAwAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.',
De='Demonetizeme:BAABNQAECn8gAAMMAAgKkw6PCgDMAQAMAAgKkw6PCgDMAQAUAAIKMgh3XwBmAAABNQAECgkJFAAFAJ8JAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwAEAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgUICQAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQAECgUIBQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgcIGwAAAA==.Dragordawn:BAAANQABCgUICQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQIBwAAAA==.',
['Då']='Dåmage:BAABNQAECn8VAAIPAAYKBQn2kQCzAAAPAAYKBQn2kQCzAAAAAA==.',
Ed='Edric:BAAANQAECgUIEAAAAA==.Edyion:BAABNQAECn8aAAIVAAcKVASuCwAyAQAVAAcKVASuCwAyAQAAAA==.',
Ef='Efreet:BAABNQAECn8iAAMSAAgKiCMUKwDtAgASAAgKiCMUKwDtAgACAAUKHxklPQBoAQAAAA==.',
El='Elimae:BAEANQADCgUIBwAAAA==.Elvenfury:BAAANQADCggIDwAAAA==.',
En='Enochian:BAAANQADCgQIBgAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgQICQAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggICAAEAAAAAA==.Evoda:BAAANQAECgYIDwAAAA==.',
Ex='Extrodinaire:BAABNQAECn8iAAIWAAkKexTYEgA8AgAWAAkKexTYEgA8AgAAAA==.',
Ez='Eziopandator:BAAANQABCggIJQAAAA==.',
Fa='Fabiio:BAAANQAECgMIAgABNQAECggIAgAEAAAAAA==.Fadedemon:BAABNQAECn8rAAITAAkK3hVjHQBoAgATAAkK3hVjHQBoAgAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAABNQAECn8kAAIXAAcK3h8PBwCFAgAXAAcK3h8PBwCFAgAAAA==.',
Fe='Fellvarg:BAAANQAECgUIDgAAAA==.Felsgoodman:BAABNQAECn8zAAMUAAoKYR/sBADTAgAUAAgKmyDsBADTAgANAAkKLRldIgBlAQAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQAECgEIAQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgUICAAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgUIBwABNQAECggIFwAYALwPAA==.',
Fu='Fulgur:BAAANQAECgUIBQAAAA==.Fumistra:BAAANQADCggIDgAAAA==.Furyalast:BAAANQADCggICAABNQAECgQICQAEAAAAAA==.',
Ga='Gahïjï:BAAANQAECgQIBgABNQAECgYIEgAEAAAAAA==.Galroot:BAAANQADCgUICAABNQAFFAUIEAACABcPAA==.Galsnipes:BAACNQAFFH8QAAMCAAUKFw9SDgBYAQACAAUKcA5SDgBYAQASAAEKxgzjNwBLAAA1AAQKfzMAAwIACArqHpoJAEsBAAIACArqHpoJAEsBABIAAQpTDfhRAUAAAAAA.Galvakrond:BAAANQAECgcIDwAAAA==.',
Ge='Gearno:BAAANQAECgEIAQAAAA==.Geearr:BAAANQAECgUIBQAAAA==.',
Gl='Glitterturds:BAAANQADCgMIAwAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAECgcICwABNQAFFAYICgAJALkZAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAABNQAECn8XAAIPAAcK7BhgmADzAQAPAAcK7BhgmADzAQAAAA==.',
Gr='Grak:BAABNQAECn8hAAIZAAgK6xD9HAD8AQAZAAgK6xD9HAD8AQABNQAECgoKJgAGAEIUAA==.Gratescott:BAABNQAECn8YAAISAAgKag3DmwDPAQASAAgKag3DmwDPAQAAAA==.Grateshot:BAAANQAECgQIBgAAAA==.Grik:BAAANQAECgUIEQAAAA==.Grimgull:BAAANQADCgUICgAAAA==.',
Gw='Gwyndora:BAABNQAECn8cAAIFAAcK0hIWKQBZAQAFAAcK0hIWKQBZAQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
He='Healup:BAAANQAECgYIEQAAAA==.Hellenita:BAAANQADCgIIAgAAAA==.',
Hi='Hildebrand:BAAANQADCgcIBgAAAA==.Hitomitanaka:BAABNQAECn8dAAMDAAkKNg9+DQBlAQADAAkKNg9+DQBlAQAaAAEKAABuTwAWAAAAAA==.',
Ho='Holyoshyy:BAABNQAECn8lAAIPAAkKZB8TDAAiAgAPAAkKZB8TDAAiAgAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQICQAAAA==.',
Hu='Hup:BAAANQAECgEIAQAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgQIBAAAAA==.',
In='Inarin:BAAANQADCgcIGwAAAA==.',
Ir='Ironmaged:BAAANQAECgEIAQABNQAECgoKMwAYAKkbAA==.',
Is='Ismitethou:BAAANQADCggICQABNQAECgYICwAEAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAABNQAECn8iAAIbAAgK1xSFBwCjAQAbAAgK1xSFBwCjAQAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgUICAAAAA==.Jamezon:BAAANQAECgcIEgAAAA==.',
Je='Jebraxis:BAAANQAECgcICwAAAA==.Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAABNQAECn8aAAIWAAgKHgtDDwAMAQAWAAgKHgtDDwAMAQAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgcIGAAEAAAAAA==.Joonbug:BAAANQABCgQIBwAAAA==.',
Ju='Juràssic:BAAANQAECgYIDgAAAA==.',
Ka='Kaeul:BAABNQAECn8ZAAIOAAgKvCWiDgBNAwAOAAgKvCWiDgBNAwAAAA==.Kahrot:BAABNQAECn8cAAIcAAoK8iNlAwC+AwAcAAoK8iNlAwC+AwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAABNQAECn8aAAIdAAcK6QkXOgAeAQAdAAcK6QkXOgAeAQAAAA==.Kando:BAAANQADCgQIBAAAAA==.Kazgrom:BAAANQAECgUIBQAAAA==.Kazool:BAAANQAECgYIBwAAAA==.',
Ke='Keanuleaves:BAAANQADCgYIBgABNQAECgcIJAAXAN4fAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAYICgAJALkZAA==.Killerheal:BAACNQAFFH8KAAIJAAYKuRn3AAACAgAJAAYKuRn3AAACAgA1AAQKfxkAAgkACgolILsGACEDAAkACgolILsGACEDAAAA.Kiralan:BAAANQADCgcJCQAAAA==.Kizzu:BAABNQAECn8qAAMRAAoKgRoeBQASAgAcAAgKaRywKwCGAgARAAoKehgeBQASAgAAAA==.',
Kl='Klawdius:BAAANQADCgcICAAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECggIEQAAAA==.Koufeb:BAAANQADCgIIAgABNQAECggIFwAYALwPAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgUICAAAAA==.',
['Kø']='Køteb:BAABNQAECn8tAAMeAAoK8hjmHQDCAgAeAAoK8hjmHQDCAgARAAMKzAOtkwBuAAAAAA==.',
La='Laerin:BAAANQABCgIIBAAAAA==.',
Le='Leadshot:BAABNQAECn8ZAAISAAQKqhBSlQCCAAASAAQKqhBSlQCCAAAAAA==.Leves:BAAANQADCggICAABNQAECgcICQAEAAAAAA==.',
Lo='Lochlynn:BAAANQADCggICAAAAA==.',
Lu='Luigimangion:BAAANQAECgIIAQAAAA==.',
Ly='Lyzbeth:BAAANQABCgUJAwAAAA==.',
['Lï']='Lïmes:BAAANQAECgUICQAAAA==.',
Ma='Maakha:BAABNQAECn8aAAIHAAcKCwhsFgA1AQAHAAcKCwhsFgA1AQAAAA==.Mabalzich:BAAANQADCgcIGwAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAABNQAECn8XAAMYAAgKvA+XKwC/AQAYAAgKvA+XKwC/AQAfAAEKAABmLgBKAAAAAA==.Magicmack:BAAANQAECgIIAQAAAA==.Magroot:BAABNQAECn8kAAIKAAkKFhoJDQCkAgAKAAkKFhoJDQCkAgAAAA==.Makula:BAABNQAECn8XAAITAAcKUgvnOQB2AQATAAcKUgvnOQB2AQAAAA==.Mana:BAAANQAECggIDgAAAA==.Manabun:BAAANQAECgUICwAAAA==.Manacakes:BAAANQAECgUICgAAAA==.Manamuffins:BAAANQADCgYICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECn8cAAIFAAkKmhgnNACXAgAFAAkKmhgnNACXAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAFAJoYAA==.Mapera:BAABNQAECn8aAAIgAAcKuh97BADEAQAgAAcKuh97BADEAQAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maraxx:BAAANQAECgcIEgAAAA==.Maray:BAAANQAECgUICQAAAA==.Marjaya:BAAANQAECgUIBQAAAA==.Maynarde:BAAANQABCgYIBgAAAA==.',
Me='Medivarg:BAAANQAECgcIBgAAAA==.Meloncauley:BAABNQAECn8fAAMeAAcKhxHyWACPAQAeAAcKhxHyWACPAQARAAMKRwWblwBlAAAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Mirisa:BAAANQAECgMIAwAAAA==.Mirosa:BAABNQAECn8aAAIXAAcKRwy6FQBSAQAXAAcKRwy6FQBSAQAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAAANQAECgUIDgAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgMIBgAAAA==.',
Na='Nangsa:BAAANQAECgUIDgAAAA==.Nastee:BAAANQADCgEIAQAAAA==.Nautisassin:BAAANQAECgYIDwABNQAECggIFwAYALwPAA==.',
Ne='Necrodk:BAAANQAECggIBQABNQAECgoKLwASABYmAA==.Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAABNQAECn8VAAICAAcK3A3NOgB6AQACAAcK3A3NOgB6AQAAAA==.Neçromonger:BAABNQAECn8vAAMSAAoKFiZjBADEAwASAAoKFiZjBADEAwACAAMKfCEaTAAEAQAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.',
No='Noxz:BAABNQAECn8zAAQGAAoKMSCuEwDKAgAGAAkKhB+uEwDKAgAFAAkKbBKrYQD8AQAIAAEKNxSsKQAwAAAAAA==.',
Ny='Nyiais:BAABNQAECn8aAAITAAcKrQibHADJAAATAAcKrQibHADJAAAAAA==.',
Ob='Obsessedwith:BAABNQAECn8eAAISAAgKHB/iVgBuAgASAAgKHB/iVgBuAgAAAA==.',
Oh='Ohamernster:BAAANQAECgQIAQAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Ou='Outlander:BAAANQABCgUIBQABNQAECgUIBQAEAAAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palashell:BAAANQAECggICQAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgUICAAAAA==.',
Pe='Persiflage:BAAANQADCggIKgAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAECgoKJgAGAEIUAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Rachellynn:BAAANQADCgEIAQAAAA==.Raginghavoc:BAAANQAECgcIDAAAAA==.Raichi:BAABNQAECn8zAAIYAAoKqRssDQBKAQAYAAoKqRssDQBKAQAAAA==.Raihne:BAAANQADCgEIAQAAAA==.Ramasseuse:BAAANQABCgIIAgAAAA==.',
Re='Reallyreally:BAABNQAECn8hAAISAAkKGR6nDgD8AQASAAkKGR6nDgD8AQAAAA==.Reeally:BAAANQAECgUIDwABNQAECgkJIQASABkeAA==.Reelly:BAAANQADCgUIBwABNQAECgkJIQASABkeAA==.Reppitt:BAAANQADCgUIBwAAAA==.',
Ri='Rik:BAAANQAECgUICQAAAA==.Rionnach:BAAANQADCgQIBAAAAA==.Riopia:BAAANQADCgcIEwAAAA==.Riptheramore:BAAANQAECgYIBgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgMIBAAAAA==.Ronny:BAAANQAECgEIAgABNQAECgoKNwAhAA4hAA==.Ronosaur:BAABNQAECn83AAMhAAoKDiEMFQAfAwAhAAoKDiEMFQAfAwADAAQKbxvjIADIAAAAAA==.Ronrad:BAAANQADCggICAABNQAECgoKNwAhAA4hAA==.Rons:BAAANQAECgUICAABNQAECgoKNwAhAA4hAA==.Roulette:BAAANQADCggIDwAAAA==.Rozzinor:BAAANQAECgIIAwABNQAECgcIGgAhACMOAA==.Rozzjung:BAAANQAECgMIBQABNQAECgcIGgAhACMOAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggIDAABNQAFFAYIEwASAAoeAA==.Ruslah:BAABNQAECn8cAAISAAcKEhkxJwB9AQASAAcKEhkxJwB9AQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgABNQADCggIDAAEAAAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECn8rAAIfAAkKyxPnDQAZAgAfAAkKyxPnDQAZAgAAAA==.Sanguinius:BAABNQAECn8ZAAILAAgKSyQKIwDgAgALAAgKSyQKIwDgAgAAAA==.Savageslayer:BAABNQAECn8zAAMhAAoKShgnKgCHAgAhAAkKtRonKgCHAgAJAAQKlw6rEAAIAQAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgUIBgAAAA==.Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQAECgMIBgAAAA==.Seventl:BAABNQAECn8qAAMbAAkKYxnmHwCCAgAbAAkKYxnmHwCCAgAKAAQKqQnJPQDKAAAAAA==.',
Sh='Shadowbloom:BAAANQAECgUICwAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAAANQAECgcIDAAAAA==.Shaokhan:BAACNQAFFH8HAAIYAAQKORJcCgAeAQAYAAQKORJcCgAeAQA1AAQKfy8AAhgACgqPHhoIAI4BABgACgqPHhoIAI4BAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgkJFAAFAJ8JAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAABNQAECn8YAAIOAAcKKBkOFwCeAQAOAAcKKBkOFwCeAQAAAA==.Sioux:BAAANQAECgUIBgAAAA==.',
So='Solmendera:BAAANQADCgIIAgAAAA==.',
Sp='Spheres:BAAANQADCggIDAAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECgkJIQAPAKcbAA==.Starlithe:BAAANQADCgcIDQAAAA==.Steele:BAAANQAECgQIBAABNQAECggIDAAEAAAAAA==.Stoogatz:BAABNQAECn8aAAMhAAcKIw6rUwCLAQAhAAcKIw6rUwCLAQADAAMKEBT8UwC4AAAAAA==.Stormiee:BAAANQADCgUICAAAAA==.Strongbow:BAAANQADCgcIGAAAAA==.',
Su='Suicidekings:BAABNQAECn8WAAIeAAcKUBICWgCLAQAeAAcKUBICWgCLAQABNQAECgoKHAAFAOQZAA==.',
['Sí']='Símbá:BAAANQAECgYICwAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECn8sAAIhAAkK8gu8EgBDAQAhAAkK8gu8EgBDAQAAAA==.Tallyblue:BAAANQAECgcIDwAAAA==.Tanarisfry:BAAANQAECgYIDwAAAA==.Taserface:BAAANQADCgQJBwAAAA==.',
Te='Temüjin:BAABNQAECn8iAAIXAAgKYxcGCQBIAgAXAAgKYxcGCQBIAgAAAA==.',
Th='Tharamore:BAAANQAECgcICQAAAA==.Theeonlyone:BAABNQAECn8sAAINAAkKURP7DADiAQANAAkKURP7DADiAQAAAA==.',
Ti='Tiberlock:BAAANQADCgUIBwAAAA==.Tioshadow:BAABNQAECn8WAAIPAAcKaxKUewDSAAAPAAcKaxKUewDSAAABNQAFFAQIBwAYADkSAA==.Tiosombra:BAAANQADCggICAABNQAFFAQIBwAYADkSAA==.Tiranii:BAABNQAECn8aAAIVAAcKLQ7bCAC3AQAVAAcKLQ7bCAC3AQAAAA==.Titannus:BAABNQAECn8YAAIPAAcKLBBNwQCaAQAPAAcKLBBNwQCaAQABNQAECggIFwAYALwPAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Tribalrage:BAAANQAECgUIEgAAAA==.Trinityblood:BAAANQAECggICAAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIFgABNQAECggIFwAYALwPAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAECgoKOgAXAH4bAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Vandal:BAABNQAECn8mAAQGAAoKQhSHCABsAQAGAAoKQhSHCABsAQAIAAYKiwuNEAAgAQAFAAIKSQ9N4ACIAAAAAA==.Varrigos:BAAANQADCgcIGwAAAA==.Vartence:BAAANQADCgIIAgAAAA==.',
Ve='Vega:BAABNQAECn8bAAIFAAoK4x6rEQA7AwAFAAoK4x6rEQA7AwAAAA==.',
Vo='Voltz:BAABNQAECn8cAAIiAAkKxw2wGwBOAQAiAAkKxw2wGwBOAQAAAA==.',
Vy='Vynllistar:BAAANQAECgIIAgABNQAECgkJJQAPAGQfAA==.',
We='Wetbread:BAABNQAECn8cAAIcAAgKLROcUQDNAQAcAAgKLROcUQDNAQAAAA==.',
Wi='Wiind:BAABNQAECn8fAAIZAAkKGxLwFwA8AgAZAAkKGxLwFwA8AgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgUIBwABNQAECgYIEgAEAAAAAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQAECgYIBQAAAA==.',
Xh='Xhaltrix:BAAANQABCgcIBwAAAA==.',
Xo='Xonz:BAABNQAECn80AAIdAAoKQR00EACbAgAdAAoKQR00EACbAgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAQIBwAYADkSAA==.',
Yo='Yomamasez:BAABNQAECn8hAAIPAAcKtQbG9AAzAQAPAAcKtQbG9AAzAQAAAA==.',
Ze='Zenaa:BAAANQADCggIBgAAAA==.Zeryph:BAAANQADCggICwAAAA==.Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECn8aAAMjAAcKWxTqGAC6AQAjAAcKWxTqGAC6AQAkAAEKAACgJAAzAAABNQAECgUIBQAEAAAAAA==.',
Zi='Zippoo:BAAANQABCgIIAgAAAA==.Zirnbie:BAABNQAECn8YAAIcAAcKfiFoJgCjAgAcAAcKfiFoJgCjAgAAAA==.',
Zo='Zoub:BAAANQAECgQIBAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Ëe']='Ëevee:BAAANQADCgUIBwAAAA==.',
['Ða']='Ðark:BAAANQADCgUIBgABNQAECgoKLwASAJIeAA==.',
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
