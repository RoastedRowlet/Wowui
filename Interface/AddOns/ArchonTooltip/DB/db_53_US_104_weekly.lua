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

local lookup = {'Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Paladin-Protection','Mage-Arcane','Warrior-Protection','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','DeathKnight-Unholy','DemonHunter-Devourer','Rogue-Assassination','Paladin-Retribution','Shaman-Restoration','Rogue-Subtlety','Druid-Restoration','Priest-Holy','Hunter-Survival','Priest-Discipline','DeathKnight-Blood','Mage-Frost','Shaman-Enhancement','Shaman-Elemental','DemonHunter-Vengeance','Warrior-Arms','Evoker-Preservation','Paladin-Holy','Druid-Feral','DeathKnight-Frost','Rogue-Outlaw','Warrior-Fury','DemonHunter-Havoc',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aartoo:BAAANQABCggICAAAAA==.',
Ac='Acherona:BAAANQABCgQIBAAAAA==.Acuminada:BAAANQADCgIIAgAAAA==.Acuna:BAAANQAECgUIDAAAAA==.',
Ad='Adison:BAAANQADCgYIBgAAAA==.',
Af='Affliction:BAAANQAECgQICQAAAA==.',
Ai='Airz:BAAANQAECgIJBgAAAA==.',
Ak='Akâkiôs:BAAANQAECgUJCAAAAA==.',
Al='Aladorman:BAAANQAECgEIAQAAAA==.Alamo:BAAANQAECgIJAwAAAA==.Albertlin:BAAANQAECgQIBgAAAA==.Alexinar:BAAANQAECgEIAQAAAA==.',
Am='Amakuagsak:BAAANQADCggIGwAAAA==.Amicus:BAAANQAECgIJAwAAAA==.Ampmage:BAAANQAECgMIBAAAAA==.Ampsdk:BAAANQADCgYIBgAAAA==.',
An='Anthren:BAAANQADCgUIBQAAAA==.Antihose:BAAANQABCgQJBAAAAA==.',
Ap='Apollo:BAAANQAECgUIDQAAAA==.Apolynnæ:BAABNQAECoEZAAIBAAcKShjkDgAYAgABAAcKShjkDgAYAgAAAA==.',
Ar='Araniss:BAAANQAECgUJCQAAAA==.Arasthel:BAAANQADCggIFAAAAA==.Aratrath:BAAANQAECgYIEgAAAA==.Aryasilly:BAAANQAECgUJCgAAAA==.',
As='Asdi:BAAANQADCggIQwAAAA==.Ashe:BAACNQAFFIEHAAICAAQKMR4yBgB8AQACAAQKMR4yBgB8AQA1AAQKgSIAAgIACQrzJP8BALADAAIACQrzJP8BALADAAAA.',
At='Attabubble:BAAANQAECgEJAQABNQAECgkJHQADAPAcAA==.Attaraxia:BAABNQAECoEdAAMDAAkK8BzoFgDxAgADAAkK8BzoFgDxAgACAAEK7Qx6WAA9AAAAAA==.',
Au='Aurelith:BAAANQADCgIIBAAAAA==.',
Av='Aviarra:BAAANQABCgYICAAAAA==.',
Ay='Ayroon:BAAANQADCgUJCAAAAA==.',
['Aé']='Aéquítas:BAAANQAECgIIAgAAAA==.',
Ba='Bamfbutcher:BAAANQAECgUICAAAAA==.Barent:BAAANQADCgYIDAAAAA==.Barrimen:BAAANQAECgYJDwAAAA==.Bartolomew:BAAANQAECgUJCwAAAQ==.Bartonella:BAAANQADCgIIAgABNQAECgEJAQAEAAAAAA==.',
Be='Bedemere:BAAANQAECgQJCgAAAA==.Beepers:BAABNQAECoEVAAIDAAcKuA1nXQDWAQADAAcKuA1nXQDWAQAAAA==.Behodahlia:BAAANQAECgQJBAAAAA==.Belfie:BAAANQAECgUJBQAAAA==.Berrylla:BAAANQADCgIIAgAAAA==.',
Bi='Bigdemon:BAAANQAECgIJAQAAAA==.Bigmakk:BAAANQAECgUJDAAAAA==.Bimzelx:BAAANQAECgIJAgAAAA==.Bipolar:BAAANQAECgQJBAAAAA==.Bitterblood:BAAANQAECgQJCgAAAA==.',
Bl='Blastgamer:BAAANQAECgMJAwAAAA==.Blondebeard:BAAANQAECgcJEQAAAA==.',
Bo='Booshi:BAAANQAECgIIAgAAAA==.Bowiiesenpai:BAAANQAECgYJDQAAAA==.',
Br='Bragontix:BAABNQAECoEXAAIBAAkKwhhhCQCcAgABAAkKwhhhCQCcAgAAAA==.Bravehearth:BAAANQADCgQIBAABNQAECgEIAQAEAAAAAA==.Brewvoke:BAAANQAECgUJCQAAAA==.Brightxan:BAABNQAECoEWAAIFAAgKhgqOHAB1AQAFAAgKhgqOHAB1AQAAAA==.',
Bu='Bubbadruid:BAAANQADCgQIBAABNQAECgcIEQAEAAAAAA==.Bubbahunter:BAAANQAECgcIEQAAAA==.Bubbashaman:BAAANQADCgIIAgABNQAECgcIEQAEAAAAAA==.Buddahspanks:BAAANQADCgcIBQAAAA==.Buddahthai:BAABNQAECoEeAAIGAAkK+RdkXQB1AgAGAAkK+RdkXQB1AgAAAA==.Buddhabum:BAAANQAECgYJBgAAAA==.Budweaver:BAAANQADCgYICQAAAA==.Bus:BAABNQAECoEfAAIHAAkKuyYfAAD+AwAHAAkKuyYfAAD+AwABNQAFFAUIEQAFADUhAA==.Bussdefense:BAAANQADCgYIFAAAAA==.Butterrs:BAAANQAFFAQIBQAAAQ==.Butterz:BAAANQAECgEIAgABNQAFFAQIBQAEAAAAAA==.',
Ca='Caleian:BAAANQAECgUJBQAAAA==.Caloren:BAAANQAECgQIDAAAAA==.Caorou:BAAANQAECgUIBQAAAA==.',
Ch='Charlyte:BAAANQAECgYJDwAAAA==.Charuzu:BAAANQADCgYIBgAAAA==.',
Cr='Crysinia:BAAANQADCgYJBQAAAA==.',
Cu='Cuigy:BAAANQAECgUJCAAAAA==.',
Cy='Cyriene:BAAANQAECgIJAwAAAA==.Cyril:BAAANQAECgIIAgABNQAECgMIBAAEAAAAAA==.',
Da='Dagadin:BAAANQADCggJCAAAAA==.Dalio:BAAANQADCggJCgAAAA==.Danté:BAAANQAECgQIBQABNQAECgYIEAAEAAAAAA==.Daraen:BAAANQADCgYIBwAAAA==.Daylen:BAAANQAECgQJBwAAAA==.',
Dd='Ddeathchura:BAAANQAECgQJBwAAAA==.',
De='Deactrim:BAAANQAECgUICgAAAA==.Dema:BAAANQADCgQIBAAAAA==.Dendrada:BAAANQAECgQJBwAAAA==.Deuce:BAAANQAECgQJBgAAAA==.',
Di='Diogenes:BAAANQADCgQIBAAAAA==.Dizimo:BAAANQAECgMIBQAAAA==.',
Do='Dogmeat:BAABNQAECoEcAAIDAAkKLiF7CgBWAwADAAkKLiF7CgBWAwABNQAFFAUJCgAIACMVAA==.Dotisa:BAAANQADCggICAAAAA==.',
Dr='Dragonlex:BAAANQADCgcIDQAAAA==.Drakeshadows:BAAANQADCgIIAgAAAA==.Drchivago:BAAANQADCgYICgAAAA==.Drdreadful:BAAANQABCgIIAgAAAA==.',
Du='Duna:BAAANQAECgIJAwAAAA==.Dungoofed:BAAANQAECgEJAQAAAA==.Duvidressra:BAABNQAECoEdAAMJAAkKtxPpAwA9AgAJAAgKcRXpAwA9AgAKAAIK1QeezQBwAAAAAA==.',
Dx='Dxmvn:BAAANQADCgQIBQAAAA==.',
Ed='Edisonn:BAABNQAECoEdAAMKAAkKBBf4MwBOAgAKAAgKrhb4MwBOAgALAAUKVBFAIgA7AQAAAA==.',
Eg='Eggies:BAAANQADCggICAABNQAECggIGQAKAM0hAA==.',
El='Eladio:BAAANQADCgIIAgAAAA==.Eldarya:BAAANQAECgUICgAAAA==.Elentisa:BAAANQADCggJGAAAAA==.Elghinn:BAAANQAECgUJDQAAAA==.Elissaria:BAAANQADCgQIBAAAAA==.Ellastrasza:BAAANQAECgYIDwAAAA==.Ellie:BAAANQAECgUJBwAAAA==.Elroy:BAAANQAECgYJEAAAAA==.',
Em='Embold:BAAANQADCggICAABNQAFFAQICQAMAO8gAA==.Emernantus:BAAANQAECgUICwAAAA==.',
Er='Erazar:BAAANQAECgUJEAAAAA==.',
Es='Espy:BAAANQAECgMIBAAAAA==.',
Eu='Eunbyeol:BAAANQAECgYJEAAAAA==.',
Ev='Evee:BAAANQABCgQIBAAAAA==.',
Fa='Faeria:BAAANQAECgQJCAAAAA==.Fatcritties:BAAANQAECgIJBAAAAA==.Fatnchunkydk:BAAANQAECgQJBgAAAA==.',
Fe='Feeblemind:BAAANQAECgQJBgAAAA==.Feli:BAAANQAECgUICAAAAA==.Femboi:BAAANQADCggIDgAAAA==.Fender:BAAANQAECgQJBQAAAA==.',
Ff='Ffugntotems:BAAANQADCgcICwAAAA==.Ffviitifa:BAAANQADCgcICwAAAA==.',
Fi='Fingertoes:BAAANQAECgYIEgAAAA==.Fistbeard:BAAANQADCgUJBQABNQADCgcJCgAEAAAAAA==.Fizzlerazz:BAAANQADCgUIBQAAAA==.',
Fl='Flattulata:BAAANQADCgEJAQAAAA==.Flatulatta:BAAANQAECgUIEgAAAA==.Flyciful:BAAANQAECgIJAgAAAA==.Flyingweasle:BAAANQADCgQIBwAAAA==.',
Fo='Forceed:BAEANQADCgYIDAABNQAECgMIBQAEAAAAAA==.Foxehh:BAAANQABCgUIBwAAAA==.Foxxycontin:BAAANQADCgEIAQAAAA==.',
Fr='Fraternaldk:BAABNQAECoESAAINAAgK6hsvFgC7AgANAAgK6hsvFgC7AgAAAA==.Fraturnal:BAAANQADCgIIAgAAAA==.Freestyle:BAAANQADCgYICgAAAA==.Frodowagons:BAAANQAFFAQIBAAAAA==.Frostpie:BAAANQAECgcJDgAAAA==.',
Fu='Fuglybaby:BAAANQADCgUJCQAAAA==.Fuhenhenka:BAAANQAECgMIAwAAAA==.',
Fw='Fwakos:BAAANQAECgIJAgAAAA==.Fwakow:BAAANQADCgUIBQAAAA==.',
Ga='Gakmonk:BAAANQADCggJDgABNQAECgUIDQAEAAAAAA==.Gakpaladin:BAAANQAECgUIDQAAAA==.Galthul:BAAANQADCgUIBQABNQAECgUJDQAEAAAAAA==.Garfyaz:BAAANQADCgYICwAAAA==.',
Gd='Gdlez:BAAANQADCgcIDAAAAA==.',
Ge='Gethael:BAAANQADCgIIAgAAAA==.',
Go='Goatroth:BAAANQADCggJFgAAAA==.Golorious:BAABNQAECoEWAAIFAAgKIRvlCwBnAgAFAAgKIRvlCwBnAgAAAA==.Goododie:BAAANQAECgIJAwAAAA==.',
Gr='Grayback:BAAANQAECggJBgABNQAECggJFwAOAOwZAA==.Grenas:BAAANQABCgMJBQAAAA==.Grippyweasle:BAAANQAECgYJDAAAAA==.Grovelly:BAAANQABCggIEAAAAA==.Growlius:BAAANQADCgcIBwABNQAECgUJBQAEAAAAAA==.',
Gu='Gudit:BAAANQADCggICAABNQAECgUJBwAEAAAAAA==.Gulaken:BAAANQAECgIJBgAAAA==.Guseva:BAAANQAECgEIAQAAAA==.Guttershark:BAABNQAECoEWAAIPAAcKNR2zFgA+AgAPAAcKNR2zFgA+AgAAAA==.',
Ha='Hafnia:BAAANQAECgEJAQAAAA==.Halliday:BAAANQADCggIHAAAAA==.Haoasakura:BAABNQAECoEaAAIQAAgKECKxHwDuAgAQAAgKECKxHwDuAgAAAA==.Haylo:BAAANQAECgIIBAAAAA==.',
He='Headshop:BAAANQADCgYIBgAAAA==.Healzforfood:BAAANQAECgEJAQAAAA==.Heap:BAAANQAECgMIAwABNQAECgcJEQAEAAAAAA==.Heartlight:BAAANQADCgMJAwAAAA==.Heavyreign:BAAANQADCgQIBwAAAA==.Helicobacter:BAAANQADCgMIAwAAAA==.Hewnoshaqa:BAAANQAECgUICQAAAA==.Hexorcist:BAABNQAECoEYAAIRAAkKzh5vFADjAgARAAkKzh5vFADjAgAAAA==.',
Hi='Hickerbilly:BAAANQADCgEIAQAAAA==.Hitormist:BAAANQAECgcJBwAAAA==.',
Ho='Holyanne:BAAANQADCgQIAgAAAA==.Holyspanks:BAAANQADCgYJBgABNQAECgYJEwAEAAAAAA==.',
Hr='Hruuli:BAAANQADCgYIBgAAAA==.',
Hu='Huntrlicious:BAAANQAECgUJEgAAAA==.Husqvarnna:BAAANQADCgUIBQAAAA==.Huugor:BAAANQAECggJCAAAAA==.',
Ic='Icoulddowork:BAAANQAECgcIBgABNQAECggJDwAEAAAAAA==.',
Id='Idoshiftwork:BAAANQAECggJDwAAAA==.Idunno:BAAANQADCgYICQAAAA==.',
Ih='Ihriel:BAAANQADCgEJAQAAAA==.',
Ik='Ikazuchi:BAAANQAECgQJCQAAAA==.',
Il='Illcutabish:BAABNQAECoEXAAMPAAgKAiCYCQDwAgAPAAcKcySYCQDwAgASAAgKfhcEFAARAgAAAA==.Illtank:BAAANQAECgUJBQAAAA==.',
Im='Imatankin:BAAANQAECgEIAQAAAA==.Imk:BAAANQAECgUIBwAAAA==.',
Io='Iock:BAEANQAECgUIBQAAAA==.',
Ir='Ironarms:BAAANQAECgYJEwAAAA==.',
Is='Ishido:BAAANQADCgYIBgAAAA==.',
Je='Jennypoo:BAAANQAECgYJDAAAAA==.Jessd:BAAANQADCgcJBwAAAA==.',
Ji='Jinuoo:BAAANQADCgQIBAAAAA==.',
Jo='Johnwarrior:BAAANQAECgYIEAAAAA==.Jorrix:BAAANQAECgUJCQAAAA==.',
Ju='Juduspriestt:BAAANQAECgUJCAAAAA==.',
Jy='Jynaxa:BAAANQADCgEIAQAAAA==.',
['Jä']='Jägermeister:BAAANQADCgYJDAAAAA==.',
Ka='Kaaeko:BAAANQAECgUJCwAAAA==.Kalerito:BAAANQAECgUJDQAAAA==.Kallythea:BAAANQADCggICAAAAA==.Kardie:BAAANQADCgQIBAABNQAECgUJEAAEAAAAAA==.Karl:BAAANQAECgIIAgAAAA==.Kaserr:BAACNQAFFIEOAAMSAAUKExftAgDMAQASAAUKjBXtAgDMAQAPAAIKkxcEBwC0AAA1AAQKgSUAAxIACQotJdoDAEYDABIACAq4JdoDAEYDAA8AAwqII6A2ACcBAAAA.Kayserdh:BAAANQAECgUICAAAAA==.Kazaf:BAAANQAECgQIDgAAAA==.',
Ke='Kebru:BAAANQAECgUICwAAAA==.Keitrek:BAAANQAECgUJDQAAAA==.Kelthias:BAAANQADCgYJDQAAAA==.Kerwîck:BAAANQAECgYIBgAAAA==.Keyen:BAAANQAECgUIBQAAAA==.',
Ki='Kibalion:BAAANQAECgUJBQAAAA==.Killbent:BAAANQADCggJHAAAAA==.Kinnky:BAAANQAECgUJBwAAAA==.Kino:BAAANQAECgMIBAAAAA==.Kitn:BAAANQABCgQIBAAAAA==.Kityana:BAAANQADCgIIAgAAAA==.',
Kp='Kpop:BAAANQADCgIIAwAAAA==.',
Kr='Krasdan:BAAANQAECgIIAgAAAA==.Kreettip:BAAANQAECgUJDQAAAA==.Krispy:BAAANQADCgcJBwABNQAECgYIEgAEAAAAAA==.',
Ks='Ksp:BAAANQADCgQIBQAAAA==.',
Ku='Kugamoo:BAABNQAECoEVAAMIAAcK9xIoLwDuAQAIAAcK9xIoLwDuAQATAAQK+QdPNQDFAAAAAA==.Kulgan:BAABNQAECoEaAAIUAAkKnxmEHgCYAgAUAAkKnxmEHgCYAgAAAA==.Kurgen:BAAANQAECgIJAwAAAA==.Kuroda:BAAANQAECgIIAwAAAA==.Kurolucifer:BAAANQADCgYIBgAAAA==.',
Ky='Kylex:BAAANQAECgMJBAAAAA==.',
La='Lamiah:BAAANQAECgIIAgAAAA==.Lauadia:BAAANQAECgIJAgAAAA==.',
Lc='Lckdown:BAAANQAECggICwAAAA==.',
Le='Legomyegolas:BAAANQADCgYJBgAAAA==.',
Li='Lightsocket:BAAANQADCgYJCAABNQAECgIJAgAEAAAAAA==.Livingkntpib:BAAANQADCggICAAAAA==.',
Lo='Lockedout:BAAANQADCgQJBAABNQAECgcJEAAEAAAAAA==.Loden:BAAANQAECgcIDAAAAA==.Lodez:BAAANQAFFAEJAQAAAA==.Loktarhogar:BAAANQAECgUIBQAAAA==.Lostadin:BAAANQADCgIIAgAAAA==.Lovi:BAAANQAECggIDwAAAA==.',
Lu='Luckyboi:BAAANQAECgcIEQAAAA==.Lumeria:BAAANQAECgMIBQAAAA==.Lumina:BAAANQAECgUIDAAAAA==.Lusciifi:BAACNQAFFIEIAAMQAAUKYhPDCAD4AAAQAAMKPRXDCAD4AAAFAAIKmhCeBQCQAAA1AAQKgScAAxAACQqaJDgGAK4DABAACQqaJDgGAK4DAAUABgpaIhINAFACAAAA.',
Ly='Lykie:BAABNQAECoEYAAIFAAcKWBkkEgD4AQAFAAcKWBkkEgD4AQAAAA==.Lynxic:BAAANQADCgQJBwABNQADCgUIBQAEAAAAAA==.Lyone:BAAANQAECgQJCQAAAA==.',
['Lä']='Lävey:BAAANQADCgEIAQAAAA==.',
['Lú']='Lúvaa:BAAANQAECgcIEwAAAA==.',
Ma='Macavity:BAAANQADCgMJAwAAAA==.Madmanmike:BAAANQADCgIIAgAAAA==.Magalis:BAAANQAECgQJBwAAAA==.Magicwoman:BAAANQAECgIIAgAAAA==.Magikkisback:BAAANQAECgEIAQAAAA==.Magsh:BAAANQADCggIIAAAAA==.Mandorius:BAAANQAECgQIBgAAAA==.Maphra:BAAANQADCggJCAABNQAECgcJBwAEAAAAAA==.Marcos:BAAANQADCgIIAgAAAA==.Marl:BAAANQADCgQIBAAAAA==.Marvolo:BAAANQAECggIDgABNQAECggJFwAOAOwZAA==.Maverickdog:BAABNQAECoEdAAQCAAgKdh7HHAALAgACAAcKQBvHHAALAgAVAAQKXBRQCAAkAQADAAMKayTBpwAPAQAAAA==.',
Mc='Mchammerwork:BAAANQAECgQJBQABNQAECggJDwAEAAAAAA==.',
Me='Mechunter:BAAANQADCgYIBgABNQAECgIIAgAEAAAAAA==.Meekzz:BAAANQAECgQJBAAAAA==.Meeshie:BAABNQAECoEjAAQUAAgKgg5HTgCjAQAUAAgKIw5HTgCjAQAMAAQKdQlnOADWAAAWAAIK5QXtFgBaAAAAAA==.Melodrop:BAAANQAECggIBQAAAA==.',
Mi='Mihawk:BAAANQADCgEIAQABNQAECgYIEgAEAAAAAA==.Mikexfire:BAAANQAECgUJCgAAAA==.Mikuzume:BAAANQADCgYIBgAAAA==.Mildchaos:BAAANQAECggJAQAAAA==.Mishima:BAAANQAECggJCAAAAA==.Misspell:BAAANQADCggJFAAAAA==.Miznewbooty:BAABNQAECoEVAAIMAAcK3BBCHQDhAQAMAAcK3BBCHQDhAQAAAA==.',
Mo='Moochella:BAAANQAECgUJCAAAAA==.Moojestic:BAAANQADCggIDwAAAA==.Moonq:BAAANQAECgQJBwAAAA==.Moosie:BAAANQAECgUJDAAAAA==.Mooska:BAAANQAECgEIAQABNQAECgUJDAAEAAAAAA==.Moxflip:BAAANQAECgcJCAAAAA==.Mozzers:BAAANQADCgcIBwAAAA==.',
Mu='Muertenegra:BAAANQADCgUIBQABNQAECgUJCAAEAAAAAA==.Muffy:BAAANQAECgQJCQAAAA==.Muln:BAAANQADCggIBwAAAA==.Murlouh:BAAANQADCgQIBAAAAA==.',
My='Myllakura:BAAANQAECgMIBgAAAA==.Mythnarra:BAABNQAECoEZAAIOAAkK+SCcBgBOAwAOAAkK+SCcBgBOAwAAAA==.',
['Mä']='Mäomäo:BAAANQADCgMIAwAAAA==.',
['Mí']='Mísanthrope:BAAANQADCgQIBAABNQADCggJFgAEAAAAAA==.',
Na='Nadíne:BAABNQAECoEWAAIGAAYK1g+QvACJAQAGAAYK1g+QvACJAQAAAA==.Nanukimon:BAAANQAECgIJAwAAAA==.Narawe:BAAANQADCgIJAgAAAA==.Naughtgelic:BAAANQADCgYJCQAAAA==.',
Ne='Nedgamingttv:BAEANQAECgMIBQAAAA==.Nekrimah:BAAANQAECgYIBgAAAA==.Nerph:BAAANQADCgQJBAAAAA==.Nevaera:BAAANQADCgYIBgAAAA==.',
Ni='Ni:BAAANQAECgQIBAAAAA==.Nick:BAACNQAFFIEIAAMNAAQKLA/+AwBNAQANAAQKLA/+AwBNAQAXAAEKkQKUGQBCAAA1AAQKgSUAAg0ACQrWJJsEAJoDAA0ACQrWJJsEAJoDAAAA.Nikor:BAEANQAECgIJAgAAAA==.',
Nm='Nmue:BAAANQADCgIIAgAAAA==.',
No='Nokorii:BAAANQAECgIJAwAAAA==.Nomecoma:BAAANQAECgUJCAAAAA==.Nonok:BAAANQADCgIIAgAAAA==.Noshom:BAAANQAECgUJDAAAAA==.Notches:BAAANQADCgEIAQAAAA==.',
Ns='Nsyncrogue:BAAANQADCgYJBgAAAA==.',
Ny='Nymful:BAAANQAECgUJBgAAAA==.',
['Nè']='Nèlo:BAAANQAECgUICQAAAA==.',
Ob='Obianstrider:BAAANQADCgYIEQAAAA==.',
Oc='Oceanspell:BAABNQAECoEYAAIYAAUKXyJ4BwDqAQAYAAUKXyJ4BwDqAQAAAA==.',
Og='Oggleboggle:BAAANQADCgEIAQAAAA==.',
Ol='Oldbuse:BAABNQAECoEVAAMZAAcK0R1BCgByAgAZAAcK0R1BCgByAgAaAAEK1Bg2zQBGAAAAAA==.',
On='Onlytoez:BAAANQAECgEJAQABNQAECggIIwAUAIIOAA==.',
Or='Orave:BAAANQAECgIJAgAAAA==.Oromë:BAAANQABCgQIBAAAAA==.Orzik:BAAANQADCgcIBwAAAA==.',
Os='Ostena:BAAANQAECgUJBQAAAA==.Osteole:BAAANQAECgQJCgABNQAECgUJBQAEAAAAAA==.',
Ou='Oulawdpriest:BAABNQAECoEgAAMMAAkK0hZcEACaAgAMAAkK0hZcEACaAgAUAAEKYxPcqAA5AAAAAA==.',
Ov='Overture:BAAANQADCgQIBgAAAA==.',
Ow='Owthatburns:BAAANQADCgYIBgAAAA==.',
Pa='Pakszdude:BAAANQADCgUIBQAAAA==.Pandamonious:BAAANQADCggICAABNQAECgEIAgAEAAAAAA==.Papawoof:BAAANQADCgQJBQABNQAECgkJGAARAM4eAA==.Parkour:BAAANQADCggIGgAAAA==.Paullyfists:BAAANQAECgcJEQAAAA==.',
Pi='Pintobeans:BAAANQAECgEIAgAAAA==.',
Po='Popkorn:BAACNQAFFIEMAAMbAAUKeB/GAAAtAQAOAAQKgxqUBABwAQAbAAMKViDGAAAtAQA1AAQKgSYAAw4ACQo0JmkAAPgDAA4ACQobJmkAAPgDABsAAgptImYSANMAAAAA.Popkourne:BAAANQAECggICgABNQAFFAUJDAAbAHgfAA==.Poplocks:BAAANQADCgYICgAAAA==.Porrana:BAAANQAECgIJAgAAAA==.Powaqa:BAAANQAECgQIBgAAAA==.',
Pr='Praetorian:BAAANQAECgYICwAAAA==.Praxxus:BAAANQADCgYIBgAAAA==.',
Pu='Purify:BAAANQAFFAIIAgAAAA==.',
Qm='Qmen:BAAANQADCgIIAgAAAA==.',
Qu='Quasient:BAAANQAECgcJEgAAAA==.Quethelos:BAAANQADCgcJGwAAAA==.Quickbrew:BAAANQADCgQIBAAAAA==.Quickspell:BAAANQAECgcJEAAAAA==.',
Ra='Raalcar:BAAANQAECgMIAwAAAA==.Raedyyn:BAAANQAECgMIAwAAAA==.Ragarninn:BAAANQADCgcICwABNQAECgkJHQARAE0kAA==.Ragendecay:BAAANQAECgUJCAAAAA==.Ragequits:BAACNQAFFIEZAAIcAAcKaiSpAADTAgAcAAcKaiSpAADTAgA1AAQKgR8AAhwACQpBJrIFALIDABwACQpBJrIFALIDAAAA.Ragewar:BAAANQABCgcJDAAAAA==.Rakshassa:BAAANQAECgMIBAAAAA==.Rawkphyst:BAAANQADCgQIAgAAAA==.Razrscale:BAAANQAECgEIAQAAAA==.',
Re='Redhuntsman:BAAANQADCgYJFwAAAA==.Regrow:BAAANQADCgcIBwABNQAECgIIAgAEAAAAAA==.Reska:BAAANQAECgEIAQAAAA==.',
Rh='Rholdentodor:BAAANQADCgEIAQABNQAECgcIGQAGACQRAA==.',
Ri='Rindorin:BAAANQAECgUJBgAAAA==.Ritarepulsa:BAAANQADCgYIDAAAAA==.',
Ro='Rohra:BAAANQAECgUICwAAAA==.Rozynwen:BAAANQADCgYICwAAAA==.',
Ru='Ruah:BAAANQABCgMIAwAAAA==.Rubmytoes:BAAANQAECgEJAQAAAA==.Rukuna:BAAANQAECgEIAQAAAA==.Runecast:BAAANQAECgcIEgAAAA==.',
Sa='Saelyrinth:BAAANQADCgUIBQABNQAECgMIBQAEAAAAAA==.Salamence:BAAANQADCggJDgABNQAECgUJCwAEAAAAAQ==.Sambor:BAAANQAECggIBwAAAA==.Sarapheena:BAABNQAECoEXAAIRAAgK4x06GwCzAgARAAgK4x06GwCzAgAAAA==.Sarouk:BAAANQAECgcIEQAAAA==.Satanbomb:BAAANQADCgQIBAAAAA==.Satansbride:BAAANQADCgQJBAABNQAECgEIAQAEAAAAAA==.Saterli:BAABNQAECoEXAAMUAAkKPxZDIgCBAgAUAAkKPxZDIgCBAgAMAAEKZQLRWAAqAAAAAA==.Saturno:BAAANQAECgEIAQAAAA==.Saucypirate:BAAANQAECgUICgAAAA==.Sayygurl:BAAANQAECgIJAwAAAA==.',
Sc='Scalvert:BAABNQAECoEZAAIGAAcKJBHolwDcAQAGAAcKJBHolwDcAQAAAA==.Scalypanda:BAAANQAECgcJEQAAAA==.Scamander:BAABNQAECoEXAAIOAAgK7Bk2FACBAgAOAAgK7Bk2FACBAgAAAA==.Scoobs:BAAANQADCgQIBAABNQADCggJGAAEAAAAAA==.Sculi:BAAANQAECggJDAAAAA==.',
Se='Seiishiro:BAAANQADCggIFQAAAA==.Seldon:BAAANQAECgQJBgAAAA==.Senyor:BAAANQAECggIDwAAAA==.Seradormi:BAAANQADCgMJAwAAAA==.Seraphiel:BAAANQAECgIIAgABNQADCgIJAgAEAAAAAA==.',
Sh='Shadowpaksz:BAAANQAECgUJCAAAAA==.Shadowsneak:BAAANQAECgIIBAAAAA==.Shadowvixen:BAAANQAECgEIAQAAAA==.Shaelistra:BAAANQAECgQJBgAAAA==.Shalilama:BAABNQAECoEdAAIRAAkKTSSmAgCnAwARAAkKTSSmAgCnAwAAAA==.Shamanana:BAAANQAECgcIBwAAAA==.Shamboli:BAAANQADCggIEAAAAA==.Shamirah:BAAANQADCgcJCQAAAA==.Shaï:BAAANQAECgQJBAAAAA==.Shenderp:BAAANQAECgEIAgAAAA==.Shinerbock:BAAANQAECgYJEAAAAA==.Shockitti:BAAANQAECgIIAgAAAA==.Shtark:BAAANQADCgcIEwAAAA==.',
Si='Silshara:BAABNQAECoEVAAIdAAkKpgvoFQDxAQAdAAkKpgvoFQDxAQAAAA==.Silverjustis:BAAANQAECgQJBwAAAA==.Siwe:BAAANQAECgUJDQAAAA==.Six:BAAANQAECgIIAgABNQAECgMJAwAEAAAAAA==.',
Sk='Skip:BAAANQADCgMIAwAAAA==.Skribblez:BAABNQAECoEaAAMQAAgKtRjbPwBTAgAQAAgKtRjbPwBTAgAeAAQKJBTEhAAGAQAAAA==.Skyanna:BAAANQADCgYIDgAAAA==.',
Sl='Slackback:BAAANQAECggIBwABNQAECgkJGQAaAOkbAA==.Sloop:BAAANQADCgUICgAAAA==.Sloot:BAAANQAECgcJCAAAAA==.',
Sn='Sneasel:BAAANQAECgMIBAABNQAECgQIBAAEAAAAAA==.Snoogins:BAAANQADCgUJCQABNQAECgEIAQAEAAAAAA==.',
So='Sockszz:BAABNQAECoEZAAIfAAgKeiTnAQBlAwAfAAgKeiTnAQBlAwAAAA==.Songblade:BAAANQABCgUIBgAAAA==.Soulsy:BAABNQAECoEaAAIQAAcKyiFeLQClAgAQAAcKyiFeLQClAgAAAA==.Soulvalk:BAAANQADCgQIBAAAAA==.Sourmagic:BAAANQAECgUICQAAAA==.',
Sp='Splendorae:BAAANQAECgcJEwAAAA==.Sprints:BAAANQAECgUJDgAAAA==.Spritz:BAABNQAECoEXAAMRAAgKZB3DGwCvAgARAAgKZB3DGwCvAgAaAAEKHB2JyQBPAAAAAA==.Sprucewillis:BAAANQADCgMIAwABNQAECgEIAQAEAAAAAA==.Spyderelite:BAAANQAECgYJEgAAAA==.',
Sq='Squirrel:BAAANQAECgUIDAAAAA==.',
Ss='Ssuperss:BAAANQADCgQICgAAAA==.',
St='Stabbot:BAAANQAECgMJAwABNQAECgcJBwAEAAAAAA==.Starblood:BAAANQABCgMIAwAAAA==.Starspeaker:BAAANQADCggIFAAAAA==.Stompmyballs:BAAANQAECgYIEgABNQAFFAcIGQAcAGokAA==.Stoogotz:BAAANQADCgIIBAAAAA==.Studlebane:BAAANQADCgYIBgABNQAECgMIBQAEAAAAAA==.Studlepalm:BAAANQAECgMIBQAAAA==.',
Su='Sundaresh:BAAANQADCgEIAQAAAA==.Sunwing:BAABNQAECoEUAAIUAAcKiCGqIgB+AgAUAAcKiCGqIgB+AgAAAA==.Supersheep:BAAANQAECgUJCAAAAA==.Suvien:BAAANQADCgcICgAAAA==.',
Sy='Sylvarian:BAAANQAECgUJBwAAAA==.Sylvinna:BAAANQADCggIFQAAAA==.',
Ta='Tagda:BAAANQADCggJCAAAAA==.Takeurland:BAAANQADCgEIAQAAAA==.Taterdotz:BAAANQAECgIIAgAAAA==.Tatortwats:BAAANQAFFAEIAwAAAA==.Taxdeeznutz:BAAANQADCgUIBQAAAA==.',
Te='Tengrit:BAAANQADCgIIAgAAAA==.Tephine:BAAANQAECgYJEwAAAA==.Tepicoyotl:BAAANQAECgcIEAAAAA==.',
Th='Thaymor:BAAANQADCgcJCgAAAA==.Thebigkitti:BAAANQADCgEIAQAAAA==.Thelonecone:BAABNQAECoEiAAIgAAkKHSStAgCgAwAgAAkKHSStAgCgAwAAAA==.Theodor:BAAANQAECgIJAgAAAA==.Theoganth:BAAANQAECgMIBAABNQAECgYIEAAEAAAAAA==.Theraphee:BAAANQADCgcJFwAAAA==.Therym:BAAANQADCgEIAQABNQAECggIFwAXAGMOAA==.Thomwizard:BAAANQADCggIFAAAAA==.Thormorn:BAAANQADCggIEwAAAA==.Thunnha:BAAANQADCgYJEwAAAA==.',
Ti='Tierali:BAAANQADCgYICgAAAA==.Tio:BAAANQADCggIGQAAAA==.',
To='Toastedsushi:BAAANQADCgYIBgAAAA==.Toofwess:BAAANQAECgIJAgABNQAECgcJBwAEAAAAAA==.Torrinchaos:BAAANQADCgQJBAAAAA==.Tosala:BAAANQAECgMIBQAAAA==.Totemkiller:BAAANQAECgQIBwAAAA==.',
Tr='Traael:BAAANQAECgYJBwAAAA==.Treesap:BAABNQAECoEUAAIhAAgKUR+2AgDlAgAhAAgKUR+2AgDlAgAAAA==.Trinityeve:BAAANQAECgEJAgAAAA==.Trmz:BAAANQAECgYICgAAAA==.Trnzlock:BAAANQAECgUICwABNQAECgYICgAEAAAAAA==.Trîggêr:BAAANQADCgYIBgAAAA==.',
Tu='Tulanii:BAAANQADCgIIAgAAAA==.Tularana:BAAANQAECgEIAQABNQAECgcJGQABAEoYAA==.Tumble:BAAANQAECgMJBAAAAA==.',
Tw='Twignberryz:BAAANQAECgEIAQAAAA==.Twinkie:BAAANQAECgUIBgAAAA==.Twodogz:BAAANQAECgQJCAAAAA==.',
Ty='Tyious:BAABNQAECoEYAAMgAAgKiRX5HAAWAgAgAAgKSRT5HAAWAgANAAQK0BEjbwCwAAAAAA==.Tyndara:BAAANQAECgQJBgAAAA==.',
Ub='Ubavoke:BAAANQAECgEIAQAAAA==.',
Uk='Ukita:BAABNQAECoEcAAIQAAgK1yBvJgDIAgAQAAgK1yBvJgDIAgAAAA==.',
Ur='Ursane:BAABNQAECoEYAAMcAAgKFBIgXAD/AQAcAAgKFBIgXAD/AQAiAAQK1Ai7FQC0AAAAAA==.Ursully:BAAANQAECgQJBgAAAA==.',
Uz='Uzi:BAAANQAECgUJCgAAAA==.',
Va='Valentíne:BAAANQADCgYIDAAAAA==.Valhalla:BAAANQAECgMIAwAAAA==.Vanncint:BAAANQAECgIIAgAAAA==.Vashie:BAAANQADCgYICgAAAA==.',
Ve='Vexus:BAABNQAECoEZAAIaAAkK6RsEGgDbAgAaAAkK6RsEGgDbAgAAAA==.',
Vi='Vixly:BAAANQADCgUJDgAAAA==.',
Vl='Vladios:BAAANQAECgUICgAAAA==.',
Vo='Voidmommy:BAAANQADCgYJBgABNQAECgMIBQAEAAAAAA==.Vordarian:BAAANQAECgEIAQAAAA==.',
Wa='Walolas:BAAANQADCggIFQAAAA==.Warlokholmes:BAAANQADCgIIAgAAAA==.Warrax:BAAANQADCgcIEAAAAA==.Watchmeburst:BAAANQADCgYICAAAAA==.',
Wh='Whaler:BAAANQAECggIBwAAAA==.',
Wi='Windeagle:BAAANQADCgQIBAABNQAECgUJBQAEAAAAAA==.Windowskey:BAAANQAECgYIAwABNQAECggICwAEAAAAAA==.',
Wu='Wuzntmyfault:BAAANQAECgIIAgAAAA==.',
Wy='Wyldfyire:BAAANQAECgUJCAAAAA==.',
Xa='Xaven:BAAANQAECgMJBQAAAA==.Xavenuke:BAAANQADCgcJDQABNQAECgMJBQAEAAAAAA==.',
Xi='Xiaotao:BAAANQAECgMIAwAAAA==.',
Xt='Xtraxtra:BAAANQADCggICQABNQAECgYIEgAEAAAAAA==.',
Yo='Yoga:BAAANQAECgIIAgAAAA==.',
Za='Zabra:BAAANQADCggJFQAAAA==.Zahshia:BAAANQAECgIJAgAAAA==.Zaldina:BAAANQADCgIIAgAAAA==.Zathaeus:BAABNQAECoEaAAIOAAkKARnFDgDKAgAOAAkKARnFDgDKAgAAAA==.Zaylian:BAABNQAECoEZAAIjAAgKgRkDGgBZAgAjAAgKgRkDGgBZAgAAAA==.Zayragossa:BAABNQAECoEZAAMKAAgKzSG3EgD6AgAKAAgKmyG3EgD6AgALAAIKyB8YOwCxAAAAAA==.Zayrah:BAAANQAECgMIAwABNQAECggIGQAKAM0hAA==.',
Ze='Zeerkk:BAAANQAECgQJCwAAAA==.Zergmark:BAAANQADCgUIBgAAAA==.',
Zi='Zirilian:BAAANQADCgQICAABNQAECgUJCAAEAAAAAA==.',
Zo='Zoomzoom:BAAANQAECgUJBgABNQAECgkJIAAMANIWAA==.Zouris:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.',
Zu='Zulkraa:BAAANQAECgIIAgAAAA==.',
Zy='Zynreth:BAAANQADCgIIAgAAAA==.',
['Ài']='Àirén:BAAANQAECgcJDQAAAA==.',
['Åb']='Åbon:BAAANQADCgcIEAAAAA==.',
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
