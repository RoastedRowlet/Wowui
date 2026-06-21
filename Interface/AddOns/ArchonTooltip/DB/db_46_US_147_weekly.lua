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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Priest-Discipline','Druid-Restoration','Druid-Guardian','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adema:BAAALgADCgQJBQABLgAFFAIJAwABAAAAAA==.',
Ae='Aellaleander:BAAALgAECggJDAAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwACAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Aratune:BAAALgADCgEJAQAAAA==.Arazen:BAAALgADCgUJAQAAAA==.Arcjanhealer:BAAALgAECgEJAQAAAA==.Ari:BAAALgAECggJCAAAAA==.Arianá:BAAALgAFFAEJAQAAAA==.',
As='Asahhealer:BAACLgAFFH8HAAIDAAMJpg+/VACnAAADAAMJpg+/VACnAAAuAAQKfzQAAwMACAkBHuQUAKQCAAMACAkBHuQUAKQCAAQABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAFACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMDAAkJYhNSKgASAgADAAkJYhNSKgASAgAEAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAICAAQJbBgWEABgAQACAAQJbBgWEABgAQAuAAQKfzYAAwIACQnhJL4KAPoCAAIACQnhJL4KAPoCAAYAAQkAAA5pAD8AAAAA.Aurõrä:BAABLgAECn8UAAIGAAYJQgrbHQC6AAAGAAYJQgrbHQC6AAAAAA==.',
Av='Averlence:BAABLgAFFH8GAAIHAAMJfAX2OACjAAAHAAMJfAX2OACjAAAAAA==.',
Az='Azlia:BAAALgAFFAQJBAAAAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8HAAQIAAQJzgc6UQB+AAAIAAMJWAQ6UQB+AAAJAAIJEhoKOQBDAAAKAAEJ8wRHUwAxAAABLgAFFAYJGgALAGUjAA==.',
Ba='Bahumn:BAAALgAECggJEgABLgAFFAIJAwABAAAAAA==.Balboga:BAAALgADCggJCAABLgAECgUJFAAGAPAIAA==.Bangpôwbôôm:BAABLgAECn9GAAMMAAkJvSCZBQDNAgAMAAkJhyCZBQDNAgANAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMOAAkJChK/JADgAQAOAAkJChK/JADgAQAPAAUJpBDNCgGrAAAAAA==.Beryl:BAAALgAECgQJAwAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIQAAgJaxwiNQCfAgAQAAgJaxwiNQCfAgABLgAFFAMJBQARADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgcJDgABLgAECggJGQAOAGMgAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwASAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgABAAAAAA==.',
Br='Brivia:BAAALgAECgUJCAABLgAFFAQJCwACAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAATABgTAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECggJEwAAAA==.',
Ca='Camel:BAABLgAECn9IAAMPAAkJXxjEAAAzAgAPAAkJXxjEAAAzAgAOAAUJBRhIPQBQAQAAAA==.Cattlestance:BAABLgAECn8bAAIUAAkJDRP3FACjAQAUAAkJDRP3FACjAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgYJDAAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwACAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgAECgIJAgAAAA==.Dashdashdash:BAABLgAECn9YAAIVAAgJ8yQ3AACzAgAVAAgJ8yQ3AACzAgAAAA==.Davethediva:BAAALgAECgEJAgAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIUAAgJ5BZWFgCSAQAUAAgJ5BZWFgCSAQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDQAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8kAAIWAAkJMBV8IQC2AQAWAAkJMBV8IQC2AQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Do='Dodgydave:BAAALgAECgEJAQAAAA==.Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8jAAIQAAkJlxUWQgAVAgAQAAkJlxUWQgAVAgAAAA==.Dragoonall:BAAALgADCgMJAwAAAA==.Dragoonette:BAAALgADCgUJBwAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIJAAkJSx1KBgCdAgAJAAkJSx1KBgCdAgAAAA==.',
['Dë']='Dëathlock:BAAALgAECgQJBAABLgAECgkJNQASAD8MAA==.',
Ec='Ectasee:BAABLgAECn8zAAMDAAkJRyQyAwCPAwADAAkJRyQyAwCPAwAEAAMJ8RCPcgCTAAAAAA==.',
Ei='Eianhander:BAAALgAECgQJBAAAAA==.Eirenus:BAAALgAECgcJEwABLgAFFAUJBgAHAP4HAA==.',
El='Element:BAAALgAECgcJDAAAAA==.',
Em='Emi:BAACLgAFFH8LAAMEAAYJggozMADSAAAEAAUJGAgzMADSAAADAAIJlBNhXACTAAAuAAQKfyIAAwQACAnEFTM4AFcBAAQABwnYFDM4AFcBAAMACAlMFjFZAFMBAAAA.',
En='Enfilade:BAAALgAECgQJBAAAAA==.Enøch:BAAALgAFFAEJAgAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8qAAMXAAkJxB+ABADlAgAXAAkJxB+ABADlAgAYAAEJXRtlNABLAAABLgAECggJKAARAG8iAA==.',
Fa='Fanuc:BAABLgAECn87AAMDAAkJQyLfBgBCAwADAAkJQyLfBgBCAwAZAAgJIBhgAACNAQAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAISAAgJjxHhfgAiAQASAAgJjxHhfgAiAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8kAAIMAAgJHBeKFwCqAQAMAAgJHBeKFwCqAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJBAABLgAFFAQJBAABAAAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgABAAAAAA==.',
Fo='Forthrich:BAACLgAFFH8GAAIPAAMJPQIBkgCPAAAPAAMJPQIBkgCPAAAuAAQKfz8AAg8ACQnRDcZuAJEBAA8ACQnRDcZuAJEBAAAA.Fozuul:BAABLgAECn8UAAMIAAkJBRLGKwD7AQAIAAkJBRLGKwD7AQAKAAEJpRW8hABAAAABLgAECgkJJwAFACsbAA==.',
Fr='Frankié:BAAALgADCgEJAQAAAA==.Fruit:BAAALgAECgYJCAAAAA==.Frâust:BAAALgAECggJEAAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMOAAgJAh0TEgCCAgAOAAgJAh0TEgCCAgAPAAUJABYxrAAlAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECggJHgAaAJEbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIbAAUJ8COlLwDxAQAbAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8bAAIcAAcJiRT+CwB6AQAcAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgAECgUJCAAAAA==.',
Ha='Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJEwAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMWAAkJhQ9MPQBFAQAWAAYJwxBMPQBFAQATAAkJBwx2SQDpAAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQARADEYAA==.Hirculos:BAABLgAECn8hAAIbAAgJyRcrIgDhAQAbAAgJyRcrIgDhAQAAAA==.',
Ho='Hoggle:BAAALgAECgEJAQAAAA==.Hokkai:BAAALgADCgEJAQAAAA==.Holix:BAAALgAECggJCAAAAA==.Holyfrog:BAABLgAECn9GAAMOAAkJaxsRFwBZAgAOAAkJaxsRFwBZAgAPAAIJQgi3VQFaAAAAAA==.Holythis:BAACLgAFFH8WAAIdAAQJPgwwCwDCAAAdAAQJPgwwCwDCAAAuAAQKfy0AAx0ACQnwFqMGAHwCAB0ACQnwFqMGAHwCAA8AAQkAAE/ZAQAAAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn89AAMeAAkJzhRiDADyAQAeAAkJzhRiDADyAQAJAAgJ4AjMNADVAAAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMSAAkJtxknJQA6AgASAAkJtxknJQA6AgAVAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn9ZAAIfAAkJAiBiAADfAQAfAAkJAiBiAADfAQAAAA==.Injunjoe:BAAALgAECgQJBAAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janaru:BAAALgAECgEJAQABLgAECgcJCgABAAAAAA==.Janelik:BAABLgAECn8jAAIQAAcJTQLA+wCzAAAQAAcJTQLA+wCzAAAAAA==.',
Je='Jeeto:BAAALgAECgEJAQAAAA==.Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jimihendrix:BAAALgAECgEJAQAAAA==.Jinxi:BAABLgAECn8jAAIaAAcJrAntlwAQAQAaAAcJrAntlwAQAQAAAA==.',
Jo='Jofixit:BAABLgAECn9ZAAIaAAkJRiDrAAAaAgAaAAkJRiDrAAAaAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaelix:BAAALgAECgMJAwABLgAECggJJAAMABwXAA==.Kaepop:BAABLgAECn8TAAISAAgJfBEFcQBRAQASAAgJfBEFcQBRAQAAAA==.Kanda:BAABLgAECn8fAAIaAAkJER31IgA0AgAaAAkJER31IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8zAAMaAAkJDCNYDQDoAgAaAAkJDCNYDQDoAgAYAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9NAAIaAAkJDR+HDgDdAgAaAAkJDR+HDgDdAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8TAAMgAAUJpBf7KQAgAQAgAAQJpBf7KQAgAQAhAAEJAACTEwAAAAAuAAQKf0AAAyEACQl7H/0CAPgCACEACAmeH/0CAPgCACAACQnkF58VAC0CAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMMAAgJsBouEwDeAQAMAAgJsBouEwDeAQANAAEJAACLrgEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8UAAIEAAYJMxi8FwBeAQAEAAYJMxi8FwBeAQAuAAQKfx4AAgQACAmkGlwXAFwCAAQACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.Kimbolee:BAAALgAECgYJCgAAAA==.',
Ko='Kobane:BAABLgAECn8UAAIGAAUJ8AgRJACRAAAGAAUJ8AgRJACRAAAAAA==.Kodali:BAAALgAFFAIJAgAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lohuugg:BAAALgAECgQJBAABLgAFFAQJCwACAGwYAA==.Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgkJEwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Macheon:BAAALgAECgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAABLgAECn8eAAICAAcJiwmwAwC4AAACAAcJiwmwAwC4AAAAAA==.Magicpantiez:BAABLgAECn8ZAAIQAAgJkh1XPwB7AgAQAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgABAAAAAA==.Malexling:BAABLgAECn9OAAIPAAkJliBrAADnAgAPAAkJliBrAADnAgAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8YAAIQAAUJ+BIkXgAkAQAQAAUJ+BIkXgAkAQAuAAQKfycAAhAACQmGG0U4ADcCABAACQmGG0U4ADcCAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMTAAkJKhTfLABwAQATAAgJoRLfLABwAQAWAAkJBwNBRwDKAAAAAA==.Mitternacht:BAACLgAFFH8KAAIEAAMJJRHSNQC3AAAEAAMJJRHSNQC3AAAuAAQKfzYAAgQACQkQIrYEABUDAAQACQkQIrYEABUDAAAA.',
Mo='Monen:BAAALgAECgcJAgAAAA==.Mooncraig:BAABLgAECn9XAAUKAAkJ7BuKAADCAQAKAAkJ7BuKAADCAQAIAAcJdxFjRwByAQAJAAQJNxc8KgAKAQAeAAMJaw8pMgCXAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.Mortamacee:BAAALgAECgYJDAABLgAECggJGQAOAGMgAA==.',
Ms='Msdeath:BAABLgAECn9IAAIJAAkJWSQUAAAxAwAJAAkJWSQUAAAxAwAAAA==.',
Na='Naiu:BAAALgAECgUJBQABLgAECggJFQADAHwWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgABAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAFFAIJAwAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAYJFAAEADMYAA==.',
Ne='Nemeeia:BAAALgAECgYJDwAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIfAAgJYBcdFQBoAgAfAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn9GAAIbAAgJ+RfwAABqAQAbAAgJ+RfwAABqAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Or='Orin:BAAALgAECgUJBQAAAA==.Ororro:BAAALgAECgYJCQAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8rAAIXAAcJ9CIMAAA8AgAXAAcJ9CIMAAA8AgAuAAQKf0UAAhcACQkIJkAAAMcDABcACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAITAAgJFRp+IQC6AQATAAgJFRp+IQC6AQAAAA==.',
Pi='Picolás:BAABLgAECn8dAAIQAAgJFx1nPwAeAgAQAAgJFx1nPwAeAgAAAA==.',
Po='Pog:BAAALgAFFAIJAwAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8vAAIHAAkJ4BAVHgDdAQAHAAkJ4BAVHgDdAQAAAA==.Probono:BAABLgAECn8nAAITAAcJywosQgAHAQATAAcJywosQgAHAQAAAA==.',
Ps='Psalmwon:BAAALgAECgMJAwAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Qw='Qwing:BAAALgAECgEJAQABLgAFFAIJAwABAAAAAA==.',
Ra='Rageleaf:BAAALgAECgYJEAAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAABLgAECn8xAAQcAAkJeRU0AADkAQAcAAkJeRU0AADkAQACAAQJDAIfEQFXAAAGAAEJxQJwSAAXAAAAAA==.',
Re='Reliasht:BAAALgAECgMJAwAAAA==.Reprises:BAABLgAECn8pAAMVAAkJqyKjBAD+AgAVAAkJqyKjBAD+AgASAAgJxBdSQgDBAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQALAH4UAA==.Restdrag:BAAALgAECgEJAQAAAA==.Revini:BAABLgAECn8dAAIMAAgJcSSKAgBEAwAMAAgJcSSKAgBEAwAAAA==.Rezø:BAACLgAFFH8GAAMHAAUJ/gekJAAoAQAHAAUJ/gekJAAoAQAWAAEJnQGoPQAlAAAuAAQKfyQABAcABwmYEjAuAGkBAAcABglRFTAuAGkBABYAAgmSC1FsADkAABMAAQnMBZOUACYAAAAA.',
Ro='Roadkillinn:BAABLgAECn8kAAMXAAkJVA23HQCvAQAXAAkJVA23HQCvAQAYAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAACLgAFFH8RAAISAAQJMxeROgA7AQASAAQJMxeROgA7AQAuAAQKfzkAAhIACQnuGp8cAGgCABIACQnuGp8cAGgCAAAA.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scounddrel:BAAALgAFFAEJAwAAAA==.Scruffy:BAABLgAECn9FAAIRAAkJ+SLaAwAfAwARAAkJ+SLaAwAfAwAAAA==.',
Se='Seferres:BAACLgAFFH8aAAILAAYJZSMtCgDvAQALAAYJZSMtCgDvAQAuAAQKfygAAwsACQkIJeEKAN0CAAsACQkIJeEKAN0CAAUAAQksF5WuAEMAAAAA.Selina:BAABLgAFFH8GAAIQAAYJ7w7VAwCMAQAQAAYJ7w7VAwCMAQAAAA==.Senortickle:BAABLgAECn8ZAAIeAAkJmyQyAgAMAwAeAAkJmyQyAgAMAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8IAAISAAMJqQujaQC5AAASAAMJqQujaQC5AAAuAAQKfx4AAxIACAkbEEJVAKQBABIACAkbEEJVAKQBACIAAglSEIMmAFEAAAEuAAUUBgkaAAsAZSMA.Shawts:BAABLgAECn8bAAIQAAcJLhHKnwCXAQAQAAcJLhHKnwCXAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAFFAUJBgAHAP4HAA==.',
Sk='Skeptimus:BAAALgADCgEJAQAAAA==.Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgYJBgAAAA==.',
Sn='Snowflower:BAAALgADCgYJBgAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAwAAAA==.Sourdumpling:BAABLgAECn8aAAIFAAgJHwyZBACnAAAFAAgJHwyZBACnAAAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAFACsbAA==.Steve:BAABLgAECn8WAAMYAAcJJQ9oOQB9AQAYAAcJJQ9oOQB9AQAXAAEJCQX5aAAsAAAAAA==.Stimutax:BAABLgAECn8kAAIjAAkJ2QY8CAAQAQAjAAkJ2QY8CAAQAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAIOAAcJ1yBJGgBCAgAOAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJEgAAAA==.Taurenvar:BAABLgAECn8uAAIZAAkJxh1YBwBZAgAZAAkJxh1YBwBZAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAACLgAFFH8KAAQJAAQJ9hF3IACbAAAJAAMJ9hF3IACbAAAIAAMJQgGAZQBRAAAeAAEJAACEJgAAAAAuAAQKfyAABAkACQkBDVApABABAAkACQkBDVApABABAAoABAlhBOhnAIIAAB4AAQk6Ax45ACQAAAAA.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIhAAgJBw5rCwBfAQAhAAgJBw5rCwBfAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgABLgAECgkJIwALACARAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAIKAAkJVSRvAwAzAwAKAAkJVSRvAwAzAwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIdAAcJdhd7FwBkAQAdAAcJdhd7FwBkAQAAAA==.',
Ty='Tyn:BAAALgAECggJBwAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.Velidora:BAAALgAFFAEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8lAAIdAAkJvRQQFQCAAQAdAAkJvRQQFQCAAQAAAA==.Vilvaxis:BAAALgAECgEJAQABLgAFFAMJBwADAKYPAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIkAAkJtRtoCgBEAgAkAAkJtRtoCgBEAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
['Wî']='Wîene:BAAALgAECgYJBgABLgAFFAUJBgAHAP4HAA==.',
Xe='Xergioc:BAAALgAECgYJBgAAAA==.Xeriator:BAABLgAECn9PAAIaAAkJ4Q3cRwDKAQAaAAkJ4Q3cRwDKAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAUJFAADAGwXAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECggJEwAAAA==.Zaligator:BAABLgAECn8fAAQhAAkJmRRLCQCWAQAhAAgJ0RVLCQCWAQAlAAMJtwUAPgB7AAAgAAIJuQfPfwBfAAAAAA==.Zayuna:BAABLgAFFH8JAAMHAAMJAw7fNAC4AAAHAAMJAw7fNAC4AAATAAEJ7AouPABBAAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAIaAAkJJAsRVQCkAQAaAAkJJAsRVQCkAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAITAAUJGBMXCABGAQATAAUJGBMXCABGAQAuAAQKfygAAhMACAk6ISsNALECABMACAk6ISsNALECAAAA.Zombear:BAAALgAECgYJCAABLgAFFAcJKwAXAPQiAA==.',
Zu='Zugzug:BAAALgADCgEJAQAAAA==.Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMFAAkJKxupEQCSAgAFAAkJKxupEQCSAgARAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8mAAICAAcJ9wlOkQAYAQACAAcJ9wlOkQAYAQAAAA==.',
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
