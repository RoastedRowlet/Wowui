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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Priest-Discipline','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','DeathKnight-Frost','Hunter-BeastMastery','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Absydion:BAAALgAECgEJAQAAAA==.',
Ad='Adema:BAAALgADCgQJBQABLgAFFAIJAwABAAAAAA==.',
Ae='Aellaleander:BAAALgAECggJDAAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwACAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Aratune:BAAALgADCgEJAQAAAA==.Arazen:BAAALgADCgUJBgAAAA==.Arcjanhealer:BAAALgAECgEJAQAAAA==.Ari:BAAALgAECggJCAAAAA==.Arianá:BAAALgAFFAEJAQAAAA==.',
As='Asahhealer:BAACLgAFFH8HAAIDAAMJpg/AVACnAAADAAMJpg/AVACnAAAuAAQKfzQAAwMACAkBHuMUAKQCAAMACAkBHuMUAKQCAAQABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAFACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMDAAkJYhNUKgASAgADAAkJYhNUKgASAgAEAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAICAAQJbBgWEABgAQACAAQJbBgWEABgAQAuAAQKfzYAAwIACQnhJL4KAPoCAAIACQnhJL4KAPoCAAYAAQkAAA5pAD8AAAAA.Aurõrä:BAABLgAECn8UAAIGAAYJQgrdHQC6AAAGAAYJQgrdHQC6AAAAAA==.',
Av='Averlence:BAABLgAFFH8GAAIHAAMJfAXwOACjAAAHAAMJfAXwOACjAAAAAA==.',
Az='Azlia:BAAALgAFFAQJBAAAAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8JAAQIAAQJkhnRDwBdAAAIAAMJ7xzRDwBdAAAJAAMJfgxcFABdAAAKAAEJ8wRCUwAxAAABLgAFFAYJGgALAGUjAA==.',
Ba='Bahumn:BAAALgAECggJEwABLgAFFAIJAwABAAAAAA==.Balboga:BAAALgADCggJCAABLgAECgUJGgAGAM0JAA==.Bangpôwbôôm:BAABLgAECn9GAAMMAAkJvSCWBQDNAgAMAAkJhyCWBQDNAgANAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMOAAkJChLAJADgAQAOAAkJChLAJADgAQAPAAUJpBDSCgGrAAAAAA==.Beryl:BAAALgAECgQJAwAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIQAAgJaxwiNQCfAgAQAAgJaxwiNQCfAgABLgAFFAMJBQARADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgcJDgABLgAECggJGQAOAGMgAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwASAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgABAAAAAA==.',
Br='Brivia:BAAALgAECgUJCAABLgAFFAQJCwACAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAATABgTAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECggJEwAAAA==.',
Ca='Calgor:BAAALgADCgEJAQAAAA==.Camel:BAABLgAECn9RAAMPAAkJXxg2AgApAgAPAAkJXxg2AgApAgAOAAkJDBBKPQBQAQAAAA==.Cattlestance:BAABLgAECn8bAAIUAAkJDRP0FACkAQAUAAkJDRP0FACkAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clamchoder:BAAALgAECgEJAQAAAA==.Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgYJDAAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwACAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgAECgIJAgAAAA==.Dashdashdash:BAABLgAECn9gAAIVAAgJBCWaAADAAgAVAAgJBCWaAADAAgAAAA==.Davethediva:BAAALgAECgEJAgAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIUAAgJ5BZUFgCSAQAUAAgJ5BZUFgCSAQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDQAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8kAAIWAAkJMBV/IQC2AQAWAAkJMBV/IQC2AQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Do='Dodgydave:BAAALgAECgEJAQAAAA==.Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8jAAIQAAkJlxUUQgAWAgAQAAkJlxUUQgAWAgAAAA==.Dragoonall:BAAALgADCgMJAwAAAA==.Dragoonette:BAAALgADCgUJBwAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.Drezz:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIIAAkJSx1KBgCdAgAIAAkJSx1KBgCdAgAAAA==.',
['Dë']='Dëathlock:BAAALgAECgQJBAABLgAECgkJNQASAD8MAA==.',
Ec='Ectasee:BAABLgAECn8zAAMDAAkJRyQxAwCPAwADAAkJRyQxAwCPAwAEAAMJ8RCUcgCTAAAAAA==.',
Ei='Eianhander:BAAALgAECgQJBAAAAA==.Eirenus:BAAALgAECgcJEwABLgAFFAYJCwAHAJsHAA==.',
El='Element:BAAALgAECgcJDAAAAA==.',
Em='Emi:BAACLgAFFH8LAAMEAAYJggozMADSAAAEAAUJGAgzMADSAAADAAIJlBNhXACTAAAuAAQKfyIAAwQACAnEFTU4AFcBAAQABwnYFDU4AFcBAAMACAlMFjVZAFIBAAAA.',
En='Enfilade:BAAALgAECgQJBAAAAA==.Enøch:BAAALgAFFAEJAgAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8qAAMXAAkJxB9/BADlAgAXAAkJxB9/BADlAgAYAAEJXRtiNABLAAABLgAECggJKAARAG8iAA==.',
Fa='Fanuc:BAABLgAECn8/AAMDAAkJQyLdBgBCAwADAAkJQyLdBgBCAwAZAAgJLxyVAADhAQAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAISAAgJjxHhfgAiAQASAAgJjxHhfgAiAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8mAAIMAAkJSRa3AgAVAQAMAAkJSRa3AgAVAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJBAABLgAFFAQJBAABAAAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgABAAAAAA==.',
Fo='Forthrich:BAACLgAFFH8HAAIPAAMJjQL9kQCPAAAPAAMJjQL9kQCPAAAuAAQKfz8AAg8ACQnRDcJuAJEBAA8ACQnRDcJuAJEBAAAA.Fozuul:BAABLgAECn8UAAMJAAkJBRLEKwD7AQAJAAkJBRLEKwD7AQAKAAEJpRW+hABAAAABLgAECgkJJwAFACsbAA==.',
Fr='Frankié:BAAALgADCgEJAQAAAA==.Fruit:BAAALgAECgYJCQAAAA==.Frâust:BAABLgAECn8YAAIaAAgJlAxBAQA/AQAaAAgJlAxBAQA/AQAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMOAAgJAh0TEgCCAgAOAAgJAh0TEgCCAgAPAAUJABYvrAAlAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECggJHgAbAJEbAA==.',
Gr='Grimhayze:BAAALgAECgEJAgAAAA==.Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIcAAUJ8COlLwDxAQAcAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8bAAIdAAcJiRT+CwB6AQAdAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgAECgYJCQAAAA==.',
Ha='Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAABLgAECn8bAAIVAAYJ6xsXAgBqAQAVAAYJ6xsXAgBqAQAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMWAAkJhQ9MPQBFAQAWAAYJwxBMPQBFAQATAAkJBwx6SQDpAAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQARADEYAA==.Hirculos:BAABLgAECn8hAAIcAAgJyRcsIgDhAQAcAAgJyRcsIgDhAQAAAA==.',
Ho='Hoggle:BAAALgAECgEJAQAAAA==.Hokkai:BAAALgADCgEJAQAAAA==.Holix:BAAALgAECggJCAAAAA==.Holyfrog:BAABLgAECn9GAAMOAAkJaxsRFwBZAgAOAAkJaxsRFwBZAgAPAAIJQgi7VQFaAAAAAA==.Holythis:BAACLgAFFH8XAAIeAAQJlg0wCwDCAAAeAAQJlg0wCwDCAAAuAAQKfy0AAx4ACQnwFqMGAHwCAB4ACQnwFqMGAHwCAA8AAQkAAFPZAQAAAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn89AAMfAAkJzhRkDADyAQAfAAkJzhRkDADyAQAIAAgJ4AjPNADVAAAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMSAAkJtxkkJQA6AgASAAkJtxkkJQA6AgAVAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn9dAAIgAAkJMSD7AADaAQAgAAkJMSD7AADaAQAAAA==.Injunjoe:BAAALgAECgQJBAAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janaru:BAAALgAECgEJAgABLgAECgcJCgABAAAAAA==.Janelik:BAABLgAECn8jAAIQAAcJTQLF+wCzAAAQAAcJTQLF+wCzAAAAAA==.',
Je='Jeeto:BAAALgAECgEJAQAAAA==.Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jimihendrix:BAAALgAECgEJAQAAAA==.Jinxi:BAABLgAECn8jAAIbAAcJrAntlwAQAQAbAAcJrAntlwAQAQAAAA==.',
Jo='Jofixit:BAABLgAECn9dAAIbAAkJVCAgDwDXAgAbAAkJVCAgDwDXAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaelix:BAAALgAECgMJAwABLgAECgkJJgAMAEkWAA==.Kaepop:BAABLgAECn8TAAISAAgJfBEFcQBRAQASAAgJfBEFcQBRAQAAAA==.Kanda:BAACLgAFFH8FAAIbAAMJjRHsFgDpAAAbAAMJjRHsFgDpAAAuAAQKfx8AAhsACQkRHfUiADQCABsACQkRHfUiADQCAAAA.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8zAAMbAAkJDCNVDQDoAgAbAAkJDCNVDQDoAgAYAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9OAAIbAAkJDR+EDgDdAgAbAAkJDR+EDgDdAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8TAAMhAAUJpBf5KQAgAQAhAAQJpBf5KQAgAQAiAAEJAACREwAAAAAuAAQKf0EAAyIACQkZIP0CAPgCACIACAmeH/0CAPgCACEACQmCGKAVAC0CAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMMAAgJsBovEwDeAQAMAAgJsBovEwDeAQANAAEJAACQrgEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8VAAIEAAcJjhe5FwBeAQAEAAcJjhe5FwBeAQAuAAQKfx4AAgQACAmkGlwXAFwCAAQACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.Kimbolee:BAAALgAECgYJCgAAAA==.',
Ko='Kobane:BAABLgAECn8aAAIGAAUJzQkTJACRAAAGAAUJzQkTJACRAAAAAA==.Kodali:BAAALgAFFAIJAgAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lockemup:BAAALgADCgMJAwAAAA==.Lohuugg:BAAALgAECgQJBAABLgAFFAQJCwACAGwYAA==.Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgkJEwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Macheon:BAAALgAECgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAABLgAECn8gAAICAAgJCgmMCADTAAACAAgJCgmMCADTAAAAAA==.Magicpantiez:BAABLgAECn8ZAAIQAAgJkh1XPwB7AgAQAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgABAAAAAA==.Malexling:BAACLgAFFH8GAAIPAAMJog/QHwCkAAAPAAMJog/QHwCkAAAuAAQKf1YAAg8ACQmWIBsBAOUCAA8ACQmWIBsBAOUCAAAA.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8bAAIQAAUJ+BK7IADSAAAQAAUJ+BK7IADSAAAuAAQKfykAAhAACQn/HEI4ADcCABAACQn/HEI4ADcCAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMTAAkJKhTiLABwAQATAAgJoRLiLABwAQAWAAkJBwNHRwDKAAAAAA==.Mitternacht:BAACLgAFFH8MAAIEAAMJJRGqDQC9AAAEAAMJJRGqDQC9AAAuAAQKfzYAAgQACQkQIrYEABUDAAQACQkQIrYEABUDAAAA.',
Mo='Monen:BAAALgAECgcJAgAAAA==.Mooncraig:BAABLgAECn9bAAUKAAkJ7BuAAQDAAQAKAAkJ7BuAAQDAAQAJAAcJ+BcgAwBJAQAIAAQJNxc8KgAKAQAfAAMJaw8pMgCXAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.Mortamacee:BAAALgAECgYJDAABLgAECggJGQAOAGMgAA==.',
Ms='Msdeath:BAABLgAECn9RAAIIAAkJqiQoAABDAwAIAAkJqiQoAABDAwAAAA==.',
Na='Naiu:BAAALgAECgUJBQABLgAECggJFQADAHwWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgABAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAFFAIJAwAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAcJFQAEAI4XAA==.',
Ne='Nemeeia:BAAALgAECgYJDwAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIgAAgJYBcdFQBoAgAgAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn9KAAIcAAgJFBhLAgCFAQAcAAgJFBhLAgCFAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Or='Orin:BAAALgAECgUJBQAAAA==.Ororro:BAAALgAECgcJCgAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8tAAIXAAcJ9CIMAAA8AgAXAAcJ9CIMAAA8AgAuAAQKf0UAAhcACQkIJkAAAMcDABcACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAITAAgJFRp/IQC6AQATAAgJFRp/IQC6AQAAAA==.',
Pi='Picolás:BAABLgAECn8dAAIQAAgJFx1lPwAeAgAQAAgJFx1lPwAeAgAAAA==.',
Po='Pog:BAAALgAFFAIJAwAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8vAAIHAAkJ4BAXHgDdAQAHAAkJ4BAXHgDdAQAAAA==.Probono:BAABLgAECn8nAAITAAcJywoyQgAHAQATAAcJywoyQgAHAQAAAA==.',
Ps='Psalmwon:BAAALgAECgMJAwAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Qw='Qwing:BAAALgAECgEJAQABLgAFFAIJAwABAAAAAA==.',
Ra='Rageleaf:BAAALgAECgYJEAAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Rakus:BAAALgAECgEJAQAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAABLgAECn86AAQdAAkJSxlFAABkAgAdAAkJSxlFAABkAgACAAQJDAIgEQFXAAAGAAEJxQJwSAAXAAAAAA==.',
Re='Reliasht:BAAALgAECgMJAwAAAA==.Reprises:BAABLgAECn8pAAMVAAkJqyKiBAD+AgAVAAkJqyKiBAD+AgASAAgJxBdUQgDBAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQALAH4UAA==.Restdrag:BAAALgAECgEJAQAAAA==.Revini:BAABLgAECn8dAAIMAAgJcSSKAgBEAwAMAAgJcSSKAgBEAwAAAA==.Rezø:BAACLgAFFH8LAAMHAAYJmwfuCAAXAQAHAAYJmwfuCAAXAQAWAAEJnQGpPQAlAAAuAAQKfyUABAcABwmYEjEuAGkBAAcABglRFTEuAGkBABYAAgmSC1VsADkAABMAAQn4DG4RADAAAAAA.',
Ro='Roadkillinn:BAABLgAECn8kAAMXAAkJVA22HQCvAQAXAAkJVA22HQCvAQAYAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgAECgEJAQAAAA==.',
Sa='Sableye:BAACLgAFFH8VAAISAAQJCholEQAQAQASAAQJCholEQAQAQAuAAQKfzsAAhIACQnuGp0cAGgCABIACQnuGp0cAGgCAAAA.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scounddrel:BAAALgAFFAEJAwAAAA==.Scruffy:BAABLgAECn9FAAIRAAkJ+SLZAwAfAwARAAkJ+SLZAwAfAwAAAA==.',
Se='Seferres:BAACLgAFFH8aAAILAAYJZSMaCgDvAQALAAYJZSMaCgDvAQAuAAQKfygAAwsACQkIJeEKAN0CAAsACQkIJeEKAN0CAAUAAQksF5muAEMAAAAA.Selina:BAABLgAFFH8NAAIQAAcJRRPGBgD1AQAQAAcJRRPGBgD1AQAAAA==.Senortickle:BAABLgAECn8ZAAIfAAkJmyQyAgAMAwAfAAkJmyQyAgAMAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8IAAISAAMJqQuYaQC5AAASAAMJqQuYaQC5AAAuAAQKfx4AAxIACAkbEEJVAKQBABIACAkbEEJVAKQBACMAAglSEIMmAFEAAAEuAAUUBgkaAAsAZSMA.Shawts:BAABLgAECn8bAAIQAAcJLhHKnwCXAQAQAAcJLhHKnwCXAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAFFAYJCwAHAJsHAA==.',
Sk='Skeptimus:BAAALgADCgEJAQAAAA==.Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgYJBgAAAA==.',
Sn='Snowflower:BAAALgADCgYJBgAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAwAAAA==.Sourdumpling:BAABLgAECn8eAAIFAAgJHwxrTQA3AQAFAAgJHwxrTQA3AQAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAFACsbAA==.Steve:BAABLgAECn8WAAMYAAcJJQ9oOQB9AQAYAAcJJQ9oOQB9AQAXAAEJCQX6aAAsAAAAAA==.Stimutax:BAABLgAECn8kAAIkAAkJ2QY9CAAQAQAkAAkJ2QY9CAAQAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAIOAAcJ1yBJGgBCAgAOAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJEwAAAA==.Taurenvar:BAABLgAECn8uAAIZAAkJxh1YBwBZAgAZAAkJxh1YBwBZAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAACLgAFFH8KAAQIAAQJ9hF7IACbAAAIAAMJ9hF7IACbAAAJAAMJQgF/ZQBRAAAfAAEJAACDJgAAAAAuAAQKfyAABAgACQkBDVApABABAAgACQkBDVApABABAAoABAlhBOhnAIIAAB8AAQk6Ax45ACQAAAAA.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIiAAgJBw5rCwBfAQAiAAgJBw5rCwBfAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgABLgAECgkJKAALAP8TAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAIKAAkJVSRvAwAzAwAKAAkJVSRvAwAzAwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIeAAcJdhd5FwBkAQAeAAcJdhd5FwBkAQAAAA==.',
Ty='Tyn:BAAALgAECggJBwAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.Velidora:BAAALgAFFAEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8lAAIeAAkJvRQQFQCAAQAeAAkJvRQQFQCAAQAAAA==.Vilvaxis:BAAALgAECgEJAQABLgAFFAMJBwADAKYPAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIlAAkJtRtmCgBEAgAlAAkJtRtmCgBEAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
['Wî']='Wîene:BAAALgAECgYJBgABLgAFFAYJCwAHAJsHAA==.',
Xe='Xergioc:BAAALgAECgYJCgAAAA==.Xeriator:BAABLgAECn9PAAIbAAkJ4Q3dRwDKAQAbAAkJ4Q3dRwDKAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAUJFAADAGwXAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAABLgAECn8UAAIcAAkJwwdwSAAkAQAcAAkJwwdwSAAkAQAAAA==.Zaligator:BAABLgAECn8fAAQiAAkJmRRLCQCWAQAiAAgJ0RVLCQCWAQAmAAMJtwUAPgB7AAAhAAIJuQfSfwBfAAAAAA==.Zayuna:BAABLgAFFH8KAAMHAAMJAw7aNAC4AAAHAAMJAw7aNAC4AAATAAEJ7AozPABBAAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAIbAAkJJAsQVQCkAQAbAAkJJAsQVQCkAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAITAAUJGBMXCABGAQATAAUJGBMXCABGAQAuAAQKfygAAhMACAk6ISsNALECABMACAk6ISsNALECAAAA.Zombear:BAAALgAFFAIJAgABLgAFFAcJLQAXAPQiAA==.',
Zu='Zugzug:BAAALgADCgEJAQAAAA==.Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMFAAkJKxunEQCSAgAFAAkJKxunEQCSAgARAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8nAAICAAgJ/AhSkQAYAQACAAgJ/AhSkQAYAQAAAA==.',
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
