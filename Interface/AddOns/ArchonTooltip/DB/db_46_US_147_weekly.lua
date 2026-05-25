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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Balance','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-05-23',data={Ae='Aellaleander:BAAALgAECgcJCwAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwABAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Ari:BAAALgAECggJCAAAAA==.',
As='Asahhealer:BAACLgAFFH8FAAICAAIJow5QTQB9AAACAAIJow5QTQB9AAAuAAQKfzIAAwIACAnJGxEUAH4CAAIACAnJGxEUAH4CAAMABAlgBQpsAJMAAAAA.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAEACsbAA==.',
Au='Aurorabelli:BAABLgAECn8kAAMCAAkJYhOtIQAYAgACAAkJYhOtIQAYAgADAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAIBAAQJbBgWEABgAQABAAQJbBgWEABgAQAuAAQKfzYAAwEACQnhJEkHAAsDAAEACQnhJEkHAAsDAAUAAQkAAA5pAD8AAAAA.Aurõrä:BAAALgAECgUJCgAAAA==.',
Av='Averlence:BAAALgAECgMJAwAAAA==.',
Az='Azlia:BAAALgAECgcJEQABLgAFFAMJAwAGAAAAAA==.Azrabaine:BAAALgAECgEJAQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAABLgAFFH8GAAQHAAMJWASPPQCbAAAHAAMJWASPPQCbAAAIAAEJEhotIABNAAAJAAEJ8wQfPQA8AAABLgAFFAUJFQAKACMlAA==.',
Ba='Bahumn:BAAALgAECggJEgAAAA==.Balboga:BAAALgADCggJCAABLgAECgUJDgAGAAAAAA==.Bangpôwbôôm:BAABLgAECn84AAMLAAkJhiAyBADUAgALAAkJNyAyBADUAgAMAAgJMBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMNAAkJChKUHgDnAQANAAkJChKUHgDnAQAOAAUJpBB63wC3AAAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIPAAgJaxwiNQCfAgAPAAgJaxwiNQCfAgABLgAFFAMJBQAQADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgYJDQAAAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwARAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAGAAAAAA==.',
Br='Brivia:BAAALgAECgUJCAABLgAFFAQJCwABAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAASABgTAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECgcJEgAAAA==.',
Ca='Camel:BAABLgAECn8lAAMNAAYJXxp1NABWAQANAAUJBRh1NABWAQAOAAYJqQ/anwAWAQAAAA==.Cattlestance:BAABLgAECn8bAAITAAkJDRP/DwDAAQATAAkJDRP/DwDAAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJEQAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgQJBwAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwABAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgADCgUJBwAAAA==.Dashdashdash:BAABLgAECn87AAIUAAgJ7R+fCAB2AgAUAAgJ7R+fCAB2AgAAAA==.Davethediva:BAAALgADCgcJCwAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAITAAgJ5BYlEQCtAQATAAgJ5BYlEQCtAQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJDAAAAA==.Derazen:BAAALgADCgMJBAAAAA==.Destyne:BAABLgAECn8jAAIVAAgJpRWqGgDMAQAVAAgJpRWqGgDMAQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJCwAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8dAAIPAAgJNRX8VwC4AQAPAAgJNRX8VwC4AQAAAA==.Dragoonette:BAAALgADCgIJAgAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8vAAIIAAkJSx1yBACiAgAIAAkJSx1yBACiAgAAAA==.',
['Dë']='Dëathlock:BAAALgADCgYJAgABLgAECgkJNQARAD8MAA==.',
Ec='Ectasee:BAABLgAECn8yAAMCAAkJRySyAQCZAwACAAkJRySyAQCZAwADAAMJ8RAqXwCVAAAAAA==.',
Ei='Eianhander:BAAALgADCgMJAwAAAA==.Eirenus:BAAALgAECgcJDAABLgAECgcJGwAWANYOAA==.',
El='Element:BAAALgAECgQJBAAAAA==.',
Em='Emi:BAACLgAFFH8IAAIDAAQJGAieIAD1AAADAAQJGAieIAD1AAAuAAQKfxwAAwMACAnEFWktAGABAAMABwnYFGktAGABAAIABAlbGDhxAMsAAAAA.',
En='Enøch:BAAALgAFFAEJAQAAAA==.',
Er='Eriktherod:BAAALgAECgUJBgAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8bAAMXAAcJBxzDFgDPAQAXAAcJBxzDFgDPAQAYAAEJXRsbLABNAAABLgAECggJKAAQAG8iAA==.',
Fa='Fanuc:BAABLgAECn8qAAMCAAkJQyJOBABNAwACAAkJQyJOBABNAwAZAAcJwRH6FAArAQAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAIRAAgJjxFhaQAsAQARAAgJjxFhaQAsAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAABLgAECn8VAAILAAcJiheYFQCQAQALAAcJiheYFQCQAQAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJAwAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAGAAAAAA==.',
Fo='Forthrich:BAABLgAECn81AAIOAAkJbAoDagB7AQAOAAkJbAoDagB7AQAAAA==.Fozuul:BAABLgAECn8UAAMHAAkJBRKbJQD+AQAHAAkJBRKbJQD+AQAJAAEJpRUTbwBAAAABLgAECgkJJwAEACsbAA==.',
Fr='Fruit:BAAALgAECgYJBgAAAA==.Frâust:BAAALgADCgkJDQAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMNAAgJAh0TEgCCAgANAAgJAh0TEgCCAgAOAAUJABZmiwA5AQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Goaty:BAAALgAECgUJBQAAAA==.Gobbs:BAAALgADCgcJEwABLgAECggJHgAaAJEbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIbAAUJ8COlLwDxAQAbAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8bAAIcAAcJiRT+CwB6AQAcAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJDQAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMVAAkJhQ9MPQBFAQAVAAYJwxBMPQBFAQASAAkJBwxKPAD3AAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQAQADEYAA==.Hirculos:BAABLgAECn8ZAAIbAAgJFxfhHQDbAQAbAAgJFxfhHQDbAQAAAA==.',
Ho='Hokkai:BAAALgADCgEJAQAAAA==.Holyfrog:BAABLgAECn89AAMNAAkJxRkRFwBZAgANAAkJxRkRFwBZAgAOAAIJQghTIAFfAAAAAA==.Holythis:BAACLgAFFH8MAAIdAAQJPgw2BwDZAAAdAAQJPgw2BwDZAAAuAAQKfysAAh0ACQmLFqMGAHwCAB0ACQmLFqMGAHwCAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn81AAIeAAkJzhQ3CQAAAgAeAAkJzhQ3CQAAAgAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMRAAkJtxk2HgBCAgARAAkJtxk2HgBCAgAUAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn9CAAIfAAkJsB31BwCFAgAfAAkJsB31BwCFAgAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAABLgAECn8UAAIPAAYJrQFD+ACJAAAPAAYJrQFD+ACJAAAAAA==.',
Je='Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAABLgAECn8fAAIaAAYJ5woWigD5AAAaAAYJ5woWigD5AAAAAA==.',
Jo='Jofixit:BAABLgAECn9CAAIaAAkJnR+fCwDTAgAaAAkJnR+fCwDTAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaepop:BAABLgAECn8SAAIRAAgJfBEFcQBRAQARAAgJfBEFcQBRAQAAAA==.Kanda:BAABLgAECn8eAAIaAAgJUxz1IgA0AgAaAAgJUxz1IgA0AgAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8zAAMaAAkJDCOjBwD/AgAaAAkJDCOjBwD/AgAYAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn9AAAIaAAkJCxzYEQCZAgAaAAkJCxzYEQCZAgAAAA==.Kehila:BAAALgAECgEJAQAAAA==.Keihas:BAACLgAFFH8LAAIgAAQJgBEEIgAUAQAgAAQJgBEEIgAUAQAuAAQKfzgAAyEACQl7H/0CAPgCACEACAmeH/0CAPgCACAACQnkF1MSAC4CAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMLAAgJsBptDgDyAQALAAgJsBptDgDyAQAMAAEJAAC3YgEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8OAAIDAAUJJhR1GAAjAQADAAUJJhR1GAAjAQAuAAQKfx4AAgMACAmkGlwXAFwCAAMACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.',
Ko='Kobane:BAAALgAECgUJDgAAAA==.Kodali:BAAALgAECgUJDAAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgcJCgAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECggJCgAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Lu='Lucifeàr:BAAALgAECgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAAALgAECgYJEgAAAA==.Magicpantiez:BAABLgAECn8ZAAIPAAgJkh1XPwB7AgAPAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgcJCgAGAAAAAA==.Malexling:BAABLgAECn8rAAIOAAcJMh1WQQDjAQAOAAcJMh1WQQDjAQAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8MAAIPAAQJ4w9+SgAzAQAPAAQJ4w9+SgAzAQAuAAQKfycAAg8ACQmGGwosAEwCAA8ACQmGGwosAEwCAAAA.',
Mi='Mitteny:BAABLgAECn8oAAMSAAkJKhT3IgCIAQASAAgJoRL3IgCIAQAVAAkJBwPHPQDVAAAAAA==.Mitternacht:BAABLgAECn8eAAIDAAkJVh9GBgDcAgADAAkJVh9GBgDcAgAAAA==.',
Mo='Mooncraig:BAABLgAECn9BAAQJAAkJgBtYDQBcAgAJAAkJgBtYDQBcAgAHAAcJdxELQABvAQAeAAMJaw+MJQCkAAAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAABLgAECn8lAAIIAAYJxBfYFwBSAQAIAAYJxBfYFwBSAQAAAA==.',
Na='Naiu:BAAALgAECgUJBQABLgAECggJFQACAHwWAA==.Naois:BAAALgAECgYJCAABLgAECgcJCgAGAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAECgUJBQABLgAECggJEgAGAAAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAUJDgADACYUAA==.',
Ne='Nemeeia:BAAALgAECgYJDQAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIfAAgJYBcdFQBoAgAfAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn8xAAIbAAgJ7hHLIwCxAQAbAAgJ7hHLIwCxAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8fAAIXAAcJLCIMAAA8AgAXAAcJLCIMAAA8AgAuAAQKf0UAAhcACQkIJkAAAMcDABcACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAISAAgJFRorGgDPAQASAAgJFRorGgDPAQAAAA==.',
Pi='Picolás:BAABLgAECn8cAAIPAAcJ1R4+SwDdAQAPAAcJ1R4+SwDdAQAAAA==.',
Po='Pog:BAAALgAFFAEJAQAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8vAAIWAAkJ4BCkFgDzAQAWAAkJ4BCkFgDzAQAAAA==.Probono:BAABLgAECn8gAAISAAYJ2wpWQADjAAASAAYJ2wpWQADjAAAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Ra='Rageleaf:BAAALgAECgUJDgAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAAALgAECgYJDwAAAA==.',
Re='Reprises:BAABLgAECn8pAAMUAAkJqyKUAgAUAwAUAAkJqyKUAgAUAwARAAgJxBexOADCAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAKAH4UAA==.Restdrag:BAAALgADCgkJDwAAAA==.Revini:BAABLgAECn8dAAILAAgJcSSKAgBEAwALAAgJcSSKAgBEAwAAAA==.Rezø:BAABLgAECn8bAAMWAAcJ1g6pNwADAQAWAAYJBg6pNwADAQAVAAIJkgtwXQA9AAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8kAAMXAAkJVA0mGADAAQAXAAkJVA0mGADAAQAYAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAACLgAFFH8GAAIRAAMJSRldQgD1AAARAAMJSRldQgD1AAAuAAQKfzIAAhEACQkrGTgfADwCABEACQkrGTgfADwCAAAA.Sayven:BAAALgAECgMJAwAAAA==.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scruffy:BAABLgAECn88AAIQAAkJyyIiAwAZAwAQAAkJyyIiAwAZAwAAAA==.',
Se='Seferres:BAACLgAFFH8VAAIKAAUJIyXJCACuAQAKAAUJIyXJCACuAQAuAAQKfyMAAgoACAm5JOEKAN0CAAoACAm5JOEKAN0CAAAA.Senortickle:BAABLgAECn8XAAIeAAkJISR3AQATAwAeAAkJISR3AQATAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8FAAIRAAMJ/wXvVQC1AAARAAMJ/wXvVQC1AAAuAAQKfx4AAxEACAkbEEJVAKQBABEACAkbEEJVAKQBACIAAglSEIMmAFEAAAEuAAUUBQkVAAoAIyUA.Shawts:BAABLgAECn8bAAIPAAcJLhE+iQBJAQAPAAcJLhE+iQBJAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAECgcJGwAWANYOAA==.',
Sk='Skordo:BAAALgAECgEJAQAAAA==.Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgUJBQAAAA==.',
Sn='Snowflower:BAAALgADCgMJAwAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAwAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAEACsbAA==.Steve:BAABLgAECn8WAAMYAAcJJQ9oOQB9AQAYAAcJJQ9oOQB9AQAXAAEJCQVMWQAuAAAAAA==.Stimutax:BAABLgAECn8jAAIjAAgJsga+BQAwAQAjAAgJsga+BQAwAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAINAAcJ1yBJGgBCAgANAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJDwAAAA==.Taurenvar:BAABLgAECn8uAAIZAAkJxh0uBQBpAgAZAAkJxh0uBQBpAgAAAA==.Taziel:BAAALgAECggJEQAAAA==.',
Te='Teddyhappy:BAABLgAECn8gAAQIAAkJAQ3jHQAaAQAIAAkJAQ3jHQAaAQAJAAQJYQToZwCCAAAeAAEJOgMeOQAkAAAAAA==.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIhAAgJBw5FCQBxAQAhAAgJBw5FCQBxAQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDgAAAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8wAAIJAAkJVSRnAgA7AwAJAAkJVSRnAgA7AwAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIdAAcJdhdHEwBoAQAdAAcJdhdHEwBoAQAAAA==.',
Ty='Tyn:BAAALgAECgcJBQAAAA==.',
Um='Umgross:BAAALgADCgYJCwAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8kAAIdAAgJDxX1EACIAQAdAAgJDxX1EACIAQAAAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIkAAkJtRuUBwBXAgAkAAkJtRuUBwBXAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn8+AAIaAAkJNAxkPQDAAQAaAAkJNAxkPQDAAQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAQJDAACAKINAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECggJEwAAAA==.Zaligator:BAABLgAECn8fAAQhAAkJmRRtBwClAQAhAAgJ0RVtBwClAQAlAAMJtwUAPgB7AAAgAAIJuQcAagBlAAAAAA==.Zayuna:BAAALgAECgQJBAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8qAAIaAAkJJAskQgCwAQAaAAkJJAskQgCwAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAISAAUJGBMXCABGAQASAAUJGBMXCABGAQAuAAQKfygAAhIACAk6ISsNALECABIACAk6ISsNALECAAAA.Zombear:BAAALgAECgYJCAABLgAFFAcJHwAXACwiAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMEAAkJKxuUDQCOAgAEAAkJKxuUDQCOAgAQAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8hAAIBAAYJ/Ak7lwD4AAABAAYJ/Ak7lwD4AAAAAA==.',
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
