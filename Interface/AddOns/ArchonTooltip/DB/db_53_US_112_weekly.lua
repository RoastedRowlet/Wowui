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

local lookup = {'Unknown-Unknown','Warrior-Arms','Warlock-Destruction','Monk-Windwalker','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Hunter-BeastMastery','Warlock-Demonology','Paladin-Holy','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Warlock-Affliction','Hunter-Marksmanship','DeathKnight-Blood','DemonHunter-Vengeance','Priest-Discipline','Monk-Brewmaster','Druid-Guardian','Evoker-Devastation','Hunter-Survival','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-10-13',data={Ak='Akaidia:BAAANQAECggIBgAAAA==.',
Al='Alckmin:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQAECgYICAAAAA==.Allysaun:BAAANQAECgEIAQAAAA==.',
Am='Amaurra:BAAANQABCgQIBAAAAA==.Amorina:BAAANQAECgYIDgAAAA==.',
An='Anda:BAAANQAECgEIAQAAAA==.Andill:BAAANQAECgIIAgAAAA==.Andromeda:BAAANQAECgUIBQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAACNQAFFH8GAAICAAMKghS8IADzAAACAAMKghS8IADzAAA1AAQKfx8AAgIACQp9HZ5NAJ0CAAIACQp9HZ5NAJ0CAAAA.Angrygnome:BAABNQAECn8jAAIDAAkKaBpXAwAQAwADAAkKaBpXAwAQAwAAAA==.Angélique:BAAANQAECgYIBgABNQAFFAMIBgACAIIUAA==.Anieros:BAAANQAECgEIAgABNQAFFAEIAgABAAAAAA==.',
Ar='Arai:BAAANQADCgIIAgAAAA==.Arax:BAAANQAECgQIBgAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAAANQAECgYIDAAAAA==.Armâgeddon:BAABNQAECn8fAAICAAkK+B6WQgC/AgACAAkK+B6WQgC/AgAAAA==.Arrokoth:BAAANQADCggIDwAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.Artistic:BAAANQADCgMIAwAAAA==.',
At='Atropós:BAAANQAECgYIDwAAAA==.Attachedplag:BAAANQAECgUIDQAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQADCgMIBQAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIAwAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBgAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgEIAQABNQAECgkJLAAEAO8fAA==.',
Be='Beardedyeti:BAAANQABCgQIBAAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECn8fAAIFAAgKLxpsLAA2AgAFAAgKLxpsLAA2AgAAAA==.Bernese:BAAANQAECgQIBAAAAA==.Berunma:BAAANQAECgYIDwAAAA==.',
Bh='Bhain:BAAANQAECgQIBAAAAA==.',
Bi='Bileshots:BAAANQAECgYIBgAAAA==.Biowolf:BAAANQAFFAIIAwAAAA==.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgIIAgAAAA==.',
Bj='Bjoren:BAABNQAECn8oAAMGAAgK7yIeFwAaAwAGAAgK7yIeFwAaAwAHAAEKAAD5lAAKAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.Bloodbaron:BAAANQAECgIIAgABNQAECgUIDAABAAAAAA==.',
Bo='Bootiebang:BAABNQAECn8XAAIIAAYKPAbwLwA7AQAIAAYKPAbwLwA7AQAAAA==.Bootycaall:BAAANQADCgcIDgAAAA==.Boxxie:BAAANQADCgcIDgAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgEIAQAAAA==.',
Bu='Bucknekkid:BAAANQAECgUIBQAAAA==.Buckwhild:BAABNQAECn8aAAMGAAkK3xbjMgCZAgAGAAkK3xbjMgCZAgAHAAEKAAAAiQAfAAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECn8sAAMJAAgKCyCcCwDdAgAJAAgKCyCcCwDdAgAKAAEKAABZmgE3AAAAAA==.Canadaisheal:BAAANQAECgQICgAAAA==.Catslol:BAAANQADCgEIAQAAAA==.',
Ce='Cerñuñños:BAAANQAECgEIAQAAAA==.Cesàrè:BAAANQAECgQIDgAAAA==.',
Ch='Chahra:BAAANQAECgUIBQAAAA==.Chamuki:BAAANQAECggICgABNQAFFAUIEwALALEWAA==.Cheesecake:BAAANQADCgMIAwABNQAFFAMIBgACAIIUAA==.Chuubak:BAAANQAECggICAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAAANQAECgQICAAAAA==.',
Co='Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAABNQAECn8UAAIMAAYKiBVmGQCYAQAMAAYKiBVmGQCYAQAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECn8cAAMCAAcKEh4leQAoAgACAAcK+x0leQAoAgANAAQKWxgoHgDMAAAAAA==.',
Da='Dagby:BAAANQADCgcIGwAAAA==.Dandi:BAAANQAECgIIAgAAAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkscorp:BAAANQADCgIIAgAAAA==.Darkwolf:BAAANQAECgQICAAAAA==.Darnuus:BAABNQAECn8gAAMOAAkKixtXKADBAgAOAAkKixtXKADBAgAPAAIKBQeXFQFcAAAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAABNQAECn8cAAMQAAcK0wmIPQAyAQAQAAcK0wmIPQAyAQALAAYKCAd+cAADAQABNQAECggIGQARACMFAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAABNQAECn8UAAISAAgKPhTgbgAOAgASAAgKPhTgbgAOAgAAAA==.Dellin:BAAANQAECgYIEwAAAA==.Demeco:BAEANQAECgUJBwABNQAFFAcIEwATAMsaAA==.Demondots:BAAANQAECgUIBwAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.',
Do='Doozydruid:BAAANQAECgYJEQAAAA==.Dorozh:BAAANQAECgYICAAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonstorm:BAAANQADCgEIAQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAABNQAECn8XAAIGAAYKzxaahQCBAQAGAAYKzxaahQCBAQAAAA==.Dreadpally:BAAANQADCgYJCgABNQADCgYICgABAAAAAA==.Dreco:BAAANQAECgUIDAAAAA==.Driver:BAEANQAECggICAAAAA==.Drtydhn:BAAANQABCgMJAwAAAA==.Druuzak:BAABNQAECn8cAAIUAAgKXQ6zDgC9AQAUAAgKXQ6zDgC9AQAAAA==.Dryconias:BAABNQAECn81AAIKAAkKxxxhQgDKAgAKAAkKxxxhQgDKAgAAAA==.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAAANQAECggIDwABNQAECgkJFQAGAPYUAA==.Dunkelzhan:BAABNQAECn8hAAIVAAcKSxan1ADaAQAVAAcKSxan1ADaAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUIDQAAAA==.',
Dy='Dyana:BAAANQAECgYICAAAAA==.',
Dz='Dz:BAABNQAECn8wAAMTAAkKiiOcBACrAwATAAkKiiOcBACrAwAKAAYKDA448QAzAQAAAA==.',
['Dø']='Dømimømmÿ:BAAANQAECgMIAwAAAA==.',
Ec='Ecobessie:BAAANQADCgYICgAAAA==.Ecowolf:BAAANQADCgYICgABNQADCgYICgABAAAAAA==.',
Ed='Edlund:BAAANQAECgYIDgAAAA==.',
El='Electricfun:BAAANQAECgEIAQAAAA==.Ellenaim:BAAANQAECgUIBQAAAA==.Elvy:BAABNQAECn8nAAILAAgKPhiHNgA0AgALAAgKPhiHNgA0AgAAAA==.',
En='Enngin:BAAANQAECgMIAwAAAA==.Enroks:BAABNQAECn8nAAQPAAgK+BGNYgD2AQAPAAgK+BGNYgD2AQAOAAYKZhmmgACGAQAWAAEKAABrNgAzAAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAABNQAECn8fAAMQAAgKzxDJKwC6AQAQAAgKzxDJKwC6AQALAAUKlwQ+hAC7AAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAAANQAFFAEIAgAAAA==.',
Fa='Fabulousness:BAAANQAECgYICwAAAA==.Fathur:BAAANQADCggICwAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUICwAAAA==.Furussy:BAAANQADCgcIBwAAAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Gamboslice:BAABNQAECn8eAAIFAAkKJxV1LAA2AgAFAAkKJxV1LAA2AgAAAA==.Garkevon:BAAANQAECgYIEQAAAA==.',
Ge='Gevul:BAABNQAECn8+AAQSAAkKNBt2QgCHAgASAAgKtxt2QgCHAgADAAMKoRH/OADcAAAXAAEKAABWMQAxAAAAAA==.',
Gh='Ghuun:BAAANQAECgUIDAAAAA==.',
Gl='Glep:BAAANQADCggICwAAAA==.Glimmervoid:BAAANQAECgIIAgAAAA==.',
Go='Golland:BAAANQABCgIIAgABNQAECgkJHwAPAAQWAA==.Goob:BAAANQADCgYIBgAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAAANQAECgcIEQAAAA==.Grimero:BAAANQAECggIAgAAAA==.Groinsapper:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Grozny:BAAANQADCgYICgABNQAECgYIEwABAAAAAA==.',
Gu='Gumboslice:BAABNQAECn8uAAIQAAkKcB0lEQDIAgAQAAkKcB0lEQDIAgAAAA==.Gumiho:BAAANQAECgUIBwAAAA==.Gusgus:BAAANQAECgUIDgAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAACNQAFFH8JAAIRAAQKkxEIEQBHAQARAAQKkxEIEQBHAQA1AAQKfyAAAhEACQokIQwTAFIDABEACQokIQwTAFIDAAAA.Habanero:BAAANQAECgYIDwAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECggKIwAYACALAA==.Hammerfist:BAAANQAECgIIAgAAAA==.Hark:BAAANQADCgYIFQAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECgcIGAACABoPAA==.',
He='Helena:BAABNQAECn8kAAMJAAgK9CFECQAHAwAJAAgK9CFECQAHAwAKAAgKNhp7cQBIAgAAAA==.Heliarc:BAAANQADCgYIGwAAAA==.',
Hi='Hidän:BAAANQAECgUIEgAAAA==.Himself:BAAANQADCgUIBQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQADCgYJCgAAAA==.',
Il='Illatix:BAAANQAECgQICAAAAA==.Illustriä:BAAANQAECgQIBgAAAA==.',
In='Insidious:BAABNQAECn8bAAIZAAcKlxzGLwBQAgAZAAcKlxzGLwBQAgAAAA==.',
Ir='Irs:BAAANQAECgcICAAAAA==.',
Is='Isisvane:BAAANQADCgcICQAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECggIIQAUAHEfAA==.Itchymage:BAABNQAECn8hAAMUAAgKcR9pFQBTAQAVAAgK0R3AhAB0AgAUAAQKEh1pFQBTAQAAAA==.',
Iv='Ivyrayne:BAAANQADCggICAAAAA==.',
Ja='Jaganash:BAAANQADCggICwABNQAECgYIDwABAAAAAA==.Jakeofny:BAAANQAECgUICAAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIDQAAAA==.',
Ji='Jighlipuff:BAAANQAECgYIDwAAAA==.Jigs:BAABNQAECn8cAAIRAAcKjwrDtgCSAQARAAcKjwrDtgCSAQAAAA==.Jinxy:BAAANQADCggINwAAAA==.',
Ju='Judgements:BAAANQAECgQIBgAAAA==.Jug:BAAANQADCggIIgAAAA==.Jujutanketh:BAAANQAECgQICgAAAA==.Junebugg:BAAANQAECgUICAAAAA==.',
Ka='Kabøchi:BAAANQAECgUIDQAAAA==.Kafia:BAAANQADCgEJAQAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgUICQAAAA==.Kanaloa:BAAANQAECgUIBwAAAA==.Kaorin:BAAANQAECgEIAQABNQAECgkJJQAOAGUjAA==.Karindis:BAABNQAECn8oAAIaAAgK8iLTAwAYAwAaAAgK8iLTAwAYAwAAAA==.Kathulhu:BAAANQAECgEIAwAAAA==.',
Ke='Kegerator:BAAANQADCgIIAwAAAA==.Keldica:BAAANQAECgUJBQABNQAECgcIEwABAAAAAA==.Kenshan:BAAANQAECgEIAQAAAA==.',
Kh='Khalinor:BAAANQAECgYIDwAAAA==.Khotuhn:BAAANQADCgcIFgAAAA==.',
Ki='Kickazdin:BAABNQAECn8rAAMTAAkKyR5gKADFAgATAAgKRh9gKADFAgAKAAEKAAA4mAE4AAAAAA==.Kiryie:BAAANQAECgIIAgAAAA==.Kitinna:BAAANQAECgQICQAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECn8aAAMOAAcKdBxXTgAnAgAOAAcKdBxXTgAnAgAPAAUKVhFkrwAwAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDAAAAA==.',
Kr='Kraigen:BAAANQAECgYIDQAAAA==.',
Ku='Kunzhut:BAAANQAECgYIDwAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgYIEgAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAAANQADCggIDgABNQADCggINwABAAAAAA==.Laydin:BAABNQAECn8ZAAIRAAgKIwWB/QAEAQARAAgKIwWB/QAEAQAAAA==.',
Lb='Lb:BAABNQAECn8aAAMRAAgKahhkYABTAgARAAgKahhkYABTAgAYAAUKcAtdSgAJAQAAAA==.',
Le='Legzanot:BAABNQAECn8lAAIPAAgKuhNmWgAQAgAPAAgKuhNmWgAQAgAAAA==.Lestrade:BAAANQAECgUIDwABNQAECgkJIAAOAIsbAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAAANQAECgQIEgAAAA==.Lightsfallen:BAABNQAECn8VAAMGAAkK9hSGOgB8AgAGAAkK9hSGOgB8AgAbAAEKuwYuLQApAAAAAA==.Lithia:BAAANQAECgUIBQAAAA==.Littlemo:BAAANQAECgUICwAAAA==.',
Lo='Lohnar:BAAANQAECgUICwAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgcIEgAAAA==.Lucielbaal:BAAANQAECgYIEgAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQADCggIDgAAAA==.Lunareth:BAAANQAECgYICAABNQAECgYIEwABAAAAAA==.',
Ly='Lyrska:BAAANQAECgQICQAAAA==.Lytearrow:BAAANQAECgcIEgAAAA==.',
['Lì']='Lìvíd:BAAANQAECgUICQAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makmobius:BAAANQAECgYIBgAAAA==.Manbearpally:BAAANQAECgEIAQAAAA==.Mannypack:BAAANQAECgQIBQAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Mathau:BAAANQADCgcIFwAAAA==.Maztrix:BAAANQAECgIIAwAAAA==.',
Mc='Mcleary:BAAANQAECgQJBQAAAA==.',
Me='Meldrus:BAAANQAECgcIEgAAAA==.Mending:BAAANQAECgQIBgAAAA==.',
Mi='Miala:BAAANQAECgIIAgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAABNQAECn8YAAIOAAcKKyH9MgCSAgAOAAcKKyH9MgCSAgAAAA==.Miler:BAAANQAECgQIBgAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAABNQAECn8YAAIQAAYKCCS4GQBpAgAQAAYKCCS4GQBpAgAAAA==.Mogryn:BAAANQAECgYIEAAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQAECgEIAQAAAA==.Moonwarriorx:BAAANQADCggIDgAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgMIAwABNQAECgcIHQAEAO8VAA==.Morthok:BAAANQAECgYIDwAAAA==.Mosh:BAABNQAECn8YAAIcAAYKJh5UDQAjAgAcAAYKJh5UDQAjAgAAAA==.',
Mu='Muskelunge:BAAANQADCgcIFQAAAA==.Mustachekick:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAABNQAECn8YAAIRAAcKCBolcgAqAgARAAcKCBolcgAqAgAAAA==.Nafir:BAAANQADCgYIDwAAAA==.Nakky:BAAANQADCggICwAAAA==.Nazgor:BAAANQAECgYIDwAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQADCgYIGwAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECgUIBwAAAA==.',
Oa='Oath:BAAANQAECgYIDwAAAA==.',
Ob='Obscyra:BAAANQAECgYIEwAAAA==.',
Oc='Ochiie:BAAANQADCgcIFgAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgUIBgAAAA==.Oddyeppyep:BAAANQADCgYIEQAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Ol='Olmek:BAACNQAFFH8KAAMCAAUK2wZdGgA8AQACAAUK2wZdGgA8AQANAAEK7AnWBgA9AAA1AAQKfzcAAwIACQp7H2kgADUDAAIACQp7H2kgADUDAA0ABAruD4YeAMgAAAAA.',
Oo='Oochie:BAAANQAECgcIEQAAAA==.Oochiee:BAAANQAECgEIAQAAAA==.Oochiië:BAAANQAECgEIAQAAAA==.',
Op='Oprahwndfury:BAAANQADCggIEgAAAA==.',
Pa='Palanoris:BAAANQABCggIGAAAAA==.Palasades:BAAANQAECgUICwAAAA==.Palelore:BAAANQAECgEIAQAAAA==.Pallydussy:BAAANQAECgMIAwAAAA==.Pallymarc:BAAANQADCgQIBAAAAA==.Pandalorian:BAABNQAECn8fAAIGAAgKVBfYSABIAgAGAAgKVBfYSABIAgAAAA==.Papapumpies:BAABNQAECn8pAAICAAkKRyLhKwAKAwACAAkKRyLhKwAKAwAAAA==.Parlow:BAAANQADCggIGQAAAA==.Pazzo:BAAANQAECgUIBQAAAA==.',
Ph='Pharaa:BAAANQAECgUIDwAAAA==.Philandre:BAAANQADCgUIBQAAAA==.',
Pi='Picoso:BAAANQAECgYIDwAAAA==.Piianna:BAABNQAECn8uAAIGAAkKwBdcMACkAgAGAAkKwBdcMACkAgAAAA==.Pizzaroll:BAABNQAECn8jAAIdAAgKhyC0CADrAgAdAAgKhyC0CADrAgAAAA==.',
Po='Pomégranate:BAAANQADCggICAAAAA==.',
Pu='Puckster:BAAANQADCggICAAAAA==.',
['Pø']='Pøwe:BAAANQADCgMIAwABNQADCggIEgABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIEgAAAA==.',
Qi='Qikkaw:BAAANQAECgUIDwAAAA==.',
Qu='Quantos:BAAANQAECgYIDgAAAA==.',
Ra='Raatha:BAABNQAECn8YAAIKAAcKNxtMlQD0AQAKAAcKNxtMlQD0AQAAAA==.Raganar:BAAANQAECgUIDwAAAA==.Rago:BAAANQAECgcICwAAAA==.Rasz:BAABNQAECn8gAAMRAAYKwRqznwDDAQARAAYKDhqznwDDAQAYAAUK/Q0rSQARAQAAAA==.Rayjean:BAAANQADCgMIAwABNQADCgYIGAABAAAAAA==.',
Re='Regelia:BAAANQADCgcIBwAAAA==.Reider:BAAANQADCggIDwAAAA==.Relmax:BAAANQAECgYICAAAAA==.Rennia:BAAANQAECgIIAgABNQAECggIBgABAAAAAA==.',
Rh='Rhonwynn:BAAANQAECgUIDwAAAA==.',
Ri='Rikershipdwn:BAAANQAECgQIBQAAAA==.Rimrave:BAABNQAECn8YAAICAAcKGg8vwAB3AQACAAcKGg8vwAB3AQAAAA==.Ritobeans:BAAANQADCgYICQAAAA==.',
Rk='Rk:BAABNQAECn8ZAAIeAAYKYQyFIQBBAQAeAAYKYQyFIQBBAQABNQAECggIIgAfAO0JAA==.',
Ro='Robertkenway:BAABNQAECn8iAAIfAAgK7QnRBwDnAQAfAAgK7QnRBwDnAQAAAA==.Roberto:BAAANQADCggICAAAAA==.Rod:BAABNQAECn8fAAIgAAgKORLuGgDPAQAgAAgKORLuGgDPAQAAAA==.Rokte:BAAANQAECgUIBQAAAA==.Rollhots:BAAANQAECgYIDQAAAA==.Rook:BAABNQAECn8YAAMXAAkKIyBpAQBJAwAXAAkKIyBpAQBJAwASAAEK7g7ENgFAAAABNQAECgcIEwABAAAAAA==.Rooke:BAAANQAECgcIEwAAAA==.Rorsh:BAAANQAECgQIBAAAAA==.Rosekenway:BAAANQAECgcIEQABNQAECggIIgAfAO0JAA==.',
Rr='Rratt:BAAANQADCgcIDwAAAA==.',
Ru='Running:BAAANQADCgcICAAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUICwAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICQAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAAANQAECgUIEQAAAA==.',
Se='Sedrick:BAABNQAECn8bAAMKAAcKlBGSvwCXAQAKAAcKlBGSvwCXAQATAAYKWBMqkQBnAQAAAA==.Sekaholic:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQAECgIIAgAAAA==.Seksational:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Sekthyr:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Sekzen:BAAANQADCgUJDgABNQAECgIIAgABAAAAAA==.',
Sh='Shamtune:BAACNQAFFH8HAAIOAAMKtA/pGADPAAAOAAMKtA/pGADPAAA1AAQKfyEAAw4ACQoNFwhIAD8CAA4ACQoNFwhIAD8CAA8AAQqdDqgpATsAAAAA.Sharayman:BAAANQADCgYIGAAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAABNQAECn8cAAIFAAcK6BYDQgC3AQAFAAcK6BYDQgC3AQAAAA==.Shazool:BAABNQAECn8lAAMOAAkKZSNICQB2AwAOAAkKZSNICQB2AwAWAAQK/goQJwDqAAAAAA==.Shevee:BAAANQADCgEIAQAAAA==.Shifterz:BAAANQAECgUIBwAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAAANQAECgYICAAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgQIDAABAAAAAA==.Sindella:BAAANQAECgQIDAAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgQIDAABAAAAAA==.Sinna:BAAANQADCgYICgAAAA==.Sinpriest:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.',
Sk='Skedaddle:BAAANQAECgMIAwAAAA==.',
Sl='Slashgquit:BAABNQAECn8ZAAIZAAcKVCKnLwBRAgAZAAcKVCKnLwBRAgAAAA==.Slumbermist:BAABNQAECn8dAAIEAAcK7xVtLACyAQAEAAcK7xVtLACyAQAAAA==.',
Sn='Snazzi:BAAANQAECgcIEQAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
Sp='Sploob:BAAANQADCgUIBQAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Strawberyy:BAAANQABCgcICQABNQAFFAMIBgACAIIUAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECgQIBwABAAAAAA==.',
Sy='Syndar:BAAANQAECgcIEwAAAA==.Synthetic:BAAANQAECgUICwAAAA==.',
Sz='Szasstaam:BAAANQAECggIAwAAAA==.',
Ta='Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgUIBwAAAA==.',
Te='Tecsaran:BAAANQAECgcICgABNQAECgcIEwABAAAAAA==.Tekis:BAAANQAECgQICAAAAA==.Tensanio:BAAANQADCggIEwAAAA==.',
Th='Thalira:BAAANQAECgYIBwAAAA==.Thalrix:BAAANQAECgUICwAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thetowelie:BAAANQABCgMIAwAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.',
Ti='Tieson:BAAANQAECgEIAwAAAA==.Tinkera:BAAANQADCgcIEQAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Tomcruise:BAAANQABCgUICAABNQAECgIIAgABAAAAAA==.Torridwells:BAAANQAECgUIBQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAAANQAECgUICwAAAA==.Troagstar:BAAANQAECgUICwAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAABNQAECn8iAAMhAAgKVB0JIACWAgAhAAgKVB0JIACWAgAiAAEKAABzawAzAAAAAA==.Tyrmog:BAAANQADCggIFAAAAA==.Tytus:BAAANQABCgcIDwAAAA==.',
Un='Undetha:BAAANQAECgYIDwAAAA==.',
Us='Ushas:BAABNQAECn8fAAMGAAgKHBelUwAkAgAGAAgKHBelUwAkAgAHAAEKAABgggAlAAAAAA==.',
Va='Vaeiane:BAAANQADCggICAABNQAECggIBgABAAAAAA==.Vali:BAAANQADCgcIDQABNQAECgYIDwABAAAAAA==.Valindrea:BAAANQAECgUICwAAAA==.Vasrael:BAAANQAECgYIDwAAAA==.',
Ve='Vel:BAABNQAECn8cAAMiAAgK0AY6NQCUAQAiAAgK0AY6NQCUAQAaAAcK2AG2IAC7AAAAAA==.Velnie:BAAANQAECgMIAwAAAA==.Venvanse:BAAANQAECgEIAQABNQAECgcIGQAVACsPAA==.Verq:BAAANQAECgEIAQAAAA==.Vexen:BAABNQAECn8cAAIiAAcKUBdFLQDUAQAiAAcKUBdFLQDUAQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAABNQAECn8rAAMiAAkKRRsbFwCjAgAiAAkKRRsbFwCjAgAhAAcKeA2sSAB/AQAAAA==.',
Vy='Vynis:BAAANQAECgQIBAABNQAFFAMIBwAOALQPAA==.Vyrahildard:BAABNQAECn8YAAIKAAcK9BrnfwAlAgAKAAcK9BrnfwAlAgAAAA==.',
Wa='Wakkiq:BAAANQADCgYICgAAAA==.Wasteland:BAABNQAECn8sAAIZAAkKwguZWACOAQAZAAkKwguZWACOAQAAAA==.Watermelon:BAABNQAECn8hAAMOAAkKVRKDWAAEAgAOAAkKVRKDWAAEAgAPAAQKJALI/gCLAAABNQAFFAIIBAABAAAAAA==.',
We='Weaselhunter:BAAANQAECggIDAAAAA==.Weasellock:BAAANQAECgMICgABNQAECggIDAABAAAAAA==.Weaselmage:BAAANQAECgEIBwABNQAECggIDAABAAAAAA==.Weaselshammy:BAAANQAECgUIDAABNQAECggIDAABAAAAAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAAANQAECgMIBAABNQAECggIDAABAAAAAA==.Winterhide:BAAANQAECgYIDwAAAA==.Wishbone:BAAANQAECgQICwAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIDgAAAA==.Xanvyr:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.Xaquillis:BAABNQAECn8bAAIZAAkKdA+hTADBAQAZAAkKdA+hTADBAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQADCggICAAAAA==.Xeyvara:BAABNQAECn8YAAIaAAcKwiGRBwCIAgAaAAcKwiGRBwCIAgAAAA==.',
Ya='Yah:BAAANQADCggICwAAAA==.',
Za='Zaravalatha:BAAANQADCgUICQAAAA==.Zarihanna:BAABNQAECn8xAAIVAAgKWxA8vwAEAgAVAAgKWxA8vwAEAgAAAA==.Zariia:BAAANQADCgQIBAAAAA==.Zarsiia:BAAANQAECgQICQAAAA==.Zatima:BAAANQADCgYIBgAAAA==.',
Ze='Zernakk:BAAANQAECgUICgAAAA==.Zestdh:BAAANQAECgUIBwAAAA==.Zestyknight:BAAANQAECgQIBgAAAA==.',
Zi='Zindeshal:BAAANQADCgcICwAAAA==.',
Zo='Zorcunter:BAABNQAECn8gAAIRAAkKbiR3EwBQAwARAAkKbiR3EwBQAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBAAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðonjon:BAAANQADCgcICwAAAA==.',
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
