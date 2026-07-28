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

local lookup = {'Druid-Feral','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Priest-Discipline','Warrior-Protection','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Brewmaster','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','DeathKnight-Frost','Warlock-Affliction','Paladin-Protection','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Absydion:BAAALgAFFAEJAQAAAA==.',
Ac='Acherøn:BAAALgAECggJCAAAAA==.',
Ad='Adema:BAAALgADCgQJBQABLgAECgkJFgABAC8aAA==.',
Ae='Aellaleander:BAAALgAECggJDAAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwACAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Arathelie:BAAALgAFFAIJAgAAAA==.Aratune:BAAALgADCgEJAQAAAA==.Arazen:BAAALgAECgUJCQAAAA==.Arcjanhealer:BAAALgAECgYJDAAAAA==.Ari:BAAALgAECggJCAAAAA==.Arianá:BAAALgAFFAEJAQAAAA==.',
As='Asahhealer:BAACLgAFFH8MAAIDAAMJiRY0JAC2AAADAAMJiRY0JAC2AAAuAAQKfzQAAwMACAkBHuMUAKQCAAMACAkBHuMUAKQCAAQABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAFACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMDAAkJYhNUKgASAgADAAkJYhNUKgASAgAEAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAICAAQJbBgWEABgAQACAAQJbBgWEABgAQAuAAQKfzYAAwIACQnhJL4KAPoCAAIACQnhJL4KAPoCAAYAAQkAAA5pAD8AAAAA.Aurõrä:BAABLgAECn8UAAIGAAYJQgrdHQC6AAAGAAYJQgrdHQC6AAAAAA==.',
Av='Averlence:BAABLgAFFH8GAAIHAAMJfAXwOACjAAAHAAMJfAXwOACjAAAAAA==.',
Az='Azlia:BAAALgAFFAQJBAABLgAFFAUJBwAIAHQHAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8NAAQJAAUJFx9EBwAfAQAJAAUJFx9EBwAfAQAKAAMJfgw2UQB+AAALAAEJ8wRCUwAxAAABLgAFFAcJGwAMAKwiAA==.',
Ba='Bahumn:BAABLgAECn8WAAIBAAkJLxoIBQAGAQABAAkJLxoIBQAGAQAAAA==.Balboga:BAAALgADCggJCAABLgAECgYJCQANAAAAAA==.Bangpôwbôôm:BAABLgAECn9GAAMOAAkJvSCWBQDNAgAOAAkJhyCWBQDNAgAPAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMQAAkJChLAJADgAQAQAAkJChLAJADgAQARAAUJpBDSCgGrAAAAAA==.Beryl:BAAALgAECgQJAwAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAISAAgJaxwiNQCfAgASAAgJaxwiNQCfAgABLgAFFAMJBQATADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgcJDgABLgAECggJGQAQAGMgAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwAUAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgANAAAAAA==.',
Br='Bralantha:BAAALgAECgEJAQABLgAFFAMJDAADAIkWAA==.Brivia:BAAALgAECgUJCAABLgAFFAQJCwACAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAAVABgTAA==.Bullseye:BAAALgAECgMJAwAAAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Burningfel:BAAALgAECgIJAgAAAA==.Buruwar:BAAALgAECggJEwAAAA==.',
Ca='Calgor:BAAALgADCgEJAQAAAA==.Calihye:BAAALgAECgYJCQABLgAFFAkJIwAKAA0cAA==.Camel:BAACLgAFFH8MAAMRAAIJLwjnSwB3AAARAAIJLwjnSwB3AAAQAAEJxATAJwArAAAuAAQKf10AAxEACQk2GV8FADgCABEACQk2GV8FADgCABAACQkLEEo9AFABAAAA.Cattlestance:BAABLgAECn8bAAIIAAkJDRP0FACkAQAIAAkJDRP0FACkAQAAAA==.',
Ce='Ceriebrium:BAAALgAECgEJAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgAECgEJAQAAAA==.',
Cl='Clamchoder:BAAALgAECgEJAQAAAA==.Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgYJDAAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwACAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgAECgIJAgAAAA==.Dashdashdash:BAABLgAECn95AAIWAAkJiyTlAAAmAwAWAAkJiyTlAAAmAwAAAA==.Davethediva:BAAALgAECgEJAgAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIIAAgJ5BZUFgCSAQAIAAgJ5BZUFgCSAQAAAA==.',
De='Deathcraig:BAAALgAECgQJBAAAAA==.Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDQAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8kAAIXAAkJLxV/IQC2AQAXAAkJLxV/IQC2AQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Di='Dirge:BAABLgAFFH8HAAIPAAIJixvhTAC5AAAPAAIJixvhTAC5AAAAAA==.',
Do='Dodgydave:BAAALgAECgEJAQAAAA==.Doomzeer:BAABLgAECn8WAAMVAAcJaRtSAwDfAQAVAAcJaRtSAwDfAQAHAAUJ0hoSBgCMAQABLgAFFAUJEgAYAKkcAA==.Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8jAAISAAkJlxUUQgAWAgASAAkJlxUUQgAWAgAAAA==.Dragoonall:BAAALgADCgMJAwAAAA==.Dragoonette:BAAALgADCgUJBwAAAA==.Drakarys:BAAALgAECgQJBQAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.Drezz:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIJAAkJSx1KBgCdAgAJAAkJSx1KBgCdAgAAAA==.',
['Dë']='Dëathlock:BAAALgAECgQJBAABLgAECgkJNQAUAD8MAA==.',
Ec='Ectasee:BAABLgAECn8zAAMDAAkJRyQxAwCPAwADAAkJRyQxAwCPAwAEAAMJ8RCUcgCTAAAAAA==.',
Ei='Eianhander:BAAALgAECgQJBAAAAA==.Eirenus:BAABLgAECn8UAAMFAAcJVAt/cADHAAAFAAcJVAt/cADHAAAMAAYJiA0OUwC4AAABLgAFFAYJCwAHAJsHAA==.',
El='Element:BAAALgAFFAIJAgAAAA==.',
Em='Emi:BAACLgAFFH8NAAMEAAgJ/AozMADSAAAEAAYJAgczMADSAAADAAMJLhZhXACTAAAuAAQKfyIAAwQACAnEFTU4AFcBAAQABwnYFDU4AFcBAAMACAlMFjVZAFIBAAAA.',
En='Enfilade:BAAALgAECgQJBAAAAA==.Enøch:BAAALgAFFAEJAgAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8tAAQZAAkJ0R9/BADlAgAZAAkJ0R9/BADlAgAaAAEJZB9lOwBZAAAbAAEJXRtiNABLAAABLgAECggJPgATALAjAA==.',
Fa='Fanuc:BAABLgAECn9AAAMDAAkJQyLdBgBCAwADAAkJQyLdBgBCAwAcAAgJLxxjAQAIAgAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAIUAAgJjxHhfgAiAQAUAAgJjxHhfgAiAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8uAAIOAAkJ6xbNAgDwAQAOAAkJ6xbNAgDwAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAABLgAFFH8HAAMIAAUJdAfUFQBvAAAIAAQJmgfUFQBvAAAYAAEJ2waNNABBAAAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgANAAAAAA==.',
Fo='Forthrich:BAACLgAFFH8QAAIRAAMJjgkCOACyAAARAAMJjgkCOACyAAAuAAQKfz8AAhEACQnRDcJuAJEBABEACQnRDcJuAJEBAAAA.Fozuul:BAABLgAECn8UAAMKAAkJBRLEKwD7AQAKAAkJBRLEKwD7AQALAAEJpRW+hABAAAABLgAECgkJJwAFACsbAA==.',
Fr='Frankié:BAAALgADCgEJAQAAAA==.Freeports:BAAALgADCgUJBQAAAA==.Frozendeath:BAAALgAECgEJAQAAAA==.Fruit:BAAALgAECgYJCQAAAA==.Frâust:BAABLgAECn8hAAIdAAkJlxABAgC+AQAdAAkJlxABAgC+AQAAAA==.',
Ga='Galadril:BAAALgADCgYJBgAAAA==.Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMQAAgJAh0TEgCCAgAQAAgJAh0TEgCCAgARAAUJABYvrAAlAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECggJHgAaAJEbAA==.',
Gr='Grimhayze:BAAALgAECgEJAgAAAA==.Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIYAAUJ8COlLwDxAQAYAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgUJDAAAAA==.Gutholoydne:BAABLgAECn8bAAIeAAcJiRT+CwB6AQAeAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgAECgYJCQAAAA==.',
Ha='Hakunamatata:BAAALgAECgEJAQAAAA==.Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAABLgAECn8bAAIWAAYJ6xtqBQBjAQAWAAYJ6xtqBQBjAQAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMXAAkJhQ9MPQBFAQAXAAYJwxBMPQBFAQAVAAkJBwx6SQDpAAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQATADEYAA==.Hirculos:BAABLgAECn8hAAIYAAgJyRcsIgDhAQAYAAgJyRcsIgDhAQAAAA==.',
Ho='Hoggle:BAAALgAECgEJAQAAAA==.Hokkai:BAAALgADCgEJAQAAAA==.Holix:BAAALgAECggJCAAAAA==.Holyfrog:BAABLgAECn9IAAMQAAkJaxsRFwBZAgAQAAkJaxsRFwBZAgARAAIJQgi7VQFaAAAAAA==.Holythis:BAACLgAFFH8XAAIfAAQJlg0wCwDCAAAfAAQJlg0wCwDCAAAuAAQKfy0AAx8ACQnwFqMGAHwCAB8ACQnwFqMGAHwCABEAAQkAAFPZAQAAAAAA.',
Hu='Huntosi:BAAALgAECgEJAQAAAA==.Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
If='Ifrit:BAABLgAFFH8OAAIUAAQJKBEsIgD9AAAUAAQJKBEsIgD9AAAAAA==.',
Ig='Ignis:BAABLgAECn89AAMBAAkJzhRkDADyAQABAAkJzhRkDADyAQAJAAgJ4AjPNADVAAAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMUAAkJtxkkJQA6AgAUAAkJtxkkJQA6AgAWAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn9eAAIgAAkJMSDVAQASAgAgAAkJMSDVAQASAgAAAA==.Injunjoe:BAAALgAECgQJBQAAAA==.',
Io='Ionadaria:BAAALgAECgMJAwAAAA==.',
Is='Isneeztomuch:BAAALgAECgEJAQAAAA==.Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janaru:BAAALgAECgEJAgABLgAECgcJCgANAAAAAA==.Janelik:BAABLgAECn8tAAISAAcJEwUQJgCpAAASAAcJEwUQJgCpAAAAAA==.',
Je='Jeeto:BAAALgAFFAEJAQAAAA==.Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jimihendrix:BAAALgAECgYJCAAAAA==.Jinxi:BAABLgAECn8jAAIaAAcJrAntlwAQAQAaAAcJrAntlwAQAQAAAA==.',
Jo='Jofixit:BAABLgAECn9eAAIaAAkJVCAgDwDXAgAaAAkJVCAgDwDXAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaelix:BAAALgAECgQJBwABLgAECgkJLgAOAOsWAA==.Kaepop:BAABLgAECn8TAAIUAAgJfBEFcQBRAQAUAAgJfBEFcQBRAQAAAA==.Kanda:BAACLgAFFH8IAAIaAAMJBxaYLwDcAAAaAAMJBxaYLwDcAAAuAAQKfx8AAhoACQkRHfUiADQCABoACQkRHfUiADQCAAAA.Kastarnu:BAAALgADCgMJAwAAAA==.Kasunas:BAAALgAECgMJAQABLgAECgcJCgANAAAAAA==.Kaynub:BAABLgAECn8zAAMaAAkJDCNVDQDoAgAaAAkJDCNVDQDoAgAbAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9bAAIaAAkJqyCEDgDdAgAaAAkJqyCEDgDdAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8TAAMhAAUJpBf5KQAgAQAhAAQJpBf5KQAgAQAiAAEJAACREwAAAAAuAAQKf0YAAyIACQkZIP0CAPgCACIACAmeH/0CAPgCACEACQmlGeICAKkBAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMOAAgJsBovEwDeAQAOAAgJsBovEwDeAQAPAAEJAACQrgEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8VAAIEAAcJdxe5FwBeAQAEAAcJdxe5FwBeAQAuAAQKfx4AAgQACAmkGlwXAFwCAAQACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.Kimbolee:BAAALgAECgYJCgAAAA==.',
Ko='Kobane:BAABLgAECn8iAAIGAAUJTQ0TJACRAAAGAAUJTQ0TJACRAAABLgAECgYJCQANAAAAAA==.Kodali:BAAALgAFFAIJAgAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.Kylekorver:BAAALgAECgEJAwAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lockemup:BAAALgADCgMJAwAAAA==.Lohuugg:BAAALgAECgQJBAABLgAFFAQJCwACAGwYAA==.Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgkJEwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Macheon:BAAALgAECgQJBAAAAA==.Madashell:BAAALgAECgQJBQAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Madtrip:BAAALgADCgUJBQAAAA==.Maeeba:BAABLgAECn8kAAICAAgJbQmpDgD/AAACAAgJbQmpDgD/AAAAAA==.Maerwyn:BAAALgAECgEJAQAAAA==.Magicpantiez:BAABLgAECn8ZAAISAAgJkh1XPwB7AgASAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgANAAAAAA==.Malexling:BAACLgAFFH8NAAIRAAMJEhT/OQCsAAARAAMJEhT/OQCsAAAuAAQKf1kAAhEACQnAIKICAOECABEACQnAIKICAOECAAAA.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8gAAISAAUJLBdfMQD5AAASAAUJLBdfMQD5AAAuAAQKfykAAhIACQn9HEI4ADcCABIACQn9HEI4ADcCAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMVAAkJKhTiLABwAQAVAAgJoRLiLABwAQAXAAkJBwNHRwDKAAAAAA==.Mitternacht:BAACLgAFFH8MAAIEAAMJJRF0HgCjAAAEAAMJJRF0HgCjAAAuAAQKfzsAAgQACQksIrYEABUDAAQACQksIrYEABUDAAAA.',
Mo='Monen:BAAALgAECgcJAgAAAA==.Monkalicious:BAAALgAECgEJAQAAAA==.Moodew:BAAALgAECgUJBQAAAA==.Mooncraig:BAABLgAECn9bAAULAAkJ7BulDgBzAgALAAkJ7BulDgBzAgAKAAcJ+BeDBwBBAQAJAAQJNxc8KgAKAQABAAMJaw8pMgCXAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.Mortamacee:BAAALgAECgYJDAABLgAECggJGQAQAGMgAA==.',
Ms='Msdeath:BAACLgAFFH8MAAIJAAIJGyKCDADGAAAJAAIJGyKCDADGAAAuAAQKf10AAgkACQkAJV4AAEcDAAkACQkAJV4AAEcDAAAA.',
Na='Naiu:BAAALgAECgUJBQABLgAECggJFQADAHwWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgANAAAAAA==.Nargrark:BAAALgAECgUJBwAAAA==.Nashalion:BAABLgAFFH8GAAMdAAIJJwWQFABtAAAdAAIJJwWQFABtAAAOAAEJYwHPRgAdAAABLgAECgkJFgABAC8aAA==.Nazureser:BAAALgAECgMJAwABLgAFFAcJFQAEAHcXAA==.',
Ne='Nemeeia:BAAALgAECgcJEwAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIgAAgJYBcdFQBoAgAgAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn9LAAIYAAgJFBitBACnAQAYAAgJFBitBACnAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Or='Orin:BAAALgAECgUJBQAAAA==.Ororro:BAABLgAECn8hAAIaAAgJvw+gDwBZAQAaAAgJvw+gDwBZAQAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH84AAIZAAkJsyMMAAA8AgAZAAkJsyMMAAA8AgAuAAQKf0UAAhkACQkIJkAAAMcDABkACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phrozencurse:BAAALgADCgQJBAAAAA==.Phrozensoul:BAAALgADCgYJCgAAAA==.Phrozenspark:BAAALgADCgMJAwAAAA==.Phyllip:BAABLgAECn80AAIVAAgJFRp/IQC6AQAVAAgJFRp/IQC6AQAAAA==.',
Pi='Picolás:BAABLgAECn8iAAISAAgJhR3wDAB5AQASAAgJhR3wDAB5AQAAAA==.',
Po='Pog:BAAALgAFFAIJAwAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgAECgYJBgAAAA==.Primrose:BAABLgAECn8vAAIHAAkJ4BAXHgDdAQAHAAkJ4BAXHgDdAQAAAA==.Probono:BAABLgAECn8oAAIVAAcJywoyQgAHAQAVAAcJywoyQgAHAQAAAA==.',
Ps='Psalmwon:BAAALgAECgMJAwAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Qw='Qwing:BAAALgAECgEJAQABLgAECgkJFgABAC8aAA==.',
Ra='Rageleaf:BAAALgAECgYJEAAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Rakus:BAAALgAECgEJAQAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAACLgAFFH8LAAIeAAIJaRB4CACVAAAeAAIJaRB4CACVAAAuAAQKfzwABB4ACQlNGbwAAFICAB4ACQlNGbwAAFICAAIABQn/AyARAVcAAAYAAQnFAnBIABcAAAAA.',
Re='Reliasht:BAAALgAECgMJAwAAAA==.Reprises:BAABLgAECn8pAAMWAAkJqyKiBAD+AgAWAAkJqyKiBAD+AgAUAAgJxBdUQgDBAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAMAH4UAA==.Restdrag:BAAALgAECgEJAQAAAA==.Revini:BAABLgAECn8dAAIOAAgJcSSKAgBEAwAOAAgJcSSKAgBEAwAAAA==.Rezø:BAACLgAFFH8LAAMHAAYJmwfKEwDtAAAHAAYJmwfKEwDtAAAXAAEJnQGpPQAlAAAuAAQKfyYABAcABwmYEjEuAGkBAAcABglRFTEuAGkBABcAAgmSC1VsADkAABUAAQmSEGUjADMAAAAA.',
Ro='Roadkillinn:BAABLgAECn8kAAMZAAkJVA22HQCvAQAZAAkJVA22HQCvAQAbAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgAECgEJAgAAAA==.',
Sa='Sableye:BAACLgAFFH8WAAIUAAQJChqGOgA7AQAUAAQJChqGOgA7AQAuAAQKfzsAAhQACQnuGp0cAGgCABQACQnuGp0cAGgCAAAA.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scounddrel:BAABLgAFFH8HAAMaAAMJng7LOAC9AAAaAAMJng7LOAC9AAAbAAEJGwHPPAAsAAAAAA==.Scruffy:BAABLgAECn9YAAITAAkJWyOnAAAMAwATAAkJWyOnAAAMAwAAAA==.',
Se='Seferres:BAACLgAFFH8bAAIMAAcJrCIaCgDvAQAMAAcJrCIaCgDvAQAuAAQKfygAAwwACQkIJeEKAN0CAAwACQkIJeEKAN0CAAUAAQksF5muAEMAAAAA.Selina:BAABLgAFFH8nAAISAAcJhyBgCgBYAgASAAcJhyBgCgBYAgAAAA==.Senortickle:BAABLgAECn8ZAAIBAAkJmyQyAgAMAwABAAkJmyQyAgAMAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8IAAIUAAMJqQuYaQC5AAAUAAMJqQuYaQC5AAAuAAQKfx4AAxQACAkbEEJVAKQBABQACAkbEEJVAKQBACMAAglSEIMmAFEAAAEuAAUUBwkbAAwArCIA.Shawts:BAABLgAECn8bAAISAAcJLhHKnwCXAQASAAcJLhHKnwCXAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAFFAYJCwAHAJsHAA==.',
Sk='Skeptimus:BAAALgADCgEJAQAAAA==.Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgYJBgAAAA==.',
Sn='Snowflower:BAAALgADCgYJBgAAAA==.',
So='Solar:BAABLgAFFH8GAAIUAAUJxwHxQgBbAAAUAAUJxwHxQgBbAAAAAA==.Solàire:BAAALgAECgEJAQABLgAECgkJRgAOAL0gAA==.Sonicice:BAAALgAECgEJAwAAAA==.Sourdumpling:BAABLgAECn8fAAIFAAgJHwxrTQA3AQAFAAgJHwxrTQA3AQAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAFACsbAA==.Steve:BAABLgAECn8WAAMbAAcJJQ9oOQB9AQAbAAcJJQ9oOQB9AQAZAAEJCQX6aAAsAAAAAA==.Stimutax:BAABLgAECn8kAAIkAAkJ2AY9CAAQAQAkAAkJ2AY9CAAQAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAIQAAcJ1yBJGgBCAgAQAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJEwAAAA==.Taurenvar:BAABLgAECn8uAAIcAAkJxh1YBwBZAgAcAAkJxh1YBwBZAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAACLgAFFH8LAAQJAAQJ9hF7IACbAAAJAAMJ9hF7IACbAAAKAAMJeQN/ZQBRAAABAAEJAACDJgAAAAAuAAQKfyUABAkACQkEFI8FAEQBAAkACQkEFI8FAEQBAAsABAlhBOhnAIIAAAEAAQk6Ax45ACQAAAAA.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIiAAgJBw5rCwBfAQAiAAgJBw5rCwBfAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgABLgAECgkJKAAMAP8TAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAILAAkJVSRvAwAzAwALAAkJVSRvAwAzAwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIfAAcJdhd5FwBkAQAfAAcJdhd5FwBkAQAAAA==.',
Ty='Tyn:BAAALgAECggJBwAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Va='Varric:BAAALgADCgUJBQAAAA==.',
Ve='Velariaena:BAAALgAECgQJBAABLgAFFAMJDAADAIkWAA==.Veldramaar:BAAALgADCgEJAQAAAA==.Velidora:BAAALgAFFAEJAgAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8lAAIfAAkJvBQQFQCAAQAfAAkJvBQQFQCAAQAAAA==.Vilvaxis:BAAALgAECgQJBAABLgAFFAMJDAADAIkWAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgYJBwAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIlAAkJtRtmCgBEAgAlAAkJtRtmCgBEAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
['Wî']='Wîene:BAAALgAECgYJBgABLgAFFAYJCwAHAJsHAA==.',
Xe='Xergioc:BAAALgAECgYJCgAAAA==.Xeriator:BAABLgAECn9QAAIaAAkJDA/dRwDKAQAaAAkJDA/dRwDKAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAUJFAADAGwXAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAABLgAECn8UAAIYAAkJwgdwSAAkAQAYAAkJwgdwSAAkAQAAAA==.Zaligator:BAABLgAECn8fAAQiAAkJmRRLCQCWAQAiAAgJ0RVLCQCWAQAmAAMJtwUAPgB7AAAhAAIJuQfSfwBfAAAAAA==.Zaurk:BAAALgAECgIJAgAAAA==.Zayuna:BAABLgAFFH8KAAMHAAMJAw7aNAC4AAAHAAMJAw7aNAC4AAAVAAEJ7AozPABBAAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAIaAAkJJAsQVQCkAQAaAAkJJAsQVQCkAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAIVAAUJGBMXCABGAQAVAAUJGBMXCABGAQAuAAQKfygAAhUACAk6ISsNALECABUACAk6ISsNALECAAAA.Zombear:BAAALgAFFAIJAgABLgAFFAkJOAAZALMjAA==.',
Zu='Zugzug:BAAALgAECgIJAgAAAA==.Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMFAAkJKxunEQCSAgAFAAkJKxunEQCSAgATAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn80AAICAAgJIQu1DwDvAAACAAgJIQu1DwDvAAAAAA==.',
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
