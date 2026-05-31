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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Monk-Brewmaster','Priest-Shadow','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Rogue-Outlaw','Druid-Feral','Monk-Windwalker','Warlock-Affliction',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgEJAQAAAA==.Addu:BAAALgAECgUJBQAAAA==.Adiforis:BAABLgAECn8UAAMBAAYJ6Q2VFQADAQABAAYJ6Q2VFQADAQACAAQJFgeBZQAAAAAAAA==.Adobo:BAAALgAECgkJDAAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIDAAgJpQlWEgAjAQADAAgJpQlWEgAjAQAAAA==.Aerandir:BAABLgAECn8UAAMEAAYJNQrjrwD5AAAEAAYJNQrjrwD5AAAFAAEJAAAXeQAqAAABLgAECgcJFgAGAL4NAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn8qAAIBAAgJXBKSDQBwAQABAAgJXBKSDQBwAQAAAA==.Alrekur:BAAALgAECgEJAQAAAA==.Alyestra:BAAALgAECgcJEwAAAA==.',
Am='Ambien:BAAALgAECgEJAgAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAHAJ0iAA==.Animyst:BAACLgAFFH8IAAIIAAQJ8hykGwBGAQAIAAQJ8hykGwBGAQAuAAQKfz4AAggACAkjJVgFAD0DAAgACAkjJVgFAD0DAAEuAAQKCQktAAcAnSIA.Anipaltu:BAACLgAFFH8IAAIJAAQJsAxpIgD5AAAJAAQJsAxpIgD5AAAuAAQKfx4AAgkACQm2HYcHAAEDAAkACQm2HYcHAAEDAAEuAAQKCQktAAcAnSIA.Aniron:BAABLgAECn8UAAIEAAYJchGhgwApAQAEAAYJchGhgwApAQABLgAECgkJLQAHAJ0iAA==.Anirot:BAABLgAECn8tAAIHAAkJnSK+AwBCAwAHAAkJnSK+AwBCAwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAHAJ0iAA==.Antoni:BAAALgAECgEJAQAAAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMKAAYJmQ6sXAAQAQAKAAYJmQ6sXAAQAQALAAYJ9AnYSQDKAAAAAA==.Arcanium:BAAALgAECgEJAgAAAA==.',
As='Astren:BAAALgAECgEJAQAAAA==.Asynsia:BAABLgAECn8oAAIMAAkJZiGWDgC9AgAMAAkJZiGWDgC9AgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Banashain:BAAALgADCgEJAgAAAA==.Bartholomew:BAABLgAECn8lAAIIAAkJphwbCgDaAgAIAAkJphwbCgDaAgAAAA==.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn8zAAIHAAkJ9CQtAQCvAwAHAAkJ9CQtAQCvAwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgUJBgAAAA==.',
Bo='Boffadeez:BAAALgAECgQJBQAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAgANAAAAAA==.Boryndin:BAABLgAECn8iAAIOAAkJohn7CwAYAgAOAAkJohn7CwAYAgAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8LAAIPAAQJaQ+4OgAhAQAPAAQJaQ+4OgAhAQAuAAQKfzUAAg8ACQl0GSw6ADoCAA8ACQl0GSw6ADoCAAAA.',
Bu='Bulgrim:BAAALgADCgMJBQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgcJBwABLgAECgkJJAAQANgNAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAABLgAECn8ZAAIRAAgJKiD0CwB3AgARAAgJKiD0CwB3AgAAAA==.Chrismeister:BAAALgAECgYJEAAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAECgkJDgAAAA==.',
Co='Codah:BAAALgAECgIJBgAAAA==.Coomonka:BAAALgADCgcJCQAAAA==.Coraggioso:BAAALgADCgYJBgAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAAEAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgYJCAAAAA==.Crettephal:BAEALgAECgUJEQAAAA==.Crodo:BAAALgADCgYJBgAAAA==.',
['Cä']='Cähira:BAAALgADCgcJCwABLgADCggJDwANAAAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAAALgAECggJDgAAAA==.Daisia:BAABLgAECn8aAAISAAgJrQYMKQBKAQASAAgJrQYMKQBKAQAAAA==.Dalarrong:BAAALgAECgIJAgAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAAALgAECgQJCQAAAA==.Deathstopper:BAAALgAECgEJAQAAAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8ZAAMEAAgJphGjbgBUAQAEAAcJwBCjbgBUAQAFAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8mAAIOAAgJQRjvDwDTAQAOAAgJQRjvDwDTAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Devour:BAAALgAECgcJDgAAAA==.Dezin:BAAALgAECgYJBgAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAFFAIJAgANAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8fAAITAAgJEQ+CNABQAQATAAgJEQ+CNABQAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgYJCwAAAA==.Draqula:BAAALgADCggJEgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8rAAIUAAgJGwx0hQBTAQAUAAgJGwx0hQBTAQAAAA==.',
Du='Dura:BAABLgAECn8vAAIVAAgJWBjlHwA4AgAVAAgJWBjlHwA4AgAAAA==.',
El='Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn85AAIFAAkJKwuwDQBJAQAFAAkJKwuwDQBJAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9EAAMGAAkJyg37TADKAQAGAAkJyg37TADKAQACAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgEJAwABLgAECgUJCwANAAAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgANAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQRAAgJtAydLABTAQARAAgJtAydLABTAQAWAAYJ2wnjLwAhAQAHAAUJYAq0TwCHAAAAAA==.Faith:BAABLgAECn8fAAIPAAYJlxyFZwCHAQAPAAYJlxyFZwCHAQAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgADCgkJEAABLgAECgkJLQAPACwbAA==.Firebug:BAABLgAECn8ZAAIOAAcJ5AU4KwDHAAAOAAcJ5AU4KwDHAAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgQJCwAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAUJGgAXALghAA==.',
Fu='Furnok:BAABLgAECn8zAAMTAAkJ1RFSHwDRAQATAAkJ1RFSHwDRAQAVAAYJ6Q1BbAD6AAAAAA==.Fuzzyshukk:BAAALgAECgQJCAAAAA==.',
Ga='Galethia:BAAALgADCgkJIQAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAYAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8OAAIZAAMJIQ6OIADJAAAZAAMJIQ6OIADJAAAuAAQKfzoAAxkACQm6FxIMABACABkACQm6FxIMABACABoABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAABLgAECn8dAAIJAAgJ6BrEGwARAgAJAAgJ6BrEGwARAgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgYJDgAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn85AAIYAAkJGxOxCwANAgAYAAkJGxOxCwANAgAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8aAAIPAAgJsxHYcABzAQAPAAgJsxHYcABzAQAAAA==.',
Ho='Hollet:BAABLgAECn8hAAIbAAYJMRBffQAuAQAbAAYJMRBffQAuAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8NAAIJAAUJAx3yDgCsAQAJAAUJAx3yDgCsAQAuAAQKfyUAAwkACQmRIqEFABIDAAkACQmRIqEFABIDAA8AAQlCB0qeAR8AAAAA.',
Hu='Huckk:BAAALgADCgcJCwAAAA==.',
Hy='Hylen:BAAALgAECggJEQAAAA==.',
Ib='Ibrandul:BAABLgAECn8qAAIPAAgJHBIiawB/AQAPAAgJHBIiawB/AQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIUAAcJ8wFM/ACPAAAUAAcJ8wFM/ACPAAAAAA==.',
Ir='Iroha:BAAALgADCgQJBgAAAA==.Ironhuntress:BAABLgAECn8bAAIbAAgJnhCKUACaAQAbAAgJnhCKUACaAQAAAA==.',
It='Ithro:BAABLgAECn8nAAIcAAkJJxgHBQAfAgAcAAkJJxgHBQAfAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJEwAAAA==.',
Ja='Jarlo:BAABLgAECn85AAIcAAkJIxjmAwBUAgAcAAkJIxjmAwBUAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQAPAMUaAA==.Jefficiently:BAAALgAECgYJBgABLgAECgkJLQAPAMUaAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJLQAPAMUaAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn8nAAIZAAkJ1CF0BAC8AgAZAAkJ1CF0BAC8AgAAAA==.',
Ju='Juanhunglow:BAAALgADCgkJNAAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn8tAAMGAAgJRyF5GgCWAgAGAAgJRyF5GgCWAgACAAEJ/w+qVwAoAAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn81AAIbAAcJUxR1ZgBhAQAbAAcJUxR1ZgBhAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Keruptadin:BAAALgAECgUJBgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ko='Kope:BAABLgAECn8rAAIYAAkJ/BqLBQCqAgAYAAkJ/BqLBQCqAgAAAA==.',
Kr='Kreltor:BAABLgAECn8nAAIVAAgJRiKACwDsAgAVAAgJRiKACwDsAgAAAA==.Kryptikz:BAAALgAECggJEAAAAA==.Krystoferson:BAABLgAECn8bAAIdAAgJPALFNADoAAAdAAgJPALFNADoAAAAAA==.',
La='Largar:BAAALgADCgUJCAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAgANAAAAAA==.Leianii:BAAALgAECgQJCQAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAIEAAcJ8QesgwBTAQAEAAcJ8QesgwBTAQAAAA==.Lillat:BAAALgAECgYJEQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgADCgkJCwAAAA==.Luuggork:BAAALgAECgEJAQAAAA==.',
Ly='Lyarith:BAAALgADCgUJBQAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJAgAAAA==.',
['Lì']='Lìesson:BAABLgAECn8mAAIPAAkJfiEqDwDXAgAPAAkJfiEqDwDXAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8HAAIUAAQJWhAZWAAiAQAUAAQJWhAZWAAiAQAuAAQKfxoAAhQACAlSFrVZALkBABQACAlSFrVZALkBAAEuAAUUAgkCAA0AAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn84AAIUAAkJ8xjiLgBIAgAUAAkJ8xjiLgBIAgAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgYJEAANAAAAAA==.Makkagg:BAACLgAFFH8RAAMOAAQJZBTdEQACAQAOAAQJZBTdEQACAQAaAAIJRAcTSQBCAAAuAAQKfzUAAw4ACQkiISMEANcCAA4ACQkiISMEANcCABoACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8hAAIUAAgJ6gcElQA1AQAUAAgJ6gcElQA1AQAAAA==.',
Me='Melarndra:BAAALgADCgYJBgAAAA==.',
Mi='Milagrosa:BAABLgAECn8jAAIXAAkJJQ1wLABwAQAXAAkJJQ1wLABwAQAAAA==.Mirael:BAACLgAFFH8LAAIbAAUJqxw4LQA6AQAbAAUJqxw4LQA6AQAuAAQKfy4AAhsACQkkIMAIAAcDABsACQkkIMAIAAcDAAAA.Mishuntsalot:BAAALgADCggJDwAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAABLgAECn8XAAIPAAYJwAjT1ADPAAAPAAYJwAjT1ADPAAAAAA==.',
Mu='Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8ZAAIKAAcJvg0QUwAyAQAKAAcJvg0QUwAyAQAAAA==.Mystryx:BAAALgAECggJEgAAAA==.',
['Mà']='Màck:BAAALgAFFAIJAgAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Naldor:BAAALgADCgkJCQAAAA==.Nargul:BAABLgAECn8kAAIEAAYJ2xelZwBkAQAEAAYJ2xelZwBkAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQAPAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAEAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8YAAIPAAcJigc6yADgAAAPAAcJigc6yADgAAAAAA==.',
Oa='Oathmere:BAAALgADCgcJCwAAAA==.',
Og='Ogrusao:BAABLgAECn8fAAIbAAgJeA3iUwCRAQAbAAgJeA3iUwCRAQAAAA==.Ogun:BAAALgADCgEJAgAAAA==.',
Pa='Panasaurus:BAABLgAECn85AAIeAAkJhBQrCADgAQAeAAkJhBQrCADgAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIQAAcJwBmCMgCHAQAQAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn8tAAIRAAgJYAgFNgAdAQARAAgJYAgFNgAdAQAAAA==.Pendraig:BAAALgAECgUJBQAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAAALgAECgkJCgAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJDgANAAAAAA==.Rayst:BAABLgAECn8bAAIUAAYJVQIx/QCNAAAUAAYJVQIx/QCNAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAABLgAECn8YAAIKAAgJ5CCkCwD1AgAKAAgJ5CCkCwD1AgABLgAFFAMJDAAKAGAVAA==.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8bAAIaAAgJIiEkDwBxAgAaAAgJIiEkDwBxAgAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn8sAAMSAAkJwxNuEQAUAgASAAkJXxNuEQAUAgAbAAEJ+hRvAAE/AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAfAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Sabba:BAAALgADCgYJBgAAAA==.Sagearian:BAAALgAECgQJBQAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn8ZAAMbAAYJawhpogDiAAAbAAYJXghpogDiAAASAAQJfAIFTgBfAAAAAA==.Samanda:BAABLgAECn8ZAAIgAAYJ0w55HgDyAAAgAAYJ0w55HgDyAAAAAA==.Samshir:BAABLgAECn8WAAIGAAcJvg25hwBCAQAGAAcJvg25hwBCAQAAAA==.',
Sc='Scorned:BAABLgAECn8mAAIMAAcJ4hAUcAApAQAMAAcJ4hAUcAApAQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seosinz:BAAALgAECgcJEwAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgMJAwAAAA==.Shaylinn:BAAALgADCgkJMAAAAA==.Shenanigan:BAAALgADCgEJAQABLgAECgkJLQAPACwbAA==.Shukkvoker:BAAALgADCgQJBQABLgAFFAUJDQAJAAMdAA==.',
Si='Siella:BAABLgAECn8vAAIHAAgJ+hOYHADMAQAHAAgJ+hOYHADMAQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgUJCwANAAAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8rAAIUAAgJfiHbGwCfAgAUAAgJfiHbGwCfAgAAAA==.Snowette:BAAALgADCgIJAgAAAA==.',
So='Solar:BAAALgAFFAEJAQAAAA==.Somenai:BAAALgAECgEJAQAAAA==.Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgADCgIJAgABLgAECgEJAQANAAAAAA==.Soulbaine:BAAALgAECgYJDwAAAA==.',
Sp='Spazeric:BAABLgAECn8fAAMIAAkJ3ha+IQDqAQAIAAgJcxW+IQDqAQAhAAcJKBbFLgA5AQAAAA==.Spheria:BAABLgAECn8zAAIEAAgJJQgDeQA+AQAEAAgJJQgDeQA+AQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJAwAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJAgAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECgYJCAANAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn8bAAIiAAYJpQaUGQDTAAAiAAYJpQaUGQDTAAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgADCgkJJgAAAA==.',
Ti='Tim:BAABLgAFFH8FAAIVAAMJ0RZhPgDRAAAVAAMJ0RZhPgDRAAAAAA==.Timeshadow:BAABLgAECn8cAAIdAAYJhwNiOgDGAAAdAAYJhwNiOgDGAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8oAAIUAAkJixdEPQAQAgAUAAkJixdEPQAQAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8XAAIPAAcJRxF3hwBHAQAPAAcJRxF3hwBHAQAAAA==.',
Tr='Triplesix:BAAALgAECggJEwAAAA==.Trittia:BAABLgAECn8lAAIaAAcJTA9VNgBcAQAaAAcJTA9VNgBcAQAAAA==.',
Tu='Tukk:BAABLgAECn8UAAIOAAcJ4hHaGwBCAQAOAAcJ4hHaGwBCAQAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAIKAAgJCBX5KwDpAQAKAAgJCBX5KwDpAQABLgAECgcJEQANAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgADCgcJCwABLgAECgQJBAANAAAAAA==.',
Ur='Urza:BAAALgAECgUJBwAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn81AAMbAAkJVR0lEgCsAgAbAAkJVR0lEgCsAgADAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgQJBAAAAA==.Vexxa:BAABLgAECn8YAAIMAAkJPBiWRgCdAQAMAAkJPBiWRgCdAQAAAA==.',
Vi='Viridania:BAAALgAECgUJBgAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgAECgYJBgANAAAAAA==.',
Wa='Walkz:BAAALgAECgYJEAABLgAECggJEAANAAAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn8zAAIRAAkJ9hxlCQCgAgARAAkJ9hxlCQCgAgAAAA==.Wiggleston:BAABLgAECn8bAAMJAAkJJgzZKQCsAQAJAAkJJgzZKQCsAQAPAAMJYwMxNQFbAAAAAA==.Willscarlet:BAAALgAECgYJDAAAAA==.',
Wy='Wylethia:BAAALgADCgcJCAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgcJFgAGAL4NAA==.',
Yf='Yffre:BAAALgADCgMJAwAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgADCgkJGAAAAA==.',
Za='Zarathia:BAAALgAECgYJDwAAAA==.Zaritym:BAABLgAECn8bAAMIAAgJhRkyGQAsAgAIAAgJhRkyGQAsAgAhAAQJbw/2XQCIAAAAAA==.Zarrilin:BAABLgAECn8oAAIUAAkJlBeJPQAPAgAUAAkJlBeJPQAPAgAAAA==.',
Ze='Zebop:BAAALgADCgkJDQAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8NAAIFAAUJ3g20BQAiAQAFAAUJ3g20BQAiAQAuAAQKf0UAAgUACQnNHGgCAIACAAUACQnNHGgCAIACAAAA.',
Zo='Zoeheals:BAAALgAECgYJCAAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCgAAAA==.Zulmahn:BAABLgAECn8fAAMVAAcJcBCpUABUAQAVAAcJcBCpUABUAQATAAYJJARwYgCkAAAAAA==.',
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
