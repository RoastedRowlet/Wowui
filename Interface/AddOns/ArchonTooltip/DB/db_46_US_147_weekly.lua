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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Priest-Discipline','Druid-Restoration','Druid-Guardian','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','Hunter-BeastMastery','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adema:BAAALgADCgQJBQABLgAECggJEgABAAAAAA==.',
Ae='Aellaleander:BAAALgAECggJDAAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwACAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Aratune:BAAALgADCgEJAQAAAA==.Ari:BAAALgAECggJCAAAAA==.',
As='Asahhealer:BAACLgAFFH8HAAIDAAMJpg/OTACpAAADAAMJpg/OTACpAAAuAAQKfzMAAwMACAnJG6sYAHgCAAMACAnJG6sYAHgCAAQABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAFACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMDAAkJYhPJJwASAgADAAkJYhPJJwASAgAEAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAICAAQJbBgWEABgAQACAAQJbBgWEABgAQAuAAQKfzYAAwIACQnhJI4JAAADAAIACQnhJI4JAAADAAYAAQkAAA5pAD8AAAAA.Aurõrä:BAAALgAECgUJDQAAAA==.',
Av='Averlence:BAABLgAFFH8GAAIHAAMJfAUbMwClAAAHAAMJfAUbMwClAAAAAA==.',
Az='Azlia:BAAALgAFFAMJAwABLgAFFAMJAwABAAAAAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8HAAQIAAQJzgfISQCLAAAIAAMJWATISQCLAAAJAAIJEhoVMABGAAAKAAEJ8wTFSwAxAAABLgAFFAUJGQALACMlAA==.',
Ba='Bahumn:BAAALgAECggJEgAAAA==.Balboga:BAAALgADCggJCAABLgAECgUJDgABAAAAAA==.Bangpôwbôôm:BAABLgAECn9BAAMMAAkJvSAEBQDWAgAMAAkJhyAEBQDWAgANAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMOAAkJChIUIwDhAQAOAAkJChIUIwDhAQAPAAUJpBDG/ACtAAAAAA==.Beryl:BAAALgAECgMJAwAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIQAAgJaxwiNQCfAgAQAAgJaxwiNQCfAgABLgAFFAMJBQARADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgcJDgABLgAECgkJHgASAEgfAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwATAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgABAAAAAA==.',
Br='Brivia:BAAALgAECgUJCAABLgAFFAQJCwACAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAAUABgTAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECggJEwAAAA==.',
Ca='Camel:BAABLgAECn82AAMPAAgJABGWbACKAQAPAAgJABGWbACKAQAOAAUJBRjBOgBSAQAAAA==.Cattlestance:BAABLgAECn8bAAIVAAkJDRN9EwCrAQAVAAkJDRN9EwCrAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgQJBwAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwACAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgAECgIJAgAAAA==.Dashdashdash:BAABLgAECn9IAAIWAAgJgCORBgDCAgAWAAgJgCORBgDCAgAAAA==.Davethediva:BAAALgAECgEJAgAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIVAAgJ5BbhFACXAQAVAAgJ5BbhFACXAQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDAAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8jAAIXAAgJpRV2HwC5AQAXAAgJpRV2HwC5AQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8jAAIQAAkJlxVePQAfAgAQAAkJlxVePQAfAgAAAA==.Dragoonall:BAAALgADCgMJAwAAAA==.Dragoonette:BAAALgADCgUJBwAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIJAAkJSx29BQCdAgAJAAkJSx29BQCdAgAAAA==.',
['Dë']='Dëathlock:BAAALgAECgQJBAABLgAECgkJNQATAD8MAA==.',
Ec='Ectasee:BAABLgAECn8yAAMDAAkJRySwAgCSAwADAAkJRySwAgCSAwAEAAMJ8RC8awCUAAAAAA==.',
Ei='Eianhander:BAAALgAECgQJBAAAAA==.Eirenus:BAAALgAECgcJDAABLgAECgcJIQAHAMkQAA==.',
El='Element:BAAALgAECgcJDAAAAA==.',
Em='Emi:BAACLgAFFH8LAAMEAAYJggowKgDgAAAEAAUJGAgwKgDgAAADAAIJlBP1UwCWAAAuAAQKfyIAAwQACAnEFcE0AFgBAAQABwnYFME0AFgBAAMACAlMFjlUAFQBAAAA.',
En='Enfilade:BAAALgAECgQJBAAAAA==.Enøch:BAAALgAFFAEJAgAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8jAAMYAAgJch5LCgB1AgAYAAgJch5LCgB1AgAZAAEJXRuqMQBLAAABLgAECggJKAARAG8iAA==.',
Fa='Fanuc:BAABLgAECn8zAAMDAAkJQyIaBgBFAwADAAkJQyIaBgBFAwAaAAgJ8BOIDgC7AQAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAITAAgJjxHOeAAiAQATAAgJjxHOeAAiAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8dAAIMAAcJihe8GQCGAQAMAAcJihe8GQCGAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJAwAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgABAAAAAA==.',
Fo='Forthrich:BAABLgAECn89AAIPAAkJGwwGdAB7AQAPAAkJGwwGdAB7AQAAAA==.Fozuul:BAABLgAECn8UAAMIAAkJBRLIKQD9AQAIAAkJBRLIKQD9AQAKAAEJpRXPfQBAAAABLgAECgkJJwAFACsbAA==.',
Fr='Frankié:BAAALgADCgEJAQAAAA==.Fruit:BAAALgAECgYJBgAAAA==.Frâust:BAAALgAECgUJCAAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMOAAgJAh0TEgCCAgAOAAgJAh0TEgCCAgAPAAUJABagogAnAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECggJHgASAJEbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIbAAUJ8COlLwDxAQAbAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8bAAIcAAcJiRT+CwB6AQAcAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJDgAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMXAAkJhQ9MPQBFAQAXAAYJwxBMPQBFAQAUAAkJBwzuRADyAAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQARADEYAA==.Hirculos:BAABLgAECn8dAAIbAAgJwhf2HwDqAQAbAAgJwhf2HwDqAQAAAA==.',
Ho='Hoggle:BAAALgAECgEJAQAAAA==.Hokkai:BAAALgADCgEJAQAAAA==.Holix:BAAALgADCgUJBQAAAA==.Holyfrog:BAABLgAECn9GAAMOAAkJaxsRFwBZAgAOAAkJaxsRFwBZAgAPAAIJQgjqRAFaAAAAAA==.Holythis:BAACLgAFFH8QAAIdAAQJPgy0CQDMAAAdAAQJPgy0CQDMAAAuAAQKfysAAh0ACQmLFqMGAHwCAB0ACQmLFqMGAHwCAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn89AAMeAAkJzhRJCwD2AQAeAAkJzhRJCwD2AQAJAAgJ4AiEMADVAAAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMTAAkJtxkyIwA5AgATAAkJtxkyIwA5AgAWAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn9LAAIfAAkJXR4FCACcAgAfAAkJXR4FCACcAgAAAA==.Injunjoe:BAAALgAECgQJBAAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAABLgAECn8cAAIQAAcJGAJc9gCxAAAQAAcJGAJc9gCxAAAAAA==.',
Je='Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAABLgAECn8jAAISAAcJrAm3jQAWAQASAAcJrAm3jQAWAQAAAA==.',
Jo='Jofixit:BAABLgAECn9LAAISAAkJnR+5DgDRAgASAAkJnR+5DgDRAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaepop:BAABLgAECn8TAAITAAgJfBEFcQBRAQATAAgJfBEFcQBRAQAAAA==.Kanda:BAABLgAECn8eAAISAAgJUxz1IgA0AgASAAgJUxz1IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8zAAMSAAkJDCNqCwDvAgASAAkJDCNqCwDvAgAZAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9JAAISAAkJJh5KDwDNAgASAAkJJh5KDwDNAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8OAAMgAAUJPhQvKQAQAQAgAAQJPhQvKQAQAQAhAAEJAAAdEgAAAAAuAAQKfzsAAyEACQl7H/0CAPgCACEACAmeH/0CAPgCACAACQnkFxQVACoCAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMMAAgJsBrNEQDlAQAMAAgJsBrNEQDlAQANAAEJAAA9kwEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8UAAIEAAYJMxhaEgB1AQAEAAYJMxhaEgB1AQAuAAQKfx4AAgQACAmkGlwXAFwCAAQACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.Kimbolee:BAAALgAECgQJAgAAAA==.',
Ko='Kobane:BAAALgAECgUJDgAAAA==.Kodali:BAAALgAECgUJDAAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lohuugg:BAAALgAECgQJBAABLgAFFAQJCwACAGwYAA==.Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECggJDwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAABLgAECn8aAAICAAcJagiclQAMAQACAAcJagiclQAMAQAAAA==.Magicpantiez:BAABLgAECn8ZAAIQAAgJkh1XPwB7AgAQAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgABAAAAAA==.Malexling:BAABLgAECn88AAIPAAgJTx1nKgBNAgAPAAgJTx1nKgBNAgAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8TAAIQAAQJPhAcWwApAQAQAAQJPhAcWwApAQAuAAQKfycAAhAACQmGGxk0AEECABAACQmGGxk0AEECAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMUAAkJKhQrKQB+AQAUAAgJoRIrKQB+AQAXAAkJBwP1QwDLAAAAAA==.Mitternacht:BAACLgAFFH8GAAIEAAIJAhSYOgCMAAAEAAIJAhSYOgCMAAAuAAQKfy8AAgQACQn7IUQEABUDAAQACQn7IUQEABUDAAAA.',
Mo='Mooncraig:BAABLgAECn9JAAQKAAkJnBt/DQB3AgAKAAkJnBt/DQB3AgAIAAcJdxFSRQBxAQAeAAMJaw+MLQCbAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAABLgAECn82AAIJAAgJ1SLiBAC3AgAJAAgJ1SLiBAC3AgAAAA==.',
Na='Naiu:BAAALgAECgUJBQABLgAECggJFQADAHwWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgABAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAECgUJBQABLgAECggJEgABAAAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAYJFAAEADMYAA==.',
Ne='Nemeeia:BAAALgAECgYJDwAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIfAAgJYBcdFQBoAgAfAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn86AAIbAAgJThZ7IADmAQAbAAgJThZ7IADmAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Or='Orin:BAAALgAECgUJBQAAAA==.Ororro:BAAALgAECgEJAQAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8kAAIYAAcJ0yIMAAA8AgAYAAcJ0yIMAAA8AgAuAAQKf0UAAhgACQkIJkAAAMcDABgACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAIUAAgJFRqpHgDIAQAUAAgJFRqpHgDIAQAAAA==.',
Pi='Picolás:BAABLgAECn8cAAIQAAcJ1R6SVQDVAQAQAAcJ1R6SVQDVAQAAAA==.',
Po='Pog:BAAALgAFFAIJAwAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8vAAIHAAkJ4BCUGwDkAQAHAAkJ4BCUGwDkAQAAAA==.Probono:BAABLgAECn8nAAIUAAcJyQqJPQATAQAUAAcJyQqJPQATAQAAAA==.',
Ps='Psalmwon:BAAALgAECgMJAwAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Qw='Qwing:BAAALgAECgEJAQABLgAECggJEgABAAAAAA==.',
Ra='Rageleaf:BAAALgAECgYJEAAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAABLgAECn8fAAQcAAgJwQznDAB6AQAcAAgJwQznDAB6AQACAAQJDALTBAFaAAAGAAEJxQJXRAAXAAAAAA==.',
Re='Reliasht:BAAALgAECgMJAwAAAA==.Reprises:BAABLgAECn8pAAMWAAkJqyL6AwAEAwAWAAkJqyL6AwAEAwATAAgJxBd2PwC/AQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQALAH4UAA==.Restdrag:BAAALgAECgEJAQAAAA==.Revini:BAABLgAECn8dAAIMAAgJcSSKAgBEAwAMAAgJcSSKAgBEAwAAAA==.Rezø:BAABLgAECn8hAAMHAAcJyRCDMgBCAQAHAAYJNRODMgBCAQAXAAIJkgsiZwA6AAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8kAAMYAAkJVA3BGwC6AQAYAAkJVA3BGwC6AQAZAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAACLgAFFH8NAAITAAQJGxUuPAAiAQATAAQJGxUuPAAiAQAuAAQKfzkAAhMACQnuGv0aAGgCABMACQnuGv0aAGgCAAAA.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scounddrel:BAAALgAFFAEJAgAAAA==.Scruffy:BAABLgAECn9FAAIRAAkJ+SJnAwAjAwARAAkJ+SJnAwAjAwAAAA==.',
Se='Seferres:BAACLgAFFH8ZAAILAAUJIyUWDgCgAQALAAUJIyUWDgCgAQAuAAQKfycAAgsACQkIJeEKAN0CAAsACQkIJeEKAN0CAAAA.Senortickle:BAABLgAECn8YAAIeAAkJmyTrAQARAwAeAAkJmyTrAQARAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8IAAITAAMJqQsqYAC9AAATAAMJqQsqYAC9AAAuAAQKfx4AAxMACAkbEEJVAKQBABMACAkbEEJVAKQBACIAAglSEIMmAFEAAAEuAAUUBQkZAAsAIyUA.Shawts:BAABLgAECn8bAAIQAAcJLhHKnwCXAQAQAAcJLhHKnwCXAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAECgcJIQAHAMkQAA==.',
Sk='Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgYJBgAAAA==.',
Sn='Snowflower:BAAALgADCgYJBgAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAwAAAA==.Sourdumpling:BAAALgAECggJDAAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAFACsbAA==.Steve:BAABLgAECn8WAAMZAAcJJQ9oOQB9AQAZAAcJJQ9oOQB9AQAYAAEJCQXKYwAuAAAAAA==.Stimutax:BAABLgAECn8jAAIjAAgJsgZzBwAUAQAjAAgJsgZzBwAUAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAIOAAcJ1yBJGgBCAgAOAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJEgAAAA==.Taurenvar:BAABLgAECn8uAAIaAAkJxh22BgBeAgAaAAkJxh22BgBeAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAACLgAFFH8GAAIJAAMJ9hEzGwCgAAAJAAMJ9hEzGwCgAAAuAAQKfyAABAkACQkBDQgmABEBAAkACQkBDQgmABEBAAoABAlhBOhnAIIAAB4AAQk6Ax45ACQAAAAA.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIhAAgJBw6tCgBkAQAhAAgJBw6tCgBkAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgABLgAECggJEgABAAAAAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAIKAAkJVSQOAwA2AwAKAAkJVSQOAwA2AwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIdAAcJdhc8FgBlAQAdAAcJdhc8FgBlAQAAAA==.',
Ty='Tyn:BAAALgAECggJBwAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8kAAIdAAgJDxXkEwCBAQAdAAgJDxXkEwCBAQAAAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIkAAkJtRu2CQBFAgAkAAkJtRu2CQBFAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn9HAAISAAkJ+QziRQDEAQASAAkJ+QziRQDEAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAUJDwADAF4TAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECggJEwAAAA==.Zaligator:BAABLgAECn8fAAQhAAkJmRTBCACXAQAhAAgJ0RXBCACXAQAlAAMJtwUAPgB7AAAgAAIJuQfwdwBiAAAAAA==.Zayuna:BAAALgAFFAIJAwAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAISAAkJJAslTgCrAQASAAkJJAslTgCrAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAIUAAUJGBMXCABGAQAUAAUJGBMXCABGAQAuAAQKfygAAhQACAk6ISsNALECABQACAk6ISsNALECAAAA.Zombear:BAAALgAECgYJCAABLgAFFAcJJAAYANMiAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMFAAkJKxtcEACPAgAFAAkJKxtcEACPAgARAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8lAAICAAcJUQmnjgAZAQACAAcJUQmnjgAZAQAAAA==.',
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
