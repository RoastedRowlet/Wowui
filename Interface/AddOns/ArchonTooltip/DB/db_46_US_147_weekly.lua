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

local lookup = {'Druid-Feral','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Priest-Discipline','Unknown-Unknown','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','DeathKnight-Frost','Rogue-Subtlety','Warrior-Arms','Warlock-Affliction','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Absydion:BAAALgAFFAEJAwAAAA==.',
Ac='Acherøn:BAAALgAECggJCAAAAA==.',
Ad='Adema:BAAALgADCgQJBQABLgAECgkJFgABAC8aAA==.',
Ae='Aellaleander:BAAALgAECggJDAAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwACAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Arathelie:BAAALgAFFAIJAgAAAA==.Aratune:BAAALgADCgEJAQAAAA==.Arazen:BAAALgAECgUJCQAAAA==.Arcjanhealer:BAAALgAECgYJEgAAAA==.Ari:BAAALgAECggJCAAAAA==.Arianá:BAAALgAFFAEJAQAAAA==.',
As='Asahhealer:BAACLgAFFH8MAAIDAAMJiRauJgCxAAADAAMJiRauJgCxAAAuAAQKfzQAAwMACAkBHuMUAKQCAAMACAkBHuMUAKQCAAQABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAFACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMDAAkJYhNUKgASAgADAAkJYhNUKgASAgAEAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAICAAQJbBgWEABgAQACAAQJbBgWEABgAQAuAAQKfzYAAwIACQnhJL4KAPoCAAIACQnhJL4KAPoCAAYAAQkAAA5pAD8AAAAA.Aurõrä:BAABLgAECn8UAAIGAAYJQgrdHQC6AAAGAAYJQgrdHQC6AAAAAA==.',
Av='Averlence:BAABLgAFFH8GAAIHAAMJfAXwOACjAAAHAAMJfAXwOACjAAAAAA==.',
Aw='Aweyna:BAAALgAECgQJAwAAAA==.',
Az='Azlia:BAAALgAFFAQJBAABLgAECgMJAwAIAAAAAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8NAAQJAAUJGB/rBwAbAQAJAAUJGB/rBwAbAQAKAAMJfgw2UQB+AAALAAEJ8wRCUwAxAAABLgAFFAcJHAAMAKwiAA==.',
Ba='Bahumn:BAABLgAECn8WAAIBAAkJLxrjBQABAQABAAkJLxrjBQABAQAAAA==.Balboga:BAAALgADCggJCAABLgAECgYJCQAIAAAAAA==.Bangpôwbôôm:BAABLgAECn9GAAMNAAkJvSCWBQDNAgANAAkJhyCWBQDNAgAOAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMPAAkJChLAJADgAQAPAAkJChLAJADgAQAQAAUJpBDSCgGrAAAAAA==.Beryl:BAAALgAECgQJAwAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIRAAgJaxwiNQCfAgARAAgJaxwiNQCfAgABLgAFFAMJBQASADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgcJDgABLgAECggJGQAPAGMgAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwATAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAIAAAAAA==.',
Br='Bralantha:BAAALgAECgEJAQABLgAFFAMJDAADAIkWAA==.Brivia:BAAALgAECgUJCAABLgAFFAQJCwACAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAAUABgTAA==.Bullseye:BAAALgAECgMJAwAAAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Burningfel:BAAALgAECgIJAgAAAA==.Buruwar:BAAALgAECggJEwAAAA==.',
Ca='Calgor:BAAALgADCgEJAQAAAA==.Calihye:BAAALgAFFAEJAQABLgAFFAkJIwAKAA0cAA==.Calverine:BAAALgAECgEJAQAAAA==.Camel:BAACLgAFFH8OAAMQAAIJLwgQUABzAAAQAAIJLwgQUABzAAAPAAEJxASJKgArAAAuAAQKf2QAAxAACQmFGTEGAD4CABAACQmFGTEGAD4CAA8ACQkLEEo9AFABAAAA.Cattlestance:BAABLgAECn8bAAIVAAkJDRP0FACkAQAVAAkJDRP0FACkAQAAAA==.',
Ce='Ceriebrium:BAAALgAECgEJAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgAECgEJAQAAAA==.',
Cl='Clamchoder:BAAALgAECgEJAQAAAA==.Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgYJDAAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwACAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgAECgIJAgAAAA==.Dashdashdash:BAABLgAECn+KAAIWAAkJiyQGAQApAwAWAAkJiyQGAQApAwAAAA==.Davethediva:BAAALgAECgEJAgAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIVAAgJ5BZUFgCSAQAVAAgJ5BZUFgCSAQAAAA==.',
De='Deathcraig:BAAALgAECgQJBAAAAA==.Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDQAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8kAAIXAAkJLxV/IQC2AQAXAAkJLxV/IQC2AQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Di='Dirge:BAABLgAFFH8HAAIOAAIJixuMUQC3AAAOAAIJixuMUQC3AAAAAA==.',
Do='Dodgydave:BAAALgAECgEJAQAAAA==.Doomzeer:BAABLgAECn8WAAMUAAcJaRsFBADaAQAUAAcJaRsFBADaAQAHAAUJ0hoZBwCMAQABLgAFFAUJEgAYAKkcAA==.Dopehustsla:BAAALgADCgUJCQAAAA==.Dottacus:BAAALgADCgEJAQABLgAECggJCQAIAAAAAA==.',
Dr='Draggussy:BAABLgAECn8jAAIRAAkJlxUUQgAWAgARAAkJlxUUQgAWAgAAAA==.Dragoonall:BAAALgADCgMJAwAAAA==.Dragoonette:BAAALgADCgUJBwAAAA==.Drakarys:BAAALgAECgQJCAAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.Drezz:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIJAAkJSx1KBgCdAgAJAAkJSx1KBgCdAgAAAA==.',
['Dë']='Dëathlock:BAAALgAECgQJBAABLgAECgkJNQATAD8MAA==.',
Ec='Ectasee:BAABLgAECn8zAAMDAAkJRyQxAwCPAwADAAkJRyQxAwCPAwAEAAMJ8RCUcgCTAAAAAA==.',
Ei='Eianhander:BAAALgAECgQJBAAAAA==.Eirenus:BAABLgAECn8UAAMFAAcJVAt/cADHAAAFAAcJVAt/cADHAAAMAAYJiA0OUwC4AAABLgAFFAYJCwAHAJsHAA==.',
El='Element:BAAALgAFFAIJAgAAAA==.',
Em='Emi:BAACLgAFFH8OAAMEAAgJHgwzMADSAAAEAAYJmAgzMADSAAADAAMJLhZhXACTAAAuAAQKfyMAAwQACQlkFjU4AFcBAAQACAmwFTU4AFcBAAMACAlMFjVZAFIBAAAA.',
En='Enfilade:BAAALgAECgQJBAAAAA==.Enøch:BAAALgAFFAEJAgAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8tAAQZAAkJ0R9/BADlAgAZAAkJ0R9/BADlAgAaAAEJZB/yQgBZAAAbAAEJXRtiNABLAAABLgAECggJQgASALAjAA==.',
Fa='Fanuc:BAABLgAECn9AAAMDAAkJQyLdBgBCAwADAAkJQyLdBgBCAwAcAAgJLxy2AQADAgAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAITAAgJjxHhfgAiAQATAAgJjxHhfgAiAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8vAAINAAkJ6xZiAwDuAQANAAkJ6xZiAwDuAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAABLgAFFH8HAAMVAAUJdAfTFgBsAAAVAAQJmgfTFgBsAAAYAAEJ2wZTNwBBAAABLgAECgMJAwAIAAAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAIAAAAAA==.',
Fo='Forthrich:BAACLgAFFH8QAAIQAAMJjgnmPACpAAAQAAMJjgnmPACpAAAuAAQKfz8AAhAACQnRDcJuAJEBABAACQnRDcJuAJEBAAAA.Fozuul:BAABLgAECn8UAAMKAAkJBRLEKwD7AQAKAAkJBRLEKwD7AQALAAEJpRW+hABAAAABLgAECgkJJwAFACsbAA==.',
Fr='Frankié:BAAALgADCgEJAQAAAA==.Freeports:BAAALgAECgEJAQAAAA==.Frozendeath:BAAALgAECgEJAQAAAA==.Fruit:BAAALgAECgYJCQAAAA==.Frâust:BAABLgAECn8hAAIdAAkJlxBoAgDAAQAdAAkJlxBoAgDAAQAAAA==.',
Fu='Furiousorc:BAAALgADCgkJCQABLgAECggJHwATAI8RAA==.',
Ga='Galadril:BAAALgADCgkJDwAAAA==.Galaedra:BAAALgADCgEJAQAAAA==.Gandulf:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMPAAgJAh0TEgCCAgAPAAgJAh0TEgCCAgAQAAUJABYvrAAlAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECgkJIwAeAKgaAA==.',
Gr='Grimhayze:BAAALgAECgEJAgAAAA==.Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8gAAMYAAUJ8CMkBwBzAQAYAAUJ8CMkBwBzAQAfAAEJDyJkEgBkAAAAAA==.Gurnsey:BAAALgAECgUJDAAAAA==.Gutholoydne:BAABLgAECn8bAAIgAAcJiRT+CwB6AQAgAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgAECgYJCQAAAA==.',
Ha='Hakunamatata:BAAALgAECgEJAQAAAA==.Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAABLgAECn8bAAIWAAYJ6xtxBgBjAQAWAAYJ6xtxBgBjAQAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMXAAkJhQ9MPQBFAQAXAAYJwxBMPQBFAQAUAAkJBwx6SQDpAAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQASADEYAA==.Hirculos:BAABLgAECn8hAAIYAAgJyRcsIgDhAQAYAAgJyRcsIgDhAQAAAA==.',
Ho='Hoggle:BAAALgAECgEJAQAAAA==.Hokkai:BAAALgADCgEJAQAAAA==.Holix:BAAALgAECggJCAAAAA==.Holyfrog:BAABLgAECn9IAAMPAAkJaxsRFwBZAgAPAAkJaxsRFwBZAgAQAAIJQgi7VQFaAAAAAA==.Holythis:BAACLgAFFH8XAAIhAAQJlg0wCwDCAAAhAAQJlg0wCwDCAAAuAAQKfy0AAyEACQnwFqMGAHwCACEACQnwFqMGAHwCABAAAQkAAFPZAQAAAAAA.',
Hu='Huntosi:BAAALgAECgEJAQAAAA==.Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
If='Ifrit:BAABLgAFFH8OAAITAAQJKBHZJAD0AAATAAQJKBHZJAD0AAAAAA==.',
Ig='Ignis:BAABLgAECn89AAMBAAkJzhRkDADyAQABAAkJzhRkDADyAQAJAAgJ4AjPNADVAAAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMTAAkJtxkkJQA6AgATAAkJtxkkJQA6AgAWAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAACLgAFFH8JAAIeAAMJIxTVEwDjAAAeAAMJIxTVEwDjAAAuAAQKf14AAh4ACQkxIDoCAAwCAB4ACQkxIDoCAAwCAAAA.Injunjoe:BAAALgAECgQJBQAAAA==.',
Io='Ionadaria:BAAALgAECgMJAwAAAA==.',
Is='Isneeztomuch:BAAALgAECgEJAQAAAA==.Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janaru:BAAALgAECgEJAgABLgAECgcJCgAIAAAAAA==.Janelik:BAABLgAECn8tAAIRAAcJEwUuLACkAAARAAcJEwUuLACkAAAAAA==.',
Je='Jeeto:BAAALgAFFAEJAQAAAA==.Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jimihendrix:BAAALgAECgYJCAAAAA==.Jinxi:BAABLgAECn8jAAIaAAcJrAntlwAQAQAaAAcJrAntlwAQAQAAAA==.',
Jo='Jofixit:BAABLgAECn9eAAIaAAkJVCAgDwDXAgAaAAkJVCAgDwDXAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaelix:BAAALgAECgQJBwABLgAECgkJLwANAOsWAA==.Kaepop:BAABLgAECn8TAAITAAgJfBEFcQBRAQATAAgJfBEFcQBRAQAAAA==.Kanda:BAACLgAFFH8IAAIaAAMJBxbAMgDbAAAaAAMJBxbAMgDbAAAuAAQKfx8AAhoACQkRHfUiADQCABoACQkRHfUiADQCAAAA.Kastarnu:BAAALgADCgMJAwAAAA==.Kasunas:BAAALgAECgMJAQABLgAECgcJCgAIAAAAAA==.Kaynub:BAABLgAECn8zAAMaAAkJDCNVDQDoAgAaAAkJDCNVDQDoAgAbAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9bAAIaAAkJqyCEDgDdAgAaAAkJqyCEDgDdAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8UAAMiAAYJYRf5KQAgAQAiAAUJYRf5KQAgAQAjAAEJAACREwAAAAAuAAQKf0YAAyMACQkZIP0CAPgCACMACAmeH/0CAPgCACIACQmlGT4DAKQBAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMNAAgJsBovEwDeAQANAAgJsBovEwDeAQAOAAEJAACQrgEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8VAAIEAAcJdxe5FwBeAQAEAAcJdxe5FwBeAQAuAAQKfx4AAgQACAmkGlwXAFwCAAQACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.Kimbolee:BAAALgAECgYJCgAAAA==.',
Ko='Kobane:BAABLgAECn8iAAIGAAUJTQ0TJACRAAAGAAUJTQ0TJACRAAABLgAECgYJCQAIAAAAAA==.Kodali:BAAALgAFFAIJAgAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.Kylekorver:BAAALgAECgEJAwAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lockemup:BAAALgADCgMJAwAAAA==.Lohuugg:BAAALgAECgQJBAABLgAFFAQJCwACAGwYAA==.Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgkJEwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Macheon:BAAALgAECgQJBAAAAA==.Madashell:BAAALgAECgQJBQAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Madtrip:BAAALgADCgUJBQAAAA==.Maeeba:BAABLgAECn8kAAICAAgJbQngEAD6AAACAAgJbQngEAD6AAAAAA==.Maerwyn:BAAALgAECgEJAQAAAA==.Magicpantiez:BAABLgAECn8ZAAIRAAgJkh1XPwB7AgARAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgAIAAAAAA==.Malexling:BAACLgAFFH8NAAIQAAMJEhS3PACqAAAQAAMJEhS3PACqAAAuAAQKf1kAAhAACQnAICsDANwCABAACQnAICsDANwCAAAA.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8hAAIRAAYJqBYaJQBIAQARAAYJqBYaJQBIAQAuAAQKfykAAhEACQn9HEI4ADcCABEACQn9HEI4ADcCAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMUAAkJKhTiLABwAQAUAAgJoRLiLABwAQAXAAkJBwNHRwDKAAAAAA==.Mitternacht:BAACLgAFFH8NAAIEAAQJUg6qFwDbAAAEAAQJUg6qFwDbAAAuAAQKfzsAAgQACQksIrYEABUDAAQACQksIrYEABUDAAAA.',
Mo='Monen:BAAALgAECgcJAgAAAA==.Monkalicious:BAAALgAECgEJAQAAAA==.Moodew:BAAALgAECgUJBQAAAA==.Mooncraig:BAABLgAECn9bAAULAAkJ7BulDgBzAgALAAkJ7BulDgBzAgAKAAcJ+BeICABBAQAJAAQJNxc8KgAKAQABAAMJaw8pMgCXAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.Mortamacee:BAAALgAECgYJDAABLgAECggJGQAPAGMgAA==.',
Ms='Msdeath:BAACLgAFFH8OAAIJAAIJGyJKDQDDAAAJAAIJGyJKDQDDAAAuAAQKf2QAAgkACQkoJV8AAE8DAAkACQkoJV8AAE8DAAAA.',
Na='Naiu:BAAALgAECgUJBQABLgAECgkJFgADAMkWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgAIAAAAAA==.Nargrark:BAAALgAECgUJBwAAAA==.Nashalion:BAABLgAFFH8GAAMdAAIJJwVJFgBrAAAdAAIJJwVJFgBrAAANAAEJYwHPRgAdAAABLgAECgkJFgABAC8aAA==.Nazureser:BAAALgAECgMJAwABLgAFFAcJFQAEAHcXAA==.',
Ne='Nemeeia:BAABLgAECn8UAAIBAAcJ7wd3CwB7AAABAAcJ7wd3CwB7AAAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIeAAgJYBcdFQBoAgAeAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAACLgAFFH8FAAIYAAMJwA/6GQDTAAAYAAMJwA/6GQDTAAAuAAQKf00AAhgACQkDGOsDAO0BABgACQkDGOsDAO0BAAAA.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.Norielin:BAAALgAECgYJBgAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Or='Orin:BAAALgAECgUJBQAAAA==.Ororro:BAABLgAECn8hAAIaAAgJvw8oEgBYAQAaAAgJvw8oEgBYAQAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8+AAIZAAkJsyMMAAA8AgAZAAkJsyMMAAA8AgAuAAQKf0UAAhkACQkIJkAAAMcDABkACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phrozencurse:BAAALgADCgQJBAAAAA==.Phrozensoul:BAAALgADCgYJCgAAAA==.Phrozenspark:BAAALgADCgMJAwAAAA==.Phrozentron:BAAALgADCgQJAwAAAA==.Phyllip:BAABLgAECn80AAIUAAgJFRp/IQC6AQAUAAgJFRp/IQC6AQAAAA==.',
Pi='Picolás:BAABLgAECn8iAAIRAAgJhR0eDwB1AQARAAgJhR0eDwB1AQAAAA==.',
Po='Pog:BAAALgAFFAIJAwAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgAECgYJBgAAAA==.Primrose:BAABLgAECn8vAAIHAAkJ4BAXHgDdAQAHAAkJ4BAXHgDdAQAAAA==.Probono:BAABLgAECn8uAAIUAAcJUAuYFACXAAAUAAcJUAuYFACXAAAAAA==.',
Ps='Psalmwon:BAAALgAECgMJAwAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Qw='Qwing:BAAALgAECgEJAQABLgAECgkJFgABAC8aAA==.',
Ra='Rageleaf:BAAALgAECgYJEAAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Rakus:BAAALgAECgEJAQAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAACLgAFFH8LAAIgAAIJaRArCQCUAAAgAAIJaRArCQCUAAAuAAQKfzwABCAACQlNGeUAAE0CACAACQlNGeUAAE0CAAIABQn/AyARAVcAAAYAAQnFAnBIABcAAAAA.',
Re='Reliasht:BAAALgAECgMJAwAAAA==.Reprises:BAABLgAECn8pAAMWAAkJqyKiBAD+AgAWAAkJqyKiBAD+AgATAAgJxBdUQgDBAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAgJGAAJAHYhAA==.Restdrag:BAAALgAECgEJAQAAAA==.Revini:BAABLgAECn8dAAINAAgJcSSKAgBEAwANAAgJcSSKAgBEAwAAAA==.Rezø:BAACLgAFFH8LAAMHAAYJmwerFQDhAAAHAAYJmwerFQDhAAAXAAEJnQGpPQAlAAAuAAQKfyYABAcABwmYEjEuAGkBAAcABglRFTEuAGkBABcAAgmSC1VsADkAABQAAQmSEIMoADIAAAAA.',
Ro='Roadkillinn:BAABLgAECn8kAAMZAAkJVA22HQCvAQAZAAkJVA22HQCvAQAbAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgAECgEJAgAAAA==.',
Sa='Sableye:BAACLgAFFH8WAAITAAQJChqGOgA7AQATAAQJChqGOgA7AQAuAAQKfzsAAhMACQnuGp0cAGgCABMACQnuGp0cAGgCAAAA.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Schithappens:BAAALgAECgEJAQAAAA==.Scounddrel:BAABLgAFFH8HAAMaAAMJng64PAC6AAAaAAMJng64PAC6AAAbAAEJGwHPPAAsAAAAAA==.Scruffy:BAABLgAECn9hAAISAAkJfiOxAAAdAwASAAkJfiOxAAAdAwAAAA==.',
Se='Seferres:BAACLgAFFH8cAAIMAAcJrCIaCgDvAQAMAAcJrCIaCgDvAQAuAAQKfyoAAwwACQkIJeEKAN0CAAwACQkIJeEKAN0CAAUAAQksF5muAEMAAAAA.Selina:BAABLgAFFH8nAAIRAAcJhyAiDABKAgARAAcJhyAiDABKAgAAAA==.Senortickle:BAABLgAECn8ZAAIBAAkJmyQyAgAMAwABAAkJmyQyAgAMAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8IAAITAAMJqQuYaQC5AAATAAMJqQuYaQC5AAAuAAQKfx4AAxMACAkbEEJVAKQBABMACAkbEEJVAKQBACQAAglSEIMmAFEAAAEuAAUUBwkcAAwArCIA.Shawts:BAABLgAECn8bAAIRAAcJLhHKnwCXAQARAAcJLhHKnwCXAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shuchu:BAAALgAECgIJAgAAAA==.Shìva:BAAALgAECgYJBgAAAA==.Shînon:BAAALgADCgUJBQABLgAFFAYJCwAHAJsHAA==.',
Sk='Skeptimus:BAAALgADCgEJAQAAAA==.Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgYJBgAAAA==.',
Sn='Snowflower:BAAALgADCgYJBgAAAA==.',
So='Solar:BAABLgAFFH8GAAITAAUJxwEVRwBXAAATAAUJxwEVRwBXAAAAAA==.Solàire:BAAALgAECgEJAQABLgAECgkJRgANAL0gAA==.Sonicice:BAAALgAECgEJAwAAAA==.Sourdumpling:BAABLgAECn8fAAIFAAgJHwxrTQA3AQAFAAgJHwxrTQA3AQAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAFACsbAA==.Steve:BAABLgAECn8WAAMbAAcJJQ9oOQB9AQAbAAcJJQ9oOQB9AQAZAAEJCQX6aAAsAAAAAA==.Stimutax:BAABLgAECn8kAAIlAAkJ2AY9CAAQAQAlAAkJ2AY9CAAQAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAIPAAcJ1yBJGgBCAgAPAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJEwAAAA==.Taurenvar:BAABLgAECn8uAAIcAAkJxh1YBwBZAgAcAAkJxh1YBwBZAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAACLgAFFH8LAAQJAAQJ9hF7IACbAAAJAAMJ9hF7IACbAAAKAAMJeQN/ZQBRAAABAAEJAACDJgAAAAAuAAQKfyUABAkACQkEFEsGAEMBAAkACQkEFEsGAEMBAAsABAlhBOhnAIIAAAEAAQk6Ax45ACQAAAAA.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thekeres:BAAALgAECgMJAwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIjAAgJBw5rCwBfAQAjAAgJBw5rCwBfAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgABLgAECgkJKAAMAP8TAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAILAAkJVSRvAwAzAwALAAkJVSRvAwAzAwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIhAAcJdhd5FwBkAQAhAAcJdhd5FwBkAQAAAA==.',
Ty='Tyn:BAAALgAECggJBwAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Va='Varric:BAAALgADCgUJBQAAAA==.',
Ve='Velariaena:BAAALgAECgQJBAABLgAFFAMJDAADAIkWAA==.Veldramaar:BAAALgADCgEJAQAAAA==.Velidora:BAAALgAFFAEJAgAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8lAAIhAAkJvBQQFQCAAQAhAAkJvBQQFQCAAQAAAA==.Vilvaxis:BAAALgAECgQJBAABLgAFFAMJDAADAIkWAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECggJEwAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIfAAkJtRtmCgBEAgAfAAkJtRtmCgBEAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
['Wî']='Wîene:BAAALgAECgYJBgABLgAFFAYJCwAHAJsHAA==.',
Xe='Xergioc:BAAALgAECgYJCgAAAA==.Xeriator:BAABLgAECn9QAAIaAAkJDA/dRwDKAQAaAAkJDA/dRwDKAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAYJFQADAJIYAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAABLgAECn8UAAIYAAkJwgdwSAAkAQAYAAkJwgdwSAAkAQAAAA==.Zaligator:BAABLgAECn8fAAQjAAkJmRRLCQCWAQAjAAgJ0RVLCQCWAQAmAAMJtwUAPgB7AAAiAAIJuQfSfwBfAAAAAA==.Zaurk:BAAALgAECgIJAgAAAA==.Zayuna:BAABLgAFFH8KAAMHAAMJAw7aNAC4AAAHAAMJAw7aNAC4AAAUAAEJ7AozPABBAAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAIaAAkJJAsQVQCkAQAaAAkJJAsQVQCkAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAIUAAUJGBMXCABGAQAUAAUJGBMXCABGAQAuAAQKfygAAhQACAk6ISsNALECABQACAk6ISsNALECAAAA.Zombear:BAAALgAFFAIJAgABLgAFFAkJPgAZALMjAA==.',
Zu='Zugzug:BAAALgAECgIJAgAAAA==.Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMFAAkJKxunEQCSAgAFAAkJKxunEQCSAgASAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn89AAICAAkJswvtDQAjAQACAAkJswvtDQAjAQAAAA==.',
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
