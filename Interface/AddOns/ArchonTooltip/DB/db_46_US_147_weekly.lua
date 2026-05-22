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

local lookup = {'Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Warlock-Destruction','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DemonHunter-Havoc','Priest-Holy','Druid-Guardian','Priest-Discipline','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Warrior-Fury','Warlock-Affliction','Paladin-Protection','Druid-Feral','Rogue-Subtlety','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','Druid-Restoration','DemonHunter-Vengeance','Mage-Fire','Warrior-Arms','Evoker-Preservation',}
local provider = {region='US',realm='Maelstrom',name='US',type='weekly',zone=46,date='2026-05-16',data={Ae='Aellaleander:BAAALgAECgYJCgAAAA==.',
An='Annà:BAAALgADCgUJCgABLgAFFAQJCwABAGwYAA==.',
Ap='Aphrodotty:BAAALgAECgEJAQAAAA==.Apocolapse:BAAALgADCggJFAAAAA==.',
Ar='Ari:BAAALgAECggJCAAAAA==.',
As='Asahhealer:BAABLgAECn8wAAMCAAgJyRt6DwCFAgACAAgJyRt6DwCFAgADAAQJYAUKbACTAAAAAA==.Aszcuul:BAAALgADCgMJAwABLgAECgkJJwAEAC0bAA==.',
Au='Aurorabelli:BAABLgAECn8bAAMCAAgJuxKAJwDJAQACAAgJuxKAJwDJAQADAAUJHwa+XQDNAAAAAA==.Auróra:BAACLgAFFH8LAAIBAAQJbBgWEABgAQABAAQJbBgWEABgAQAuAAQKfzYAAwEACQnWJBQFABUDAAEACQnWJBQFABUDAAUAAQkAAA5pAD8AAAAA.Aurõrä:BAAALgAECgQJBAAAAA==.',
Az='Azlia:BAAALgAECgcJEAABLgAFFAMJAwAGAAAAAA==.Azrabaine:BAAALgADCgMJBQAAAA==.Azureheim:BAAALgADCgEJAQAAAA==.',
['Aú']='Aúra:BAAALgAFFAIJBAABLgAFFAQJEAAHAPgiAA==.',
Ba='Bahumn:BAAALgAECggJEQAAAA==.Bangpôwbôôm:BAABLgAECn8wAAMIAAgJ0R+lCAA/AgAIAAgJAh6lCAA/AgAJAAgJLBl6WADoAQAAAA==.',
Be='Beornach:BAAALgADCgMJAwAAAA==.Bergles:BAABLgAECn8zAAMKAAkJChLqGADyAQAKAAkJChLqGADyAQALAAUJpBC4uwC+AAAAAA==.',
Bi='Biggestfeet:BAABLgAECn8hAAIMAAgJaxwiNQCfAgAMAAgJaxwiNQCfAgABLgAFFAMJBQANADEYAA==.',
Bl='Bloodmourne:BAAALgADCgYJBwAAAA==.',
Bo='Bobbybigtree:BAAALgAECgYJBwAAAA==.Bogeyman:BAAALgADCgcJDQABLgAECggJHwAOAI8RAA==.Bowjobs:BAAALgADCgUJBQABLgAECgYJEgAGAAAAAA==.',
Br='Brivia:BAAALgAECgMJAwABLgAFFAQJCwABAGwYAA==.Brynne:BAAALgADCgUJBQAAAA==.',
Bu='Bullazarith:BAAALgAECgcJEQABLgAFFAUJFAAPABgTAA==.Bumboclott:BAAALgAECgEJAQAAAA==.Buruwar:BAAALgAECgcJEgAAAA==.',
Ca='Camel:BAABLgAECn8fAAMKAAYJXxrLLABdAQAKAAUJBRjLLABdAQALAAYJrA2rlQD9AAAAAA==.Cattlestance:BAABLgAECn8YAAIQAAgJuxGTEgBxAQAQAAgJuxGTEgBxAQAAAA==.',
Ch='Chastitylock:BAAALgAECgYJDAAAAA==.Cheryl:BAAALgADCgcJCQAAAA==.',
Cl='Clare:BAAALgADCgYJBgAAAA==.',
Co='Cougar:BAAALgAECgQJBwAAAA==.',
Cr='Crithappens:BAAALgAECgQJAwABLgAFFAQJCwABAGwYAA==.',
Da='Damaged:BAAALgAECgYJEgAAAA==.Danystormbrn:BAAALgADCgYJBgAAAA==.Darkjade:BAAALgADCgUJBwAAAA==.Dashdashdash:BAABLgAECn81AAIRAAgJ7B8ABwB0AgARAAgJ7B8ABwB0AgAAAA==.Davethediva:BAAALgADCgcJCwAAAA==.Daztok:BAAALgADCgkJCwAAAA==.',
Db='Dboldave:BAABLgAECn8fAAIQAAgJChfHDQC+AQAQAAgJChfHDQC+AQAAAA==.',
De='Deceiverdave:BAAALgAECgYJCgAAAA==.Demoniouss:BAAALgAECgYJBgAAAA==.Destyne:BAABLgAECn8jAAISAAgJpRXNFQDZAQASAAgJpRXNFQDZAQAAAA==.Dethlorddude:BAAALgADCgMJAwAAAA==.Devlorr:BAAALgADCgYJBgAAAA==.',
Do='Dopehustsla:BAAALgADCgUJCQAAAA==.',
Dr='Draggussy:BAABLgAECn8aAAIMAAgJJxUNSwC3AQAMAAgJJxUNSwC3AQAAAA==.Dragoonette:BAAALgADCgIJAgAAAA==.Drezlek:BAAALgAECgEJAQAAAA==.',
Du='Durkanis:BAABLgAECn8sAAITAAgJ/h2ZBQBVAgATAAgJ/h2ZBQBVAgAAAA==.',
['Dë']='Dëathlock:BAAALgADCgYJAgAAAA==.',
Ec='Ectasee:BAABLgAECn8yAAMCAAkJRyQUAQCgAwACAAkJRyQUAQCgAwADAAMJ8RBUUACeAAAAAA==.',
Ei='Eirenus:BAAALgAECgYJBwABLgAECgcJGgAUAFcMAA==.',
El='Element:BAAALgAECgQJBAAAAA==.',
Em='Emi:BAACLgAFFH8IAAIDAAQJGAiOGgD/AAADAAQJGAiOGgD/AAAuAAQKfxwAAwMACAnEFVklAGYBAAMABwnXFFklAGYBAAIABAlbGDhxAMsAAAAA.',
En='Enøch:BAAALgAECgMJAwAAAA==.',
Er='Eriktherod:BAAALgAECgUJBQAAAA==.',
Ey='Eyekilledyou:BAABLgAECn8VAAIVAAYJfx0AGQCNAQAVAAYJfx0AGQCNAQABLgAECggJIwANAG4iAA==.',
Fa='Fanuc:BAABLgAECn8iAAMCAAgJQyM9BgAFAwACAAgJQyM9BgAFAwAWAAEJkxSYKgA7AAAAAA==.',
Fe='Felbawlz:BAABLgAECn8fAAIOAAgJjxHVWQAoAQAOAAgJjxHVWQAoAQAAAA==.Felenas:BAAALgAECgQJBAAAAA==.Fenex:BAAALgADCgMJAwAAAA==.Fenicks:BAAALgADCgQJBAAAAA==.Fenrir:BAAALgAECgcJDwAAAA==.',
Fi='Fioremma:BAAALgADCgIJAgAAAA==.Firestar:BAAALgAFFAMJAwAAAA==.Fistfawk:BAAALgADCgYJBwABLgAECgYJEgAGAAAAAA==.',
Fo='Forthrich:BAABLgAECn8vAAILAAkJYQpfXQBtAQALAAkJYQpfXQBtAQAAAA==.Fozuul:BAAALgAECgkJEwABLgAECgkJJwAEAC0bAA==.',
Fr='Fruit:BAAALgAECgYJBgAAAA==.Frâust:BAAALgADCgkJCQAAAA==.',
Ga='Galaedra:BAAALgADCgEJAQAAAA==.Garnett:BAAALgAECgYJCgAAAA==.Gawkin:BAABLgAECn8tAAMKAAgJAh0TEgCCAgAKAAgJAh0TEgCCAgALAAUJABaXcABBAQAAAA==.',
Gi='Gizmoe:BAAALgAECgEJAQAAAA==.',
Go='Gobbs:BAAALgADCgcJEwABLgAECggJHgAXAJAbAA==.',
Gr='Grimreäper:BAAALgAECgMJBAAAAA==.Grimspear:BAAALgAECgkJDAAAAA==.Gromit:BAAALgADCgIJAQAAAA==.',
Gu='Gulev:BAAALgAECgUJBQAAAA==.Gumbercules:BAABLgAECn8ZAAIYAAUJ8COlLwDxAQAYAAUJ8COlLwDxAQAAAA==.Gurnsey:BAAALgAECgMJAwAAAA==.Gutholoydne:BAABLgAECn8bAAIZAAcJiRT+CwB6AQAZAAcJiRT+CwB6AQAAAA==.',
['Gæ']='Gæa:BAAALgADCgIJAgAAAA==.',
Ha='Hardreptile:BAAALgAECgUJCQAAAA==.Hardrockjoe:BAAALgAECgEJAQAAAA==.Haters:BAAALgAECgYJDAAAAA==.',
He='Heelorestus:BAABLgAECn8bAAMSAAkJhQ9MPQBFAQASAAYJwxBMPQBFAQAPAAkJBwyuNADwAAAAAA==.',
Hi='Hippocalypse:BAAALgAFFAIJAgABLgAFFAMJBQANADEYAA==.Hirculos:BAAALgAECggJEwAAAA==.',
Ho='Hokkai:BAAALgADCgEJAQAAAA==.Holyfrog:BAABLgAECn80AAMKAAkJtRkRFwBZAgAKAAkJtRkRFwBZAgALAAIJQgiO+wBfAAAAAA==.Holythis:BAACLgAFFH8IAAIaAAMJ9ws0CACjAAAaAAMJ9ws0CACjAAAuAAQKfysAAhoACQmLFqMGAHwCABoACQmLFqMGAHwCAAAA.',
Hu='Hurmin:BAAALgAECgIJAgAAAA==.',
['Hè']='Hèçate:BAAALgADCgMJBAAAAA==.',
Ig='Ignis:BAABLgAECn81AAIbAAkJzhReBwAFAgAbAAkJzhReBwAFAgAAAA==.',
Ik='Ikaruz:BAAALgAECgQJBwAAAA==.',
Il='Illaadden:BAABLgAECn8XAAMOAAkJphlEIQAIAgAOAAkJphlEIQAIAgARAAQJEw0tSADSAAAAAA==.',
In='Infiltrata:BAABLgAECn85AAIcAAgJfRv4DgDsAQAcAAgJfRv4DgDsAQAAAA==.',
Is='Isokzak:BAAALgADCgcJBwAAAA==.Isran:BAAALgADCgMJAwAAAA==.',
Ja='Jademyst:BAAALgADCgUJCgAAAA==.Janelik:BAAALgAECgQJDwAAAA==.',
Je='Jesterhunter:BAAALgAECgEJAQAAAA==.',
Ji='Jiinjo:BAAALgAECgMJAwAAAA==.Jinxi:BAABLgAECn8aAAIXAAYJQAqPegDqAAAXAAYJQAqPegDqAAAAAA==.',
Jo='Jofixit:BAABLgAECn85AAIXAAgJcyH9DgDDAgAXAAgJcyH9DgDDAgAAAA==.',
Ka='Kaazir:BAAALgADCgEJAgAAAA==.Kaepop:BAABLgAECn8RAAIOAAgJexEFcQBRAQAOAAgJexEFcQBRAQAAAA==.Kanda:BAABLgAECn8eAAIXAAgJUxynJgD1AQAXAAgJUxynJgD1AQAAAA==.Kastarnu:BAAALgADCgMJAwAAAA==.Kaynub:BAABLgAECn8wAAMXAAkJDCNnBAAXAwAXAAkJDCNnBAAXAwAdAAgJBx3qGQBbAgAAAA==.',
Ke='Kedri:BAABLgAECn84AAIXAAgJ1RmtIQAPAgAXAAgJ1RmtIQAPAgAAAA==.Keihas:BAACLgAFFH8HAAIeAAMJUA5lKwDRAAAeAAMJUA5lKwDRAAAuAAQKfzMAAx8ACQl3H/0CAPgCAB8ACAmZH/0CAPgCAB4ACQnYF+0OAC0CAAAA.Keone:BAAALgAECgMJAwAAAA==.Keonebrew:BAAALgAECgEJAQAAAA==.Keonedk:BAABLgAECn8qAAMIAAgJohoUCwAJAgAIAAgJohoUCwAJAgAJAAEJAAB3OQEAAAAAAA==.Keonewar:BAAALgADCgcJBwAAAA==.',
Ki='Kikko:BAACLgAFFH8JAAIDAAQJrBDpFQAeAQADAAQJrBDpFQAeAQAuAAQKfx4AAgMACAmkGlwXAFwCAAMACAmkGlwXAFwCAAAA.Killswitch:BAAALgAECgUJBQAAAA==.',
Ko='Kobane:BAAALgAECgUJDgAAAA==.Kodali:BAAALgAECgUJDAAAAA==.Kots:BAAALgADCgEJAQAAAA==.',
Ku='Kurando:BAAALgAECgYJCAAAAA==.',
Ky='Kyedo:BAAALgADCggJCAAAAA==.',
Le='Leali:BAAALgAECgEJAgAAAA==.',
Li='Linarine:BAAALgAECgEJAQAAAA==.Lirianne:BAAALgAECgEJAQAAAA==.',
Lo='Lonka:BAAALgADCgUJBQAAAA==.Loptyr:BAAALgAECgIJAwAAAA==.Lorzul:BAAALgADCgEJAQAAAA==.',
Ma='Ma:BAAALgADCgQJBAAAAA==.Madashell:BAAALgADCgMJBgAAAA==.Madhunt:BAAALgADCgkJCQAAAA==.Madmonk:BAAALgADCgQJBwAAAA==.Maeeba:BAAALgAECgUJDAAAAA==.Magicpantiez:BAABLgAECn8ZAAIMAAgJkh1XPwB7AgAMAAgJkh1XPwB7AgAAAA==.Mahito:BAAALgADCgQJBgAAAA==.Majeh:BAAALgAECgEJAwABLgAECgYJCAAGAAAAAA==.Malexling:BAABLgAECn8kAAILAAYJGhwCUgCJAQALAAYJGhwCUgCJAQAAAA==.',
Mc='Mcßoom:BAAALgADCgIJAQAAAA==.',
Me='Mezrè:BAACLgAFFH8JAAIMAAMJFRAOWAD0AAAMAAMJFRAOWAD0AAAuAAQKfycAAgwACQmFG/4hAFgCAAwACQmFG/4hAFgCAAAA.',
Mi='Mitteny:BAABLgAECn8lAAMPAAgJohLxHQCAAQAPAAgJohLxHQCAAQASAAgJzwJlPQCvAAAAAA==.Mitternacht:BAABLgAECn8VAAIDAAgJYBTwHACkAQADAAgJYBTwHACkAQABLgAECggJLAAXABodAA==.',
Mo='Mooncraig:BAABLgAECn84AAMgAAgJch3CDwASAgAgAAgJch3CDwASAgAhAAcJdhFjOABtAQAAAA==.Moroku:BAAALgADCgIJBAAAAA==.',
Ms='Msdeath:BAABLgAECn8fAAITAAYJkherEwBEAQATAAYJkherEwBEAQAAAA==.',
Na='Naois:BAAALgAECgEJAQABLgAECgYJCAAGAAAAAA==.Nargrark:BAAALgAECgEJAQAAAA==.Nashalion:BAAALgAECgUJBQABLgAECggJEQAGAAAAAA==.Nazureser:BAAALgAECgMJAwABLgAFFAQJCQADAKwQAA==.',
Ne='Nemeeia:BAAALgAECgYJDQAAAA==.',
Ni='Nickchurch:BAABLgAECn8VAAIcAAgJYBcdFQBoAgAcAAgJYBcdFQBoAgAAAA==.Ninkaly:BAAALgADCgQJBAAAAA==.',
No='Nodarf:BAABLgAECn8kAAIYAAgJFgt+KwBXAQAYAAgJFgt+KwBXAQAAAA==.Nomomayans:BAAALgADCgYJDAAAAA==.Noravanfrost:BAAALgADCggJCAAAAA==.',
Ny='Nyohbi:BAAALgAECgQJBAAAAA==.',
Od='Odric:BAAALgADCgMJAwAAAA==.',
Pa='Paingiver:BAAALgAECgEJAQAAAA==.Panda:BAACLgAFFH8bAAIVAAYJ2SQMAAA8AgAVAAYJ2SQMAAA8AgAuAAQKf0MAAhUACQkIJkAAAMcDABUACQkIJkAAAMcDAAAA.Pawsfermana:BAAALgADCgQJBAAAAA==.',
Ph='Phoenixaka:BAAALgAECgYJCgAAAA==.Phyllip:BAABLgAECn80AAIPAAgJFhrWFADVAQAPAAgJFhrWFADVAQAAAA==.',
Pi='Picolás:BAABLgAECn8cAAIMAAcJ1R5EOgDvAQAMAAcJ1R5EOgDvAQAAAA==.',
Po='Pog:BAAALgAFFAEJAQAAAA==.',
Pr='Prepare:BAAALgAECgYJDQAAAA==.Prime:BAAALgADCgMJAwAAAA==.Primrose:BAABLgAECn8sAAIUAAgJ5BAuGAC4AQAUAAgJ5BAuGAC4AQAAAA==.Probono:BAABLgAECn8bAAIPAAYJ2wrjNwDgAAAPAAYJ2wrjNwDgAAAAAA==.',
Pu='Puncher:BAAALgADCgYJBgAAAA==.',
Ra='Rageleaf:BAAALgAECgUJDgAAAA==.Rainee:BAAALgADCgQJBAAAAA==.Ratbag:BAAALgADCgUJBQAAAA==.Raxefal:BAAALgAECgUJBQAAAA==.',
Re='Reprises:BAABLgAECn8mAAMRAAgJOyLYBACuAgARAAgJOyLYBACuAgAOAAgJxBexLQDHAQAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAHAHwUAA==.Restdrag:BAAALgADCgkJCQAAAA==.Revini:BAABLgAECn8dAAIIAAgJcSSKAgBEAwAIAAgJcSSKAgBEAwAAAA==.Rezø:BAABLgAECn8aAAMUAAcJVwytLgAFAQAUAAYJBg6tLgAFAQASAAEJPwLMhQArAAAAAA==.',
Ro='Roadkillinn:BAABLgAECn8kAAMVAAkJVA1oEwDEAQAVAAkJVA1oEwDEAQAdAAEJAAABmwAWAAAAAA==.',
Ru='Rufus:BAAALgAECgYJDAAAAA==.Rumplefugly:BAAALgADCgcJBwAAAA==.',
Sa='Sableye:BAABLgAECn8yAAIOAAkJKxkAGgA2AgAOAAkJKxkAGgA2AgAAAA==.Sayven:BAAALgAECgMJAwAAAA==.',
Sc='Scarlxrd:BAAALgAECgIJAgAAAA==.Scruffy:BAABLgAECn83AAINAAkJmyLGAgAMAwANAAkJmyLGAgAMAwAAAA==.',
Se='Seferres:BAACLgAFFH8QAAIHAAQJ+CLpBwCbAQAHAAQJ+CLpBwCbAQAuAAQKfyMAAgcACAm3JOEKAN0CAAcACAm3JOEKAN0CAAAA.Senortickle:BAABLgAECn8XAAIbAAkJICQKAQAcAwAbAAkJICQKAQAcAwAAAA==.',
Sh='Shaunara:BAACLgAFFH8FAAIOAAMJ/wVqSQC8AAAOAAMJ/wVqSQC8AAAuAAQKfx4AAw4ACAkbEEJVAKQBAA4ACAkbEEJVAKQBACIAAglSEIMmAFEAAAEuAAUUBAkQAAcA+CIA.Shawts:BAABLgAECn8bAAIMAAcJLRH2egBFAQAMAAcJLRH2egBFAQAAAA==.Shisuii:BAAALgAECgEJAQAAAA==.Shìva:BAAALgAECgQJBAAAAA==.Shînon:BAAALgADCgUJBQABLgAECgcJGgAUAFcMAA==.',
Sk='Skragrott:BAAALgADCgEJAQAAAA==.',
Sm='Smegmo:BAAALgAECgUJBQAAAA==.',
So='Solar:BAAALgAECgcJAgAAAA==.Sonicice:BAAALgAECgEJAwAAAA==.',
Sp='Spoonprotal:BAAALgAECgUJBQAAAA==.',
St='Starburnz:BAAALgADCgkJDQABLgAECgkJJwAEAC0bAA==.Steve:BAABLgAECn8WAAMdAAcJJQ9oOQB9AQAdAAcJJQ9oOQB9AQAVAAEJCQWUTgAvAAAAAA==.Stimutax:BAABLgAECn8jAAIjAAgJsQb5BAAsAQAjAAgJsQb5BAAsAQAAAA==.',
Su='Suikotsu:BAAALgADCgEJAQAAAA==.Suntso:BAABLgAECn8nAAIKAAcJ1yBJGgBCAgAKAAcJ1yBJGgBCAgAAAA==.',
Sy='Symmaendon:BAAALgADCgcJBwAAAA==.',
['Sì']='Sìnìster:BAAALgADCgYJBwAAAA==.',
Ta='Tahjin:BAAALgAECgUJDwAAAA==.Taurenvar:BAABLgAECn8uAAIWAAkJyB2ZAwB9AgAWAAkJyB2ZAwB9AgAAAA==.Taziel:BAAALgAECggJDgAAAA==.',
Te='Teddyhappy:BAABLgAECn8fAAQTAAgJuQ0uGwDzAAATAAgJuQ0uGwDzAAAgAAQJYQToZwCCAAAbAAEJOgMeOQAkAAAAAA==.',
Th='Thanosondh:BAAALgADCgcJBwAAAA==.Thorodin:BAAALgAECgIJAgAAAA==.',
Ti='Tierra:BAAALgADCgQJBAAAAA==.Tingariban:BAAALgAECgcJDgAAAA==.',
To='Tohruu:BAABLgAECn8gAAIfAAgJBw6oBwB5AQAfAAgJBw6oBwB5AQAAAA==.Totaleclipse:BAAALgADCgIJAgAAAA==.Toterminator:BAAALgADCgYJCAAAAA==.',
Tr='Traurigkeit:BAAALgAECgcJDAAAAA==.Tristesza:BAAALgAECgIJAQAAAA==.Trollbrudda:BAABLgAECn8tAAIgAAgJ0CN1BQDFAgAgAAgJ0CN1BQDFAgAAAA==.',
Tw='Tweedledumm:BAABLgAECn8cAAIaAAcJdhfhDwBuAQAaAAcJdhfhDwBuAQAAAA==.',
Um='Umgross:BAAALgADCgYJBgAAAA==.',
Ve='Veldramaar:BAAALgADCgEJAQAAAA==.',
Vi='Vikirnoff:BAAALgAECgcJCQAAAA==.Vilehatred:BAABLgAECn8jAAIaAAgJDxX+DQCLAQAaAAgJDxX+DQCLAQAAAA==.',
Vo='Voltz:BAAALgAECgEJAQAAAA==.',
Wa='Wallis:BAAALgAECgEJAQAAAA==.Wattzazugzug:BAAALgAECgUJDwAAAA==.Waverunner:BAABLgAECn8hAAIkAAkJtRt0BQBkAgAkAAkJtRt0BQBkAgAAAA==.',
Wi='Wittick:BAAALgADCgUJBgAAAA==.',
Xe='Xeriator:BAABLgAECn81AAIXAAgJYgxZRAB8AQAXAAgJYgxZRAB8AQAAAA==.',
Ya='Yame:BAAALgADCgcJBwABLgAFFAMJCAACAEsQAA==.',
Yo='Yoyoma:BAAALgAECgQJDwAAAA==.',
Za='Zakarie:BAAALgAECggJEgAAAA==.Zaligator:BAABLgAECn8eAAQfAAgJiRbrBQCxAQAfAAgJ0RXrBQCxAQAlAAMJtwUAPgB7AAAeAAEJawjRbgAvAAAAAA==.Zayuna:BAAALgAECgQJBAAAAA==.',
Zi='Zil:BAAALgAECgEJAgAAAA==.Ziptoria:BAABLgAECn8hAAIXAAgJtQqXTgBcAQAXAAgJtQqXTgBcAQAAAA==.',
Zo='Zodijackyl:BAACLgAFFH8UAAIPAAUJGBMXCABGAQAPAAUJGBMXCABGAQAuAAQKfygAAg8ACAk6IYkNAC0CAA8ACAk6IYkNAC0CAAAA.Zombear:BAAALgAECgYJBwABLgAFFAYJGwAVANkkAA==.',
Zu='Zurosh:BAAALgADCgEJAQAAAA==.Zuulian:BAABLgAECn8nAAMEAAkJLRubCgCMAgAEAAkJLRubCgCMAgANAAYJeRZvLQB3AQAAAA==.',
Zy='Zylph:BAABLgAECn8cAAIBAAYJtQgGiwDmAAABAAYJtQgGiwDmAAAAAA==.',
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
