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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','Hunter-BeastMastery','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-05-30',data={Ae='Aellaleander:BAAALgAECgcJCwAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwABAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Aratune:BAAALgADCgEJAQAAAA==.Ari:BAAALgAECggJCAAAAA==.',
As='Asahhealer:BAACLgAFFH8FAAICAAIJow6pVgB7AAACAAIJow6pVgB7AAAuAAQKfzMAAwIACAnJG7EWAHsCAAIACAnJG7EWAHsCAAMABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAEACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMCAAkJYhNbJQAUAgACAAkJYhNbJQAUAgADAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAIBAAQJbBgWEABgAQABAAQJbBgWEABgAQAuAAQKfzYAAwEACQnhJHwIAAUDAAEACQnhJHwIAAUDAAUAAQkAAA5pAD8AAAAA.Aurõrä:BAAALgAECgUJDQAAAA==.',
Av='Averlence:BAAALgAFFAMJAwAAAA==.',
Az='Azlia:BAAALgAECgcJEQABLgAFFAMJAwAGAAAAAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8GAAQHAAMJWARbRACSAAAHAAMJWARbRACSAAAIAAEJEhoYKQBKAAAJAAEJ8wSERQAxAAABLgAFFAUJGQAKACMlAA==.',
Ba='Bahumn:BAAALgAECggJEgAAAA==.Balboga:BAAALgADCggJCAABLgAECgUJDgAGAAAAAA==.Bangpôwbôôm:BAABLgAECn9AAAMLAAkJmSC2BADTAgALAAkJYyC2BADTAgAMAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMNAAkJChIiIQDkAQANAAkJChIiIQDkAQAOAAUJpBDm7QCuAAAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIPAAgJaxwiNQCfAgAPAAgJaxwiNQCfAgABLgAFFAMJBQAQADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgYJDQABLgAECgkJHgARAEgfAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwASAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAGAAAAAA==.',
Br='Brivia:BAAALgAECgUJCAABLgAFFAQJCwABAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAATABgTAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECgcJEgAAAA==.',
Ca='Camel:BAABLgAECn8tAAMNAAcJohtaOABUAQANAAUJBRhaOABUAQAOAAcJOA+RjAA9AQAAAA==.Cattlestance:BAABLgAECn8bAAIUAAkJDRMDEgCzAQAUAAkJDRMDEgCzAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgQJBwAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwABAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgAECgIJAgAAAA==.Dashdashdash:BAABLgAECn9AAAIVAAgJqSGGBwCdAgAVAAgJqSGGBwCdAgAAAA==.Davethediva:BAAALgADCgcJCwAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIUAAgJ5BZAEwChAQAUAAgJ5BZAEwChAQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDAAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8jAAIWAAgJpRVSHQDDAQAWAAgJpRVSHQDDAQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8iAAIPAAgJGBcaUADUAQAPAAgJGBcaUADUAQAAAA==.Dragoonall:BAAALgADCgMJAwAAAA==.Dragoonette:BAAALgADCgUJBwAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIIAAkJSx0hBQChAgAIAAkJSx0hBQChAgAAAA==.',
['Dë']='Dëathlock:BAAALgADCgYJAgABLgAECgkJNQASAD8MAA==.',
Ec='Ectasee:BAABLgAECn8yAAMCAAkJRyQ6AgCVAwACAAkJRyQ6AgCVAwADAAMJ8RCGZgCUAAAAAA==.',
Ei='Eianhander:BAAALgAECgQJBAAAAA==.Eirenus:BAAALgAECgcJDAABLgAECgcJIAAXAMkQAA==.',
El='Element:BAAALgAECgYJCwAAAA==.',
Em='Emi:BAACLgAFFH8JAAIDAAUJGAjSJQDmAAADAAUJGAjSJQDmAAAuAAQKfyIAAwMACAnEFYgxAF0BAAMABwnYFIgxAF0BAAIACAlMFq1PAFUBAAAA.',
En='Enøch:BAAALgAFFAEJAgAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8eAAMYAAgJjRygDgA0AgAYAAgJjRygDgA0AgAZAAEJXRs7LwBMAAABLgAECggJKAAQAG8iAA==.',
Fa='Fanuc:BAABLgAECn8yAAMCAAkJQyJlBQBIAwACAAkJQyJlBQBIAwAaAAgJwxIQDgCyAQAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAISAAgJjxHLdAAdAQASAAgJjxHLdAAdAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8cAAILAAcJihfrFwCKAQALAAcJihfrFwCKAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJAwAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAGAAAAAA==.',
Fo='Forthrich:BAABLgAECn89AAIOAAkJGwylbwB0AQAOAAkJGwylbwB0AQAAAA==.Fozuul:BAABLgAECn8UAAMHAAkJBRIqKAD9AQAHAAkJBRIqKAD9AQAJAAEJpRWkdwBAAAABLgAECgkJJwAEACsbAA==.',
Fr='Fruit:BAAALgAECgYJBgAAAA==.Frâust:BAAALgADCgkJEgAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMNAAgJAh0TEgCCAgANAAgJAh0TEgCCAgAOAAUJABaamAAoAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECggJHgARAJEbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIbAAUJ8COlLwDxAQAbAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8bAAIcAAcJiRT+CwB6AQAcAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJDQAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMWAAkJhQ9MPQBFAQAWAAYJwxBMPQBFAQATAAkJBwwJPgD0AAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQAQADEYAA==.Hirculos:BAABLgAECn8dAAIbAAgJwhfXHQDsAQAbAAgJwhfXHQDsAQAAAA==.',
Ho='Hokkai:BAAALgADCgEJAQAAAA==.Holyfrog:BAABLgAECn9GAAMNAAkJaxsRFwBZAgANAAkJaxsRFwBZAgAOAAIJQgiEMwFbAAAAAA==.Holythis:BAACLgAFFH8MAAIdAAQJPgyPCADXAAAdAAQJPgyPCADXAAAuAAQKfysAAh0ACQmLFqMGAHwCAB0ACQmLFqMGAHwCAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn89AAMeAAkJzhRqCgD4AQAeAAkJzhRqCgD4AQAIAAgJ4AgALADZAAAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMSAAkJtxkBIQA7AgASAAkJtxkBIQA7AgAVAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn9KAAIfAAkJXR4kBwCjAgAfAAkJXR4kBwCjAgAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAABLgAECn8VAAIPAAcJsAEj+gCPAAAPAAcJsAEj+gCPAAAAAA==.',
Je='Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAABLgAECn8gAAIRAAcJrAmghQAaAQARAAcJrAmghQAaAQAAAA==.',
Jo='Jofixit:BAABLgAECn9KAAIRAAkJnR/1DADXAgARAAkJnR/1DADXAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaepop:BAABLgAECn8TAAISAAgJfBEFcQBRAQASAAgJfBEFcQBRAQAAAA==.Kanda:BAABLgAECn8eAAIRAAgJUxz1IgA0AgARAAgJUxz1IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8zAAMRAAkJDCPNCQD2AgARAAkJDCPNCQD2AgAZAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9BAAIRAAkJbhxpEwCgAgARAAkJbhxpEwCgAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8MAAIgAAQJYxOPJgALAQAgAAQJYxOPJgALAQAuAAQKfzgAAyEACQl7H/0CAPgCACEACAmeH/0CAPgCACAACQnkF+8TACQCAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMLAAgJsBpfEADqAQALAAgJsBpfEADqAQAMAAEJAACDfgEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8TAAIDAAUJ6RUDHAAYAQADAAUJ6RUDHAAYAQAuAAQKfx4AAgMACAmkGlwXAFwCAAMACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.',
Ko='Kobane:BAAALgAECgUJDgAAAA==.Kodali:BAAALgAECgUJDAAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lohuugg:BAAALgAECgMJAwABLgAFFAQJCwABAGwYAA==.Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECggJDwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAABLgAECn8UAAIBAAYJsQXstQDPAAABAAYJsQXstQDPAAAAAA==.Magicpantiez:BAABLgAECn8ZAAIPAAgJkh1XPwB7AgAPAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Malexling:BAABLgAECn8zAAIOAAcJcx6JOAAHAgAOAAcJcx6JOAAHAgAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8PAAIPAAQJ4w95VAApAQAPAAQJ4w95VAApAQAuAAQKfycAAg8ACQmGGxYxAD0CAA8ACQmGGxYxAD0CAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMTAAkJKhQvJwBzAQATAAgJoRIvJwBzAQAWAAkJBwMfQQDSAAAAAA==.Mitternacht:BAABLgAECn8hAAIDAAkJOCDyBQDuAgADAAkJOCDyBQDuAgABLgAECgkJQwARADsiAA==.',
Mo='Mooncraig:BAABLgAECn9JAAQJAAkJnBtbDAB8AgAJAAkJnBtbDAB8AgAHAAcJdxE5QwBxAQAeAAMJaw85KgCcAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAABLgAECn8tAAIIAAcJsh9FCgAhAgAIAAcJsh9FCgAhAgAAAA==.',
Na='Naiu:BAAALgAECgUJBQABLgAECggJFQACAHwWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgAGAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAECgUJBQABLgAECggJEgAGAAAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAUJEwADAOkVAA==.',
Ne='Nemeeia:BAAALgAECgYJDgAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIfAAgJYBcdFQBoAgAfAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn85AAIbAAgJFRb4HgDjAQAbAAgJFRb4HgDjAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8hAAIYAAcJLCIMAAA8AgAYAAcJLCIMAAA8AgAuAAQKf0UAAhgACQkIJkAAAMcDABgACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAITAAgJFRqSHQC6AQATAAgJFRqSHQC6AQAAAA==.',
Pi='Picolás:BAABLgAECn8cAAIPAAcJ1R7DUADSAQAPAAcJ1R7DUADSAQAAAA==.',
Po='Pog:BAAALgAFFAEJAgAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8vAAIXAAkJ4BBFGQDmAQAXAAkJ4BBFGQDmAQAAAA==.Probono:BAABLgAECn8hAAITAAcJEgpzPgDzAAATAAcJEgpzPgDzAAAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Ra='Rageleaf:BAAALgAECgUJDgAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAABLgAECn8XAAQcAAcJ3AnLEAA0AQAcAAcJ3AnLEAA0AQABAAQJDAI3+wBcAAAFAAEJxQLlQAAXAAAAAA==.',
Re='Reprises:BAABLgAECn8pAAMVAAkJqyJMAwALAwAVAAkJqyJMAwALAwASAAgJxBezPAC9AQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAKAH4UAA==.Restdrag:BAAALgAECgEJAQAAAA==.Revini:BAABLgAECn8dAAILAAgJcSSKAgBEAwALAAgJcSSKAgBEAwAAAA==.Rezø:BAABLgAECn8gAAMXAAcJyRAfLwA+AQAXAAYJNRMfLwA+AQAWAAIJkgvrYgA8AAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8kAAMYAAkJVA1FGgC9AQAYAAkJVA1FGgC9AQAZAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAACLgAFFH8IAAISAAMJcBk4SwDrAAASAAMJcBk4SwDrAAAuAAQKfzIAAhIACQkrGaUiADECABIACQkrGaUiADECAAAA.Sayven:BAAALgAECgMJAwAAAA==.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scounddrel:BAAALgAECgEJAQAAAA==.Scruffy:BAABLgAECn9FAAIQAAkJ+SIAAwAoAwAQAAkJ+SIAAwAoAwAAAA==.',
Se='Seferres:BAACLgAFFH8ZAAIKAAUJIyWpCwCmAQAKAAUJIyWpCwCmAQAuAAQKfyUAAgoACAnJJOEKAN0CAAoACAnJJOEKAN0CAAAA.Senortickle:BAABLgAECn8XAAIeAAkJISTOAQAJAwAeAAkJISTOAQAJAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8GAAISAAMJVQZ4XwCuAAASAAMJVQZ4XwCuAAAuAAQKfx4AAxIACAkbEEJVAKQBABIACAkbEEJVAKQBACIAAglSEIMmAFEAAAEuAAUUBQkZAAoAIyUA.Shawts:BAABLgAECn8bAAIPAAcJLhHKnwCXAQAPAAcJLhHKnwCXAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAECgcJIAAXAMkQAA==.',
Sk='Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgYJBgAAAA==.',
Sn='Snowflower:BAAALgADCgYJBgAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAwAAAA==.Sourdumpling:BAAALgAECgcJCwAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAEACsbAA==.Steve:BAABLgAECn8WAAMZAAcJJQ9oOQB9AQAZAAcJJQ9oOQB9AQAYAAEJCQWUXwAuAAAAAA==.Stimutax:BAABLgAECn8jAAIjAAgJsgarBgAfAQAjAAgJsgarBgAfAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAINAAcJ1yBJGgBCAgANAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJEgAAAA==.Taurenvar:BAABLgAECn8uAAIaAAkJxh0IBgBkAgAaAAkJxh0IBgBkAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAACLgAFFH8GAAIIAAMJ9hGBFgCsAAAIAAMJ9hGBFgCsAAAuAAQKfyAABAgACQkBDSAiABgBAAgACQkBDSAiABgBAAkABAlhBOhnAIIAAB4AAQk6Ax45ACQAAAAA.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIhAAgJBw72CQBvAQAhAAgJBw72CQBvAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgAAAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAIJAAkJVSTIAgA4AwAJAAkJVSTIAgA4AwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIdAAcJdhf2FABmAQAdAAcJdhf2FABmAQAAAA==.',
Ty='Tyn:BAAALgAECgcJBgAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8kAAIdAAgJDxWTEgCFAQAdAAgJDxWTEgCFAQAAAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIkAAkJtRvZCABJAgAkAAkJtRvZCABJAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn9GAAIRAAkJ+QytQADIAQARAAkJ+QytQADIAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAQJDQACAMMPAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECggJEwAAAA==.Zaligator:BAABLgAECn8fAAQhAAkJmRQSCAChAQAhAAgJ0RUSCAChAQAlAAMJtwUAPgB7AAAgAAIJuQeJbgBkAAAAAA==.Zayuna:BAAALgAFFAIJAgAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAIRAAkJJAuLSACwAQARAAkJJAuLSACwAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAITAAUJGBMXCABGAQATAAUJGBMXCABGAQAuAAQKfygAAhMACAk6ISsNALECABMACAk6ISsNALECAAAA.Zombear:BAAALgAECgYJCAABLgAFFAcJIQAYACwiAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMEAAkJKxsVDwCPAgAEAAkJKxsVDwCPAgAQAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8iAAIBAAcJUQmPiAAfAQABAAcJUQmPiAAfAQAAAA==.',
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
