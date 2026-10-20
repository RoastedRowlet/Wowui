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

local lookup = {'Unknown-Unknown','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','Monk-Windwalker','DeathKnight-Frost','Hunter-BeastMastery','Mage-Arcane','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Druid-Balance','Warrior-Protection','Warrior-Fury','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Mage-Frost','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Affliction','Hunter-Marksmanship','DemonHunter-Vengeance','Priest-Discipline','Monk-Brewmaster','Druid-Guardian','Evoker-Devastation','Hunter-Survival','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=53,date='2026-10-20',data={Ak='Akaidia:BAAANQAECggIBgABNQAECggICAABAAAAAA==.',
Al='Alckmin:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Alderan:BAAANQADCgQIBAAAAA==.Alektophobia:BAAANQAECgYICwAAAA==.Allysaun:BAAANQAECgEIAgAAAA==.',
Am='Amaurra:BAAANQAECgEIAgAAAA==.Amorina:BAAANQAECgcIEQAAAA==.',
An='Ananth:BAAANQAECgEIAQAAAA==.Anda:BAAANQAECgEIAQAAAA==.Andill:BAAANQAECgMIBQAAAA==.Andromeda:BAAANQAECgUIBQAAAA==.Aner:BAAANQADCgEIAQAAAA==.Angellete:BAACNQAFFH8JAAICAAQKoxR1IQDzAAACAAQKoxR1IQDzAAA1AAQKfyIAAgIACgrtHb5OAJ0CAAIACgrtHb5OAJ0CAAAA.Angrygnome:BAABNQAECn8qAAMDAAoKLRtcAwAQAwADAAoKLRtcAwAQAwAEAAMKvwtChwB1AAAAAA==.Angélique:BAAANQAECgYIBwABNQAFFAQICQACAKMUAA==.Anieros:BAAANQAECgEIAgABNQAECgkJFAAFAFgTAA==.',
Ar='Arai:BAAANQADCgIIAgAAAA==.Arax:BAAANQAECgQIBgAAAA==.Arcamoon:BAAANQADCgEIAQAAAA==.Arianpali:BAAANQAECgcIEQAAAA==.Armâgeddon:BAABNQAECn8jAAICAAkKcyB+LAAKAwACAAkKcyB+LAAKAwAAAA==.Arthritas:BAAANQADCgQIBAAAAA==.',
At='Atropós:BAAANQAECgYIDwAAAA==.Attachedplag:BAAANQAECgYIEgAAAA==.Atulwa:BAAANQADCgMIAwAAAA==.',
Au='Autodrive:BAAANQAECgEIAgAAAA==.',
Az='Azmodious:BAAANQABCgIIAgAAAA==.',
Ba='Baconhuntard:BAAANQAECgMIBAAAAA==.Bambislayer:BAAANQADCgYIBwAAAA==.Banannana:BAAANQAECgUIBwAAAA==.Banzen:BAAANQADCggIGwAAAA==.Battle:BAEANQADCgEIAQABNQAECgoKMAAGAGgeAA==.',
Be='Beardedyeti:BAAANQAECgEIAgAAAA==.Beginagain:BAAANQADCgcIFAAAAA==.Belgran:BAABNQAECn8nAAIHAAoKnRbiCQC9AQAHAAoKnRbiCQC9AQAAAA==.Bernese:BAAANQAECgcICQAAAA==.Berunma:BAABNQAECn8WAAIIAAgKYw23rgCnAQAIAAgKYw23rgCnAQAAAA==.',
Bh='Bhain:BAAANQAFFAMIAwAAAA==.',
Bi='Bileshots:BAAANQAECgYIBwAAAA==.Biowolf:BAABNQAECn8XAAIJAAkKHRHlsgAdAgAJAAkKHRHlsgAdAgAAAA==.Birdhunter:BAAANQAECgYIBgAAAA==.Bishopixixix:BAAANQABCgMIAwABNQAECgQIBAABAAAAAA==.Bishopxix:BAAANQAECgQIBAAAAA==.Bits:BAAANQAECgIIAgAAAA==.',
Bj='Bjoren:BAABNQAECn8rAAMKAAkKlyKIFwAaAwAKAAkKlyKIFwAaAwALAAEKAAADlwAKAAAAAA==.',
Bl='Blackki:BAAANQADCgQIBQAAAA==.Bloodbaron:BAAANQAECgIIAgABNQAECgcIFAAEAKsUAA==.',
Bo='Bootiebang:BAABNQAECn8bAAIMAAYK4AbXMgCOAAAMAAYK4AbXMgCOAAAAAA==.Bootieknight:BAAANQADCgcIBwAAAA==.Bootycaall:BAAANQADCgcIDgAAAA==.Boxxie:BAAANQADCgcIFQAAAA==.',
Br='Branches:BAAANQADCgMIAwAAAA==.Brockshot:BAAANQAECgEIBQAAAA==.',
Bu='Bucknekkid:BAAANQAECgUIBQAAAA==.Buckwhild:BAABNQAECn8eAAMKAAkKXRyxMwCZAgAKAAkKXRyxMwCZAgALAAEKAADLigAfAAAAAA==.',
By='Byleth:BAAANQADCgIIAgAAAA==.',
Ca='Caladbolg:BAABNQAECn81AAMNAAoKCh0ZBADOAQANAAkK4B8ZBADOAQAOAAQKuwsjxABtAAAAAA==.Canadaisheal:BAAANQAECgUICwAAAA==.Catslol:BAAANQADCgIIAgAAAA==.',
Ce='Cerñuñños:BAAANQAECgIIAgAAAA==.Cesàrè:BAAANQAECgQIEgAAAA==.',
Ch='Chahra:BAAANQAECgUIBQAAAA==.Chamuki:BAAANQAECggIDwABNQAFFAUIGAAPAKkZAA==.Cheesecake:BAAANQADCgMIAwABNQAFFAQICQACAKMUAA==.Chuubak:BAAANQAECggICAAAAA==.',
Cl='Clangeddin:BAAANQADCgIIAgAAAA==.Clangedin:BAAANQAECgYIDgAAAA==.',
Co='Colonidus:BAAANQAECgQIBAAAAA==.Coondic:BAAANQADCgIIAgAAAA==.Corsten:BAABNQAECn8aAAIQAAYKrRX8CAAlAQAQAAYKrRX8CAAlAQAAAA==.',
Cr='Crosis:BAAANQADCgQIBQAAAA==.',
Cu='Cute:BAABNQAECn8eAAMCAAgKzB2begAoAgACAAgKuR2begAoAgARAAQKWxiFHgDMAAAAAA==.',
Da='Dagby:BAAANQADCgcIGwAAAA==.Dandi:BAAANQAECgIIAwAAAA==.Daneaus:BAAANQAECgEIAQABNQAECggIGQASAEskAA==.Dangerzone:BAAANQADCgUIBQAAAA==.Darkchronos:BAAANQADCggICwAAAA==.Darkscorp:BAAANQADCgIIAgAAAA==.Darkwolf:BAAANQAECgQICAAAAA==.Darnuus:BAABNQAECn8mAAMTAAoKgRvjKADAAgATAAoKgRvjKADAAgAUAAQKJAmdaQBpAAAAAA==.Datromandude:BAAANQAECgMIBQAAAA==.',
De='Deadmetalhed:BAAANQADCgIIAgAAAA==.Deathbydruid:BAABNQAECn8cAAMVAAcK0wk6PgAyAQAVAAcK0wk6PgAyAQAPAAYKCAeWcQADAQABNQAECggIGQAIACMFAA==.Deathnelf:BAAANQADCgMIAwAAAA==.Deazraelle:BAABNQAECn8bAAIEAAkKLhR1GACQAQAEAAkKLhR1GACQAQAAAA==.Dellin:BAABNQAECn8YAAIPAAgKLBShPgAEAgAPAAgKLBShPgAEAgAAAA==.Demeco:BAEANQAECgUJCQABNQAFFAgIFAASAOQZAA==.Demondots:BAAANQAECgUIBwAAAA==.Denzalle:BAAANQADCgYJCQAAAA==.Devildognutz:BAAANQAECgEIAQAAAA==.',
Di='Diminuendo:BAAANQAECgIIAgAAAA==.',
Do='Doozydruid:BAABNQAECn8UAAIPAAcKeg/rVQCAAQAPAAcKeg/rVQCAAQAAAA==.Dorozh:BAAANQAECgYICwAAAA==.',
Dr='Draeke:BAAANQAECgEIAQAAAA==.Dragonstorm:BAAANQADCgEIAQAAAA==.Dragonzdemon:BAAANQADCgcICQAAAA==.Drala:BAABNQAECn8XAAIKAAYKzxY5hwCBAQAKAAYKzxY5hwCBAQAAAA==.Dreadar:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.Dreadpally:BAAANQADCgYJCgABNQAECgEIAgABAAAAAA==.Dreco:BAAANQAECgYIEgAAAA==.Driver:BAEANQAECggICAAAAA==.Drtydhn:BAAANQABCgMIAwAAAA==.Druuzak:BAABNQAECn8kAAIWAAkKGg5dBQBQAQAWAAkKGg5dBQBQAQAAAA==.Dryconias:BAABNQAECn84AAIOAAoK4hqzQwDJAgAOAAoK4hqzQwDJAgAAAA==.Drèadpriest:BAAANQADCgUJBAAAAA==.',
Du='Duncanmcleod:BAAANQAECggIEQABNQAECgoKHAAKAOQZAA==.Dunkelzhan:BAABNQAECn8iAAIJAAgKBBT+1gDZAQAJAAgKBBT+1gDZAQAAAA==.',
Dv='Dvldogma:BAAANQAECgUIDwAAAA==.',
Dy='Dyana:BAAANQAECgYICwAAAA==.',
Dz='Dz:BAABNQAECn81AAMSAAoKMCXFBACqAwASAAoKMCXFBACqAwAOAAYKDA7I9AAzAQAAAA==.',
['Dø']='Dømimømmÿ:BAAANQAECgMIAwAAAA==.',
Ec='Ecobessie:BAAANQADCgcICwAAAA==.Ecowolf:BAAANQADCgYICgABNQADCgcICwABAAAAAA==.',
Ed='Edlund:BAAANQAECgcIEwAAAA==.',
El='Electricfun:BAAANQAECgEIAQAAAA==.Ellenaim:BAAANQAECgUIBQAAAA==.Elvy:BAABNQAECn8rAAIPAAoKJhYmNwA0AgAPAAoKJhYmNwA0AgAAAA==.',
En='Enngin:BAAANQAECgMIBAAAAA==.Enroks:BAABNQAECn8rAAQUAAgK+BHrYwD1AQAUAAgK+BHrYwD1AQATAAYKZhkdggCGAQAXAAEKAAARNwAzAAAAAA==.',
Er='Erythrina:BAAANQADCgYICAAAAA==.',
Es='Esaelle:BAAANQADCggICAAAAA==.',
Ev='Evangelene:BAABNQAECn8lAAMVAAgKNRRiDQBmAQAVAAgKNRRiDQBmAQAPAAUKlwSchQC8AAAAAA==.Evangelina:BAAANQADCgEIAQAAAA==.',
Ex='Exsalsior:BAABNQAECn8UAAIFAAkKWBOoNQACAgAFAAkKWBOoNQACAgAAAA==.',
Fa='Fabulousness:BAAANQAECgYICwAAAA==.Fathur:BAAANQAECgEIAQAAAA==.',
Fe='Fellstar:BAAANQADCgYIBgAAAA==.',
Fo='Fornix:BAAANQADCgEIAQAAAA==.',
Fu='Furryriver:BAAANQAECgUIEQAAAA==.Furussy:BAAANQADCgcIBwAAAA==.Furytotem:BAAANQAECgEIAQABNQAECgcIHwAGAO8VAA==.',
Ga='Galadhras:BAAANQADCgYIDAAAAA==.Gamboslice:BAABNQAECn8pAAIHAAoKyhUzBwDlAQAHAAoKyhUzBwDlAQAAAA==.Garkevon:BAABNQAECn8cAAMYAAcKrAY3JgDNAAAYAAcKrAY3JgDNAAAZAAIK8gH7wgBCAAAAAA==.',
Ge='Geoffana:BAAANQAECgEIAQAAAA==.Gevul:BAABNQAECn9GAAQEAAkK5Ru2QwCHAgAEAAgKhhy2QwCHAgADAAMKoRFKOQDbAAAaAAEKAADLMQAxAAAAAA==.',
Gh='Ghuun:BAABNQAECn8UAAIEAAcKqxQBMwAwAQAEAAcKqxQBMwAwAQAAAA==.',
Gl='Glep:BAAANQAECgEIAQAAAA==.Glimmervoid:BAAANQAECgMIBQAAAA==.',
Go='Golland:BAAANQAECgEIAQABNQAECgoKJwAUACwVAA==.Goob:BAAANQAECgEIAQAAAA==.',
Gr='Grandmatank:BAAANQADCgYIBgAAAA==.Greeze:BAABNQAECn8XAAIOAAgKjBVkiAAWAgAOAAgKjBVkiAAWAgAAAA==.Grimero:BAAANQAECggIAgAAAA==.Groinsapper:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Grozny:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Gu='Gumboslice:BAABNQAECn80AAMVAAoKhh1SEQDJAgAVAAoKhh1SEQDJAgAPAAEKAABqYgAAAAAAAA==.Gumiho:BAAANQAECgUICgAAAA==.Gusgus:BAABNQAECn8WAAIWAAcKQgtBCQD2AAAWAAcKQgtBCQD2AAAAAA==.',
Gy='Gyroflux:BAAANQAECgMIAwAAAA==.',
Ha='Haackh:BAACNQAFFH8JAAIIAAQKkxGSEQBHAQAIAAQKkxGSEQBHAQA1AAQKfyUAAggACgrAIZsTAFADAAgACgrAIZsTAFADAAAA.Habanero:BAABNQAECn8UAAIUAAgK0B76RgBaAgAUAAgK0B76RgBaAgAAAA==.Hadd:BAAANQADCgEJAQAAAA==.Hadrìan:BAAANQADCgYIBgAAAA==.Hadéz:BAAANQAECggIAgABNQAECggKKAAbACALAA==.Hammerfist:BAAANQAECgIIAgAAAA==.Hark:BAAANQADCgcIFgAAAA==.Haveabubble:BAAANQADCgQIAgABNQAECggIGQACAKwNAA==.',
He='Healvisprsly:BAAANQAECgEIAQAAAA==.Helena:BAABNQAECn8vAAMNAAoKJiG3AAD0AgANAAoKJiG3AAD0AgAOAAgKNhpecwBIAgAAAA==.Heliarc:BAAANQADCgcIHAAAAA==.',
Hi='Hidän:BAABNQAECn8ZAAMEAAYKdw2kvQBRAQAEAAYKdw2kvQBRAQADAAEKwgWSfgAuAAAAAA==.Himself:BAAANQAECgEIAQAAAA==.',
Ho='Holeyman:BAAANQADCgMIBAAAAA==.Hoomalu:BAAANQADCgIIAgAAAA==.',
Hu='Huund:BAAANQADCgUIBQAAAA==.Huutou:BAAANQADCgYICwAAAA==.',
Il='Illatix:BAAANQAECgQICQAAAA==.Illustriä:BAAANQAECgUICgAAAA==.',
In='Insidious:BAABNQAECn8bAAIZAAcKlxxiMABQAgAZAAcKlxxiMABQAgAAAA==.',
Ir='Irs:BAAANQAECggICgAAAA==.',
It='Itchydh:BAAANQADCgEJAQABNQAECgkJKQAJADIfAA==.Itchymage:BAABNQAECn8pAAMJAAkKMh/6MwBXAQAJAAkKxh36MwBXAQAWAAQKEh2jFQBTAQAAAA==.',
Iv='Ivyrayne:BAAANQAECgEIAQAAAA==.',
Ja='Jaganash:BAAANQADCggICwABNQAECgYIDwABAAAAAA==.Jakeofny:BAAANQAECgYICgAAAA==.',
Je='Jeffsgoytoy:BAAANQAECgcIEAAAAA==.',
Ji='Jighlipuff:BAABNQAECn8XAAIOAAcKVwYnlwCrAAAOAAcKVwYnlwCrAAAAAA==.Jigs:BAABNQAECn8iAAIIAAcKjwohuQCRAQAIAAcKjwohuQCRAQAAAA==.Jinxy:BAAANQADCggINwABNQAECgQIBAABAAAAAA==.',
Ju='Judgements:BAAANQAECgQIBgAAAA==.Jug:BAAANQADCggIKQAAAA==.Jujutanketh:BAAANQAECgUIDQAAAA==.Junebugg:BAAANQAECgYIDQAAAA==.',
Ka='Kabøchi:BAAANQAECgYIEwAAAA==.Kafia:BAAANQAECgMIAgAAAA==.Kalamak:BAAANQABCgYICQAAAA==.Kaldrick:BAAANQAECgUIDAAAAA==.Kanaloa:BAAANQAECgUIBwAAAA==.Kaorin:BAAANQAECgEIAQABNQAECgoKLgATALMiAA==.Karindis:BAABNQAECn8rAAIcAAkKoiHlAwAYAwAcAAkKoiHlAwAYAwAAAA==.Kathulhu:BAAANQAECgIIBAAAAA==.Kayler:BAAANQAECggICAAAAA==.',
Ke='Kegerator:BAAANQADCgMIBAAAAA==.Keldica:BAAANQAECgcIDAABNQAECgoKIQAUACseAA==.Kenshan:BAAANQAECgEIAgAAAA==.',
Kh='Khalinor:BAAANQAECgYIEQAAAA==.Khotuhn:BAAANQAECgUIBAAAAA==.',
Ki='Kickazdin:BAABNQAECn8rAAMSAAkKyR7hKADFAgASAAgKRh/hKADFAgAOAAEKAABNngE4AAAAAA==.Killadragon:BAAANQAECgUIBQAAAA==.Kiryie:BAAANQAECgIIAgAAAA==.Kitinna:BAAANQAECgQIDQAAAA==.',
Kl='Klaw:BAAANQADCgYIEAAAAA==.',
Ko='Korraa:BAABNQAECn8gAAMTAAgKth1fTwAnAgATAAgKth1fTwAnAgAUAAUKVhGqsQAvAQAAAA==.',
Kp='Kprist:BAAANQAECgUIDQAAAA==.',
Kr='Kraigen:BAAANQAECgYIDQAAAA==.',
Ku='Kunzhut:BAABNQAECn8ZAAMYAAgKIhWnVQC7AQAYAAgKIhWnVQC7AQAHAAMKKghxRACVAAAAAA==.Kuroi:BAAANQADCgMIAwAAAA==.',
Ky='Kynasmira:BAAANQADCgcIEwAAAA==.',
La='Ladrona:BAAANQAECgEIAQAAAA==.Laeli:BAAANQAECgQIBAAAAA==.Lailyre:BAAANQAECggIBgABNQAECggICAABAAAAAA==.Laydin:BAABNQAECn8ZAAIIAAgKIwVdAAEEAQAIAAgKIwVdAAEEAQAAAA==.',
Lb='Lb:BAABNQAECn8kAAMIAAoKNhrWBQBwAgAIAAoKNhrWBQBwAgAbAAUKcAsxSwAJAQAAAA==.',
Le='Legzanot:BAABNQAECn8vAAIUAAoKchPBEQCIAQAUAAoKchPBEQCIAQAAAA==.Lestrade:BAABNQAECn8aAAIZAAgK8A3bFgAwAQAZAAgK8A3bFgAwAQABNQAECgoKJgATAIEbAA==.',
Li='Lightdude:BAAANQADCgcJBwAAAA==.Lightningfox:BAABNQAECn8aAAMOAAYK6xcuVgAYAQAOAAYK6xcuVgAYAQASAAIKqw3lBAFvAAAAAA==.Lightsfallen:BAABNQAECn8cAAMKAAoK5Bn4CgA1AgAKAAoK5Bn4CgA1AgAdAAEKuwa4LQApAAAAAA==.Lithia:BAAANQAECgUIBQAAAA==.Littlemo:BAAANQAECgUIEQAAAA==.',
Lo='Lohnar:BAAANQAECgUIEQAAAA==.Lorzana:BAAANQADCgcIDQAAAA==.',
Lu='Lucidslock:BAAANQADCgcIEgAAAA==.Lucielbaal:BAABNQAECn8WAAIEAAgK8RcOgwDeAQAEAAgK8RcOgwDeAQAAAA==.Luckystop:BAAANQAECgEIAQAAAA==.Lumenir:BAAANQADCggIDgAAAA==.Lunareth:BAAANQAECgcIDQAAAA==.',
Ly='Lyrska:BAAANQAECgQIDQAAAA==.Lytearrow:BAABNQAECn8YAAIIAAgK+Qn+kQDlAQAIAAgK+Qn+kQDlAQAAAA==.',
['Lì']='Lìvíd:BAAANQAECgUICwAAAA==.',
Ma='Mahrylee:BAAANQAECgEIAQAAAA==.Majin:BAAANQAECgUICQAAAA==.Makbeard:BAAANQADCgYIBgABNQAECgcICAABAAAAAA==.Makmobius:BAAANQAECgcICAAAAA==.Manbearpally:BAAANQAECgEIAgAAAA==.Mannypack:BAAANQAECgQIBwAAAA==.Mathagni:BAAANQADCgQIBAABNQADCgcIFwABAAAAAA==.Mathau:BAAANQADCgcIFwAAAA==.Maztrix:BAAANQAECgIIAwAAAA==.',
Mc='Mcleary:BAAANQAECgQIBwAAAA==.',
Me='Meldrus:BAABNQAECn8XAAIEAAgK/gnsmQCmAQAEAAgK/gnsmQCmAQAAAA==.Mending:BAAANQAECgQICAAAAA==.',
Mi='Miala:BAAANQAECgIIBgAAAA==.Midnytestorm:BAAANQADCgcJBgAAAA==.Mierna:BAABNQAECn8ZAAITAAgKbSCtMwCRAgATAAgKbSCtMwCRAgAAAA==.Miler:BAAANQAECgUICQAAAA==.Mirota:BAAANQADCgEJAQAAAA==.',
Mo='Moemo:BAABNQAECn8YAAIVAAYKCCQfGgBpAgAVAAYKCCQfGgBpAgAAAA==.Mogryn:BAABNQAECn8UAAIIAAgKIhYrhwD9AQAIAAgKIhYrhwD9AQAAAA==.Mommybree:BAAANQAECgIIAgAAAA==.Monotonous:BAAANQADCgUIEAAAAA==.Moondog:BAAANQAECgIIAgAAAA==.Moonwarriorx:BAAANQAECgcIBwAAAA==.Morganalefey:BAAANQADCgMIBAAAAA==.Morsecode:BAAANQAECgMIBgABNQAECgcIHwAGAO8VAA==.Morthok:BAAANQAECgYIDwAAAA==.Mosh:BAABNQAECn8cAAIeAAYKJh6EDQAjAgAeAAYKJh6EDQAjAgAAAA==.',
Mu='Muskelunge:BAAANQAECgEIAQAAAA==.Mustachekick:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãf:BAAANQADCggICQAAAA==.',
Na='Naelyn:BAABNQAECn8ZAAIIAAgKJhajcwApAgAIAAgKJhajcwApAgAAAA==.Nafir:BAAANQADCgYIDwAAAA==.Nakky:BAAANQADCggICwAAAA==.Nazgor:BAABNQAECn8XAAIYAAgK5hrLDgBoAQAYAAgK5hrLDgBoAQAAAA==.',
Ne='Necrodragon:BAAANQADCgMIBgAAAA==.Necrosius:BAAANQADCgEIAQAAAA==.Neolythic:BAEANQAECgEIAwAAAA==.Newwt:BAAANQADCgcIBwAAAA==.',
Ny='Nyxstalia:BAAANQADCgUIAwAAAA==.Nyyx:BAAANQAECgUICAAAAA==.',
Oa='Oath:BAAANQAECgYIDwAAAA==.',
Ob='Obscyra:BAABNQAECn8ZAAIWAAYKyw2RGAAzAQAWAAYKyw2RGAAzAQABNQAECgcIDQABAAAAAA==.',
Oc='Ochiie:BAAANQADCgcIFgAAAA==.Ocho:BAAANQADCgUIBQAAAA==.',
Od='Oddsham:BAAANQADCgUIBgAAAA==.Oddyeppyep:BAAANQAECgEIAgAAAA==.',
Of='Offhand:BAAANQADCggJBwAAAA==.',
Og='Oghamm:BAAANQAECgEIAQAAAA==.',
Ol='Olmek:BAACNQAFFH8KAAMCAAUK2wYKGwA8AQACAAUK2wYKGwA8AQARAAEK7AnzBgA9AAA1AAQKfz0AAwIACgrBH0oQANUBAAIACgrBH0oQANUBABEABAruD+IeAMgAAAAA.',
Oo='Oochie:BAABNQAECn8cAAIKAAkKPwp2IgB4AQAKAAkKPwp2IgB4AQAAAA==.Oochiee:BAAANQAECgQIBQAAAA==.Oochiië:BAAANQAECgEIAQAAAA==.',
Op='Oprahwndfury:BAAANQAECgEIBQABNQAECgEIAQABAAAAAA==.',
Pa='Palanoris:BAAANQABCggIGQAAAA==.Palasades:BAAANQAECgUIDgAAAA==.Palelore:BAAANQAECgEIAwAAAA==.Pallydussy:BAAANQAECgMIAwAAAA==.Pallymarc:BAAANQADCgQIBAAAAA==.Pandalorian:BAABNQAECn8iAAIKAAkKAhYYSgBHAgAKAAkKAhYYSgBHAgAAAA==.Papapumpies:BAABNQAECn8yAAICAAoKmiLJLAAJAwACAAoKmiLJLAAJAwAAAA==.Parlow:BAAANQAECgEIAQAAAA==.Pazzo:BAAANQAECgUICAAAAA==.',
Ph='Pharaa:BAABNQAECn8XAAILAAcKFAagFQDcAAALAAcKFAagFQDcAAAAAA==.Philandre:BAAANQAECgQIBAAAAA==.',
Pi='Picoso:BAAANQAECgYIDwAAAA==.Piianna:BAABNQAECn8vAAIKAAoKJBhCLwCrAgAKAAoKJBhCLwCrAgAAAA==.Pizzaroll:BAABNQAECn8mAAIfAAkKKx/WCADrAgAfAAkKKx/WCADrAgAAAA==.',
Po='Pomégranate:BAAANQADCggICgAAAA==.',
Pu='Puckster:BAAANQAECgQIBAAAAA==.',
['Pø']='Pøwe:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Qa='Qatbarph:BAAANQAECgYIEgAAAA==.',
Qi='Qikkaw:BAABNQAECn8bAAMTAAYKcBC+mgBEAQATAAYKcBC+mgBEAQAUAAYKwwdhVQCUAAAAAA==.',
Qu='Quantos:BAABNQAECn8XAAIfAAcKbhG6EAAHAQAfAAcKbhG6EAAHAQAAAA==.',
Ra='Raatha:BAABNQAECn8YAAIOAAcKNxsvmADzAQAOAAcKNxsvmADzAQAAAA==.Raganar:BAABNQAECn8dAAINAAcKowkkFQDfAAANAAcKowkkFQDfAAAAAA==.Rago:BAAANQAECgcIDAAAAA==.Rasz:BAABNQAECn8oAAMIAAgKhBWBKwBuAQAIAAcKCBiBKwBuAQAbAAYK4wzsSQARAQAAAA==.Rayjean:BAAANQADCgMIAwABNQADCgcIGQABAAAAAA==.',
Re='Regelia:BAAANQADCgcIBwAAAA==.Reider:BAAANQADCggIFwAAAA==.Relmax:BAAANQAECgYICwAAAA==.Rennia:BAAANQAECgIIAgABNQAECggICAABAAAAAA==.Renzu:BAAANQADCgYIAQAAAA==.',
Rh='Rhonwynn:BAABNQAECn8XAAITAAcKnRdmDgDqAQATAAcKnRdmDgDqAQAAAA==.',
Ri='Rikershipdwn:BAAANQAECgQIBwAAAA==.Rimrave:BAABNQAECn8ZAAICAAgKrA1QwgB3AQACAAgKrA1QwgB3AQAAAA==.Ritobeans:BAAANQADCgcICgAAAA==.',
Rk='Rk:BAABNQAECn8aAAIgAAcK2gu8IQBAAQAgAAcK2gu8IQBAAQABNQAECggIJAAhAO0JAA==.',
Ro='Robertkenway:BAABNQAECn8kAAIhAAgK7QniBwDnAQAhAAgK7QniBwDnAQAAAA==.Roberto:BAAANQADCggICgAAAA==.Rod:BAABNQAECn8iAAIiAAkKPhE1GwDPAQAiAAkKPhE1GwDPAQAAAA==.Rokte:BAAANQAECggIDAAAAA==.Rollhots:BAAANQAECgYIDQAAAA==.Rook:BAABNQAECn8kAAMaAAoKkx8qAAC4AgAaAAoKkx8qAAC4AgAEAAEK7g6WOgFAAAABNQAECgkJHQACAKEaAA==.Rooke:BAABNQAECn8dAAICAAkKoRqAIQB+AQACAAkKoRqAIQB+AQAAAA==.Rorsh:BAAANQAECgQIBAAAAA==.Rosekenway:BAABNQAECn8XAAMVAAgKewiGOABZAQAVAAgKewiGOABZAQAPAAEKwwGOwgAfAAABNQAECggIJAAhAO0JAA==.',
Rr='Rratt:BAAANQAECgEIAgAAAA==.',
Ru='Running:BAAANQADCgcICAAAAA==.',
['Rî']='Rîkku:BAAANQADCgEIAQAAAA==.',
Sa='Safewaybag:BAAANQADCgQIBAAAAA==.Samartyr:BAAANQAECgUIEQAAAA==.Sangwynaris:BAAANQADCggIDgAAAA==.Sanilien:BAAANQAECgQICgAAAA==.Saphiiraa:BAAANQADCgYIBgAAAA==.Sathara:BAAANQADCgEIAQAAAA==.',
Sc='Scorpmage:BAABNQAECn8fAAIWAAcKVhkNDgDMAQAWAAcKVhkNDgDMAQAAAA==.',
Se='Sedrick:BAABNQAECn8dAAMOAAgKZhF/wgCXAQAOAAcKlBF/wgCXAQASAAcKxhJxkgBnAQAAAA==.Sekaholic:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekendipity:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Sekhmett:BAAANQADCgIIAgAAAA==.Sekndestroy:BAAANQAECgIIAgAAAA==.Seksational:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Sekthyr:BAAANQADCgcIDgABNQAECgIIAgABAAAAAA==.Sekzen:BAAANQADCgUJDgABNQAECgIIAgABAAAAAA==.',
Sh='Shamtune:BAACNQAFFH8JAAITAAMK/xCIGQDPAAATAAMK/xCIGQDPAAA1AAQKfyUAAxMACgoXFtBIAD8CABMACgoXFtBIAD8CABQAAQqdDkEuAToAAAAA.Sharayman:BAAANQADCgcIGQAAAA==.Shattered:BAAANQADCgYICQAAAA==.Shaydra:BAABNQAECn8cAAIHAAcK6BY3QwC3AQAHAAcK6BY3QwC3AQAAAA==.Shazool:BAABNQAECn8uAAMTAAoKsyKDCQB1AwATAAoKsyKDCQB1AwAXAAQK/gqTJwDqAAAAAA==.Shevee:BAAANQADCgEIAQAAAA==.Shifterz:BAAANQAECgUICQAAAA==.Shrieke:BAAANQADCgYIBgAAAA==.Shrubbery:BAAANQAECgYICwAAAA==.',
Si='Siarra:BAAANQADCgMIAwAAAA==.Sind:BAAANQADCgIIAgABNQAECgUIDQABAAAAAA==.Sindella:BAAANQAECgUIDQAAAA==.Sindrè:BAAANQABCgUIBQABNQAECgUIDQABAAAAAA==.Sinna:BAAANQAECgEIAgAAAA==.Sinpriest:BAAANQAECgIIAwABNQAECgMIBQABAAAAAA==.',
Sk='Skedaddle:BAAANQAECgQIBwAAAA==.',
Sl='Slashgquit:BAABNQAECn8ZAAIZAAcKVCJCMABQAgAZAAcKVCJCMABQAgAAAA==.Slumbermist:BAABNQAECn8fAAIGAAcK7xXsLACyAQAGAAcK7xXsLACyAQAAAA==.',
Sn='Snazzi:BAABNQAECn8YAAIUAAgKkwqRfACuAQAUAAgKkwqRfACuAQAAAA==.Snowtitan:BAAANQADCgUIBQAAAA==.',
So='Solam:BAAANQAECgMIAwAAAA==.',
Sp='Sploob:BAAANQADCgUIBQAAAA==.',
St='Stabbs:BAAANQADCggIDgAAAA==.Strawberyy:BAAANQAECgEIAQABNQAFFAQICQACAKMUAA==.Strongboy:BAAANQADCgUIBwAAAA==.Stx:BAAANQADCggICAABNQAECggIFAAhAN8PAA==.',
Su='Survival:BAAANQAECgEIAQAAAA==.',
Sy='Syndar:BAABNQAECn8hAAMUAAoKKx4aEQCNAQAUAAkKsh8aEQCNAQATAAEKnhxHgQBUAAAAAA==.Synthetic:BAABNQAECn8UAAIDAAYK2Q0mBQDXAAADAAYK2Q0mBQDXAAAAAA==.',
Sz='Szasstaam:BAAANQAECggIBgAAAA==.',
Ta='Tarnaris:BAAANQADCgIIAgAAAA==.Tattersaile:BAAANQADCgUIBwAAAA==.',
Te='Tecsaran:BAAANQAECgYIDAABNQAECgoKIQAUACseAA==.Tekis:BAAANQAECgUIDwAAAA==.Tensanio:BAAANQAECgUIBQAAAA==.',
Th='Thalira:BAAANQAECgYICQAAAA==.Thalrix:BAAANQAECggIEQAAAA==.Thebiznitch:BAAANQADCgUIBAAAAA==.Theholyboi:BAAANQAECgUJBwAAAA==.Thetowelie:BAAANQAECgEIAQAAAA==.Thickneck:BAAANQADCgUIBQAAAA==.',
Ti='Tieson:BAAANQAECgEIBgAAAA==.Tinkera:BAAANQADCgcIEQAAAA==.Titanosaurus:BAAANQAECgIIAgAAAA==.',
To='Tomcruise:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Torridwells:BAAANQAECgUIBQAAAA==.',
Tr='Triebryn:BAAANQABCgQIBgAAAA==.Troag:BAAANQAECgUIEwAAAA==.Troagstar:BAABNQAECn8UAAIUAAYKZBARNADwAAAUAAYKZBARNADwAAAAAA==.',
Tu='Tubbytoe:BAAANQAECgEIAQAAAA==.',
Ty='Tyraana:BAABNQAECn8mAAMjAAoKihubIACWAgAjAAoKihubIACWAgAkAAEKAAAtbQAzAAAAAA==.Tyrmog:BAAANQAECgEIAQAAAA==.Tytus:BAAANQAECgEIAQAAAA==.',
Un='Undetha:BAAANQAECgYIDwAAAA==.',
Us='Ushas:BAABNQAECn8kAAMKAAkKyhfzMQA3AQAKAAkKyhfzMQA3AQALAAEKAAAZhAAlAAAAAA==.',
Va='Vali:BAAANQADCgcIDQABNQAECgYIDwABAAAAAA==.Valindrea:BAAANQAECgUIEQAAAA==.Vasrael:BAAANQAECgYIDwAAAA==.',
Ve='Vel:BAABNQAECn8lAAMkAAoK3gbbNQCUAQAkAAoK3gbbNQCUAQAcAAcKmQINDgCLAAAAAA==.Velnie:BAAANQAECgMIBQAAAA==.Venvanse:BAAANQAECgEIAQABNQAECggIGgAJALcNAA==.Verq:BAAANQAECgEIAQAAAA==.Vexen:BAABNQAECn8cAAIkAAcKUBe9LQDUAQAkAAcKUBe9LQDUAQAAAA==.',
Vn='Vnia:BAAANQAECgEIAQAAAA==.',
Vo='Voidmuffinz:BAABNQAECn8vAAMkAAoKfRtnFwCjAgAkAAoKfRtnFwCjAgAjAAcKeA2USQB/AQAAAA==.',
Vy='Vynis:BAAANQAECgQIBAABNQAFFAMICQATAP8QAA==.Vyrahildard:BAABNQAECn8ZAAIOAAgKehh2ggAjAgAOAAgKehh2ggAjAgAAAA==.',
Wa='Wakkiq:BAAANQAECgEIAQAAAA==.Wasteland:BAABNQAECn8vAAIZAAoKiApEWQCOAQAZAAoKiApEWQCOAQAAAA==.Watermelon:BAABNQAECn8lAAMTAAoK3hGGWQAEAgATAAoK3hGGWQAEAgAUAAQKJAJGAgGLAAABNQAFFAMICAAVAFsIAA==.',
We='Weaselhunter:BAAANQAECggIEgAAAA==.Weasellock:BAAANQAECgUIDQABNQAECggIEgABAAAAAA==.Weaselmage:BAAANQAECgIIDQABNQAECggIEgABAAAAAA==.Weaselshammy:BAAANQAECgYIDwABNQAECggIEgABAAAAAA==.',
Wh='Whatthef:BAAANQADCgcIDwAAAA==.',
Wi='Wildweasel:BAAANQAECgQIBgABNQAECggIEgABAAAAAA==.Winterhide:BAAANQAECgYIDwAAAA==.Wishbone:BAAANQAECgQIEAAAAA==.',
Wo='Womamatoo:BAAANQADCgcICgAAAA==.',
Xa='Xallie:BAEANQAECgYIEAAAAA==.Xanvyr:BAAANQAECgUIBwABNQAECgUICwABAAAAAA==.Xaquillis:BAABNQAECn8eAAIZAAoKyA1dTQDAAQAZAAoKyA1dTQDAAQAAAA==.Xaras:BAAANQADCgMIAwAAAA==.',
Xe='Xentrie:BAAANQAECgQIBQAAAA==.Xeyvara:BAABNQAECn8ZAAIcAAgKrR+pBwCIAgAcAAgKrR+pBwCIAgAAAA==.',
Ya='Yah:BAAANQADCggICwAAAA==.',
Za='Zaravalatha:BAAANQAECgEIAQAAAA==.Zarihanna:BAABNQAECn83AAIJAAgKkBDJWwAGAQAJAAgKkBDJWwAGAQAAAA==.Zariia:BAAANQADCgQICQAAAA==.Zarsiia:BAAANQAECgUIDgAAAA==.Zatima:BAAANQADCgYIBgAAAA==.',
Ze='Zernakk:BAAANQAECgUIDAAAAA==.Zestdh:BAAANQAECgUIBwAAAA==.Zestyknight:BAAANQAECgQIBgAAAA==.',
Zi='Zindeshal:BAAANQADCgcICwAAAA==.',
Zo='Zorcunter:BAABNQAECn8oAAIIAAoKjyTbEwBPAwAIAAoKjyTbEwBPAwAAAA==.',
Zu='Zulizzajabi:BAAANQAECgIJBgAAAA==.',
['Åt']='Åthenå:BAAANQADCgYICgAAAA==.',
['Ða']='Ðarthrevan:BAAANQAECgEIAQAAAA==.',
['Ðo']='Ðonjon:BAAANQAECgEIAQAAAA==.',
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
