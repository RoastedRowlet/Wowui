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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Feral','Hunter-Survival','Unknown-Unknown','Priest-Discipline','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Paladin-Holy','Mage-Frost','Mage-Arcane','Paladin-Retribution','Druid-Guardian','Warlock-Destruction','Paladin-Protection','Priest-Holy','Priest-Shadow','Warlock-Demonology','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Evoker-Preservation','Warrior-Arms','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Devourer','Evoker-Devastation','DeathKnight-Frost','Warlock-Affliction','Mage-Fire','Monk-Windwalker','Monk-Mistweaver','Warrior-Protection','DemonHunter-Vengeance','Evoker-Augmentation','Rogue-Outlaw','Monk-Brewmaster',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abashai:BAABNQAECn8WAAMBAAcKcBedHgDcAQABAAcKcBedHgDcAQACAAIKOAIUlABkAAAAAA==.',
Ae='Aellyria:BAAANQADCgEIAQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECggIGgADAJQaAA==.',
Ai='Ainsworth:BAEANQAECgMIAwABNQAECgcIIwAEALoPAA==.',
Ak='Akaili:BAAANQAECgYICQAAAA==.',
Al='Alexiya:BAABNQAECn8gAAIFAAgKHBK6EQDlAQAFAAgKHBK6EQDlAQAAAA==.Allacari:BAABNQAECn8XAAIGAAcKixWjCADCAQAGAAcKixWjCADCAQAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQADCgYICgABNQAECgQIBgAHAAAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQAECgIIAwAAAA==.',
Am='Amanda:BAABNQAECn8lAAIIAAgK6w87AQClAQAIAAgK6w87AQClAQAAAA==.Amonamarth:BAAANQAECgcIEgAAAA==.',
An='Anabelleigh:BAAANQABCggIEQAAAA==.Andrise:BAABNQAECn8jAAQJAAcKdBxTXgD0AQAJAAcKdBxTXgD0AQAKAAYKiBNTGwCvAQALAAUKyRgoigCLAQAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAABNQAECn8dAAMDAAcKGhjIRgD9AQADAAcKGhjIRgD9AQAMAAQKihGhnQCeAAAAAA==.',
Ap='Apol:BAABNQAECn8gAAINAAkKzw+2cwC8AQANAAkKzw+2cwC8AQAAAA==.',
Ar='Arachne:BAABNQAECn8vAAMOAAoKWxefBADdAgAOAAkK1xmfBADdAgAPAAgKbwv6YQD6AAAAAA==.Arafina:BAAANQABCgUICQABNQAECgoKKAANAFkNAA==.Arakar:BAABNQAECn8oAAINAAoKWQ1rZADrAQANAAoKWQ1rZADrAQAAAA==.Aralynne:BAAANQAECgcIDwAAAA==.Arcee:BAAANQADCgIIAgAAAA==.Arch:BAAANQAECgQICQAAAA==.Ardori:BAAANQAECgYICgABNQAECgoKHgAFAE8cAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwAHAAAAAA==.Armorya:BAABNQAECn80AAIQAAoK2Rz9BACkAgAQAAoK2Rz9BACkAgAAAA==.Armyofone:BAAANQAECgQICAAAAA==.Artaius:BAABNQAECn8dAAIRAAkKNiOQCADyAgARAAkKNiOQCADyAgAAAA==.Arthonius:BAAANQADCgQIBAAAAA==.Arthuun:BAAANQAECggIEAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggIDgABNQAECggIFAASAGsLAA==.Astarog:BAAANQAECgYIEAAAAA==.',
At='Atafloosy:BAEBNQAECn8dAAIJAAcK/h9KOwByAgAJAAcK/h9KOwByAgAAAA==.Athelf:BAABNQAECn8nAAIQAAoKKxoLBQCjAgAQAAoKKxoLBQCjAgAAAA==.Attina:BAAANQADCggICAAAAA==.',
Au='Aubriell:BAAANQAECgQICwAAAA==.',
Ay='Ayrnerdam:BAAANQAECgYICgAAAA==.',
Az='Azureas:BAAANQAECgEIAQAAAA==.',
Ba='Babelfish:BAABNQAECn8bAAITAAgKORakHgDzAQATAAgKORakHgDzAQAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAABNQAECn8eAAIBAAcK+wqYKQB4AQABAAcK+wqYKQB4AQAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAABNQAECn8qAAIRAAoK9AlZIgCEAQARAAoK9AlZIgCEAQAAAA==.Beastkael:BAAANQAECgUIBgAAAA==.Beg:BAABNQAECn8hAAIUAAkKBBCyXwACAgAUAAkKBBCyXwACAgAAAA==.Belfalas:BAAANQABCgQICAAAAA==.Beliir:BAAANQADCggICAABNQAECgcIJgATAIQeAA==.Berghain:BAAANQADCgQIAgAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAABNQAECn8cAAIUAAgKYBOKXQAJAgAUAAgKYBOKXQAJAgAAAA==.Beytryx:BAAANQAECgIJAwAAAA==.',
Bi='Bittycakes:BAAANQAECgIIAgAAAA==.',
Bl='Blackstar:BAAANQAECgIIAgAAAA==.Bladeoftruth:BAABNQAECn8gAAIMAAoK7R+lFwDwAgAMAAoK7R+lFwDwAgAAAA==.Blaize:BAAANQADCgYICQAAAA==.Blitzwing:BAAANQAECgUIBgAAAA==.Bloodyaggro:BAAANQAECgQIBwAAAA==.',
Bo='Bobapstab:BAAANQADCgIIAgAAAA==.Bodin:BAAANQADCgcIBwAAAA==.Bonnabelle:BAABNQAECn8pAAIUAAoKsQZceQCuAQAUAAoKsQZceQCuAQAAAA==.Boombawks:BAAANQAECgUIBgAAAA==.Bor:BAAANQAECgUIBwABNQAECgkJHQARADYjAA==.Bos:BAABNQAECn8dAAIVAAgKtxqSBQCjAQAVAAgKtxqSBQCjAQAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgcIGAAWAIIXAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECggIGgAXAHgZAA==.Briest:BAAANQAECgQIBAABNQAECggIGgAXAHgZAA==.Brownbar:BAAANQAECgYICQAAAA==.Bruid:BAABNQAECn8aAAMXAAgKeBnhJgDqAQAXAAcKzBfhJgDqAQAYAAcKvhI4TwCiAQAAAA==.Bruneigin:BAAANQAECgcIDgAAAA==.',
Ca='Cailey:BAAANQAECgIIBQAAAA==.Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwAHAAAAAA==.Cantliquor:BAAANQABCgQIBAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgQIAwAAAA==.Carrin:BAABNQAECn9DAAIQAAkKZCJHEAD5AQAQAAkKZCJHEAD5AQAAAA==.Castanza:BAAANQADCggICAAAAA==.Catalyia:BAABNQAECn8nAAIZAAkK4xfVTQCFAgAZAAkK4xfVTQCFAgAAAA==.Catris:BAAANQAECgQICQAAAA==.Catset:BAABNQAECn8aAAIYAAgK9wdnWwBlAQAYAAgK9wdnWwBlAQAAAA==.',
Ce='Cecea:BAAANQADCgEIAgAAAA==.',
Ch='Chaahk:BAAANQAECgQIBAABNQAECgkJHQARADYjAA==.Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECggIDAABNQAECgoKGwAaAKQLAA==.Chazzo:BAABNQAECn8fAAIbAAoKcBJ2SAAPAQAbAAoKcBJ2SAAPAQAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQAECgYIEQAAAA==.',
Co='Commy:BAABNQAECn8bAAMPAAgKXxAjzQDsAQAPAAgKXxAjzQDsAQAOAAEKng3nQgA+AAAAAA==.Concorde:BAAANQAECgUICQAAAA==.Copiousconns:BAABNQAECn8mAAISAAcKPQ5tJQBIAQASAAcKPQ5tJQBIAQAAAA==.Corlock:BAAANQADCgYIDAAAAA==.Cornholy:BAAANQADCgMIAwAAAA==.',
Cr='Craitos:BAAANQABCgYIDQAAAA==.Cranjis:BAAANQAECgYIBgAAAA==.Crimsonfury:BAAANQAECgUICgAAAA==.',
Cu='Cubos:BAABNQAECn8wAAMWAAoK6yFLAgDVAwAWAAoK6yFLAgDVAwASAAEKGCG9DQBkAAAAAA==.Cutlash:BAAANQAECgQIBgAAAA==.Cutslash:BAAANQAECgIIAgABNQAECgQIBgAHAAAAAA==.',
Cy='Cynaea:BAAANQADCgQJBAABNQAECgoKGwAaAKQLAA==.',
Da='Daemona:BAABNQAECn8jAAIcAAoKXhNUMwARAgAcAAoKXhNUMwARAgAAAA==.Daieniceis:BAABNQAECn8XAAIZAAcK7QOJ2gBLAQAZAAcK7QOJ2gBLAQAAAA==.Dalkurn:BAACNQAFFH8RAAIXAAYKOiLoAQBXAgAXAAYKOiLoAQBXAgA1AAQKfysAAhcACQrrI/wHAEQDABcACQrrI/wHAEQDAAAA.',
De='Decayy:BAACNQAFFH8LAAIMAAUKlRiMDgBrAQAMAAUKlRiMDgBrAQA1AAQKfyMAAgwACQqIImAWAPoCAAwACQqIImAWAPoCAAAA.Deceptakahn:BAABNQAECn8mAAIRAAgKsQUzNgD0AAARAAgKsQUzNgD0AAAAAA==.Derailedbeef:BAACNQAFFH8GAAMbAAIKmhSBFQBqAAAbAAIKywyBFQBqAAAdAAEKzh/qBABXAAA1AAQKfy4AAxsACgqTG0ZIALECABsACgp4G0ZIALECAB0ABArDGhQXAC0BAAAA.Deydoralia:BAABNQAECn86AAINAAoKLiBJDgBYAwANAAoKLiBJDgBYAwAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.Diô:BAAANQADCggICAAAAA==.',
Dl='Dlwlrma:BAAANQAECgYICwAAAA==.',
Dn='Dnme:BAABNQAECn8iAAIeAAoKkhHMKQD1AQAeAAoKkhHMKQD1AQAAAA==.',
Do='Doieha:BAAANQADCggIDwABNQAECgoKHgAFAE8cAA==.Doneldus:BAAANQAECgQICgAAAA==.Dool:BAAANQAECgQICwAAAA==.Dorfdragon:BAABNQAECn8gAAIfAAcKiAu2IABNAQAfAAcKiAu2IABNAQAAAA==.Dorfe:BAABNQAECn8vAAICAAgK5hSrBwChAQACAAgK5hSrBwChAQAAAA==.Dorflock:BAAANQADCggIFwAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgcIGQAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Drewgarymore:BAABNQAECn8tAAMYAAgK3xR0DQB0AQARAAcKDhcLHwCmAQAYAAgK/BF0DQB0AQAAAA==.Drough:BAAANQAECgQICQABNQAECgkJIgAbAMkNAA==.Drzeal:BAAANQADCgYIBgAAAA==.',
Du='Dumblêdorê:BAAANQADCgMIAwABNQAFFAYIDwAQAPEPAA==.Durandall:BAACNQAFFH8PAAIQAAYK8Q92CADDAQAQAAYK8Q92CADDAQA1AAQKfyQAAhAACgr6G8prAFoCABAACgr6G8prAFoCAAAA.Durleap:BAAANQAECgQICwAAAA==.Durthmaul:BAABNQAECn8XAAILAAcKNwYxJwAfAQALAAcKNwYxJwAfAQABNQAFFAYIDwAQAPEPAA==.',
Dw='Dwarflock:BAABNQAECn8bAAIWAAgKGhW5ZwAkAgAWAAgKGhW5ZwAkAgAAAA==.',
Dy='Dylpickl:BAABNQAECn8VAAIeAAkKUx3KCwAiAwAeAAkKUx3KCwAiAwAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAABNQAECn8WAAIgAAcK8wWeYQAeAQAgAAcK8wWeYQAeAQAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQAECgEIAQABNQAECgkJJwANAFsaAA==.Elow:BAAANQADCgIIAgAAAA==.Elyiet:BAAANQAECgQIBAAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAAANQAECgQICwAAAA==.Ess:BAAANQAECgQICQAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgYICQAHAAAAAA==.Evvie:BAAANQAECgcIEwAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAABNQAECn8dAAIQAAcKsxvefgAsAgAQAAcKsxvefgAsAgAAAA==.Falcondor:BAAANQADCgMIAwAAAA==.Fallin:BAAANQAECgUIBQAAAA==.Fantarius:BAACNQAFFH8NAAIUAAUKDhRvEACPAQAUAAUKDhRvEACPAQA1AAQKfy8AAxQACgqHIBEmANMCABQACgqHIBEmANMCAAgAAQqIBYouACgAAAAA.Fantazee:BAAANQADCgUIBQABNQAFFAUIDQAUAA4UAA==.Fatdono:BAAANQAECgYIEQAAAA==.',
Fi='Fibbs:BAABNQAECn8cAAIRAAcK7hxGEgA+AgARAAcK7hxGEgA+AgAAAA==.Fikti:BAABNQAECn8uAAMhAAkKAxrqBACDAgAhAAgKuxvqBACDAgAWAAYKJha+WwDKAAAAAA==.Firetongue:BAAANQADCgUIBQAAAA==.Firocios:BAABNQAECn8bAAINAAcKcxIngwCRAQANAAcKcxIngwCRAQAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.Flatiron:BAAANQADCgEIAQABNQAECgQICAAHAAAAAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAABNQAECn8ZAAIGAAYKhRFACQCoAQAGAAYKhRFACQCoAQABNQAECggIIQAGAP8UAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAAANQAECgQICAAAAA==.Frostyfella:BAACNQAFFH8QAAIPAAUK6R2oFwC7AQAPAAUK6R2oFwC7AQA1AAQKfzIAAg8ACgpfIHMaAGwDAA8ACgpfIHMaAGwDAAE1AAEKAggCAAcAAAAA.',
Fu='Furman:BAAANQADCgMIAwAAAA==.Fuzzycakes:BAAANQADCggICAAAAA==.',
['Fá']='Fáith:BAAANQAECgUIDgAAAA==.',
Ga='Garypotter:BAABNQAECn8sAAIeAAgKhyLGAgAbAgAeAAgKhyLGAgAbAgAAAA==.Gazooks:BAAANQADCgYIEwAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAABNQAECn8uAAIZAAgKpSIiHgAfAwAZAAgKpSIiHgAfAwAAAA==.Glâdiátor:BAAANQADCgMIAwAAAA==.',
Go='Goodbrew:BAAANQAECgcIDgAAAA==.',
Gr='Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIBgAAAA==.Grindelbald:BAABNQAECn8bAAMPAAkK0hL6kwBYAgAPAAkK0hL6kwBYAgAiAAIK4ghxCQByAAAAAA==.',
Gt='Gtfofupá:BAAANQAECgQICgAAAA==.',
Gu='Gushee:BAABNQAECn8fAAIdAAkKtBnRBgAuAQAdAAkKtBnRBgAuAQAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgIIAwAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Hae:BAAANQADCgIIAgAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgUIDAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Hanamari:BAACNQAFFH8OAAIjAAYKRAa8BwB0AQAjAAYKRAa8BwB0AQA1AAQKfyIAAyMACQrgFmkhACACACMACQrgFmkhACACACQAAQrrAR5WAB0AAAAA.Hanoe:BAAANQADCggICAAAAA==.Harakrron:BAAANQAECgIIAQAAAA==.Harleyquìnn:BAAANQAECgIIAQAAAA==.Harydresden:BAABNQAECn8YAAIPAAgKWwPrOwEpAQAPAAgKWwPrOwEpAQAAAA==.Hawkesmage:BAAANQAECgIIAgAAAA==.Hawkslayer:BAAANQAECgQICQAAAA==.Hazule:BAAANQAECgIIAwABNQAECggIGwAJAGwXAA==.',
He='Healadín:BAAANQADCggIEAAAAA==.Hedgelord:BAACNQAFFH8NAAIYAAUKUQ22EQBQAQAYAAUKUQ22EQBQAQA1AAQKfyMAAhgACgrOGU0pAIwCABgACgrOGU0pAIwCAAAA.Heyboyy:BAAANQAECgcIDAABNQAECgoKOQAZALEhAA==.',
Hi='Hisky:BAAANQAECgQIBgAAAA==.',
Ho='Hobe:BAABNQAECn8YAAIWAAcKsh/AXABBAgAWAAcKsh/AXABBAgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgkJHQAWADMVAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQAECgQICQAAAA==.Huntaredead:BAAANQAECgQIBgABNQAECgoKJQAWAL4hAA==.',
Ic='Icyblades:BAABNQAECn8bAAIDAAgKZwqmZwBzAQADAAgKZwqmZwBzAQAAAA==.',
Il='Ilidania:BAAANQAECgYICQAAAA==.Ilyna:BAABNQAECn8eAAIWAAcKgQpcsgBrAQAWAAcKgQpcsgBrAQAAAA==.',
Im='Immortalnut:BAABNQAECn8UAAIfAAcKjwhYIABSAQAfAAcKjwhYIABSAQAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.Ittyycakes:BAAANQADCgcIBwAAAA==.',
Ja='Jackypan:BAAANQADCgUIBQAAAA==.Jaedis:BAAANQAECgYICgAAAA==.Jaktar:BAABNQAECn8VAAIZAAkKXwjHjwDqAQAZAAkKXwjHjwDqAQAAAA==.Jane:BAAANQAECgIIAgAAAA==.Janet:BAABNQAECn8bAAIlAAkKrhA8FADiAQAlAAkKrhA8FADiAQAAAA==.Jani:BAAANQADCgQIBAABNQAECgkJGwAlAK4QAA==.Janiina:BAAANQADCgYIDQAAAA==.',
Je='Jeroung:BAAANQABCgQIAgABNQAECgkJHgAbALMNAA==.Jezak:BAAANQADCgIIAgABNQAECgQIBgAHAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQAECgQICwAAAA==.Joobs:BAABNQAECn8UAAISAAgKawveFADHAQASAAgKawveFADHAQAAAA==.Joosh:BAAANQAECgUIBQAAAA==.',
Js='Jslice:BAACNQAFFH8LAAIbAAUKmg/gFQB5AQAbAAUKmg/gFQB5AQA1AAQKfyEAAhsACQrHIOtGALUCABsACQrHIOtGALUCAAAA.',
Ju='Juda:BAAANQAECgUICAAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgEIAQAAAA==.',
Ka='Kaelys:BAABNQAECn8gAAMNAAYK3xGWLAAwAQANAAYK3xGWLAAwAQAQAAEKAAAV0wEdAAAAAA==.Kahliea:BAAANQAECgQICQAAAA==.Kaidance:BAAANQAECggICQAAAA==.Kaisaze:BAABNQAECn8YAAIgAAkK9wgkGgBDAQAgAAkK9wgkGgBDAQAAAA==.Kamiga:BAAANQAECgUIBQABNQAECgoKHgAFAE8cAA==.Kapachka:BAAANQAECgUIDQAAAA==.Karbide:BAAANQAECgIIAgAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQAECgQIBQAAAA==.Katmarie:BAAANQAECgIIAwAAAA==.Kazothor:BAAANQAECgQICQAAAA==.',
Ke='Kelborne:BAAANQAECgUIBwAAAA==.Keria:BAACNQAFFH8TAAIcAAcKsB4jAgCMAgAcAAcKsB4jAgCMAgA1AAQKfzkAAhwACgplJOMCAMYDABwACgplJOMCAMYDAAAA.Keyz:BAAANQAECgYICwAAAA==.',
Ki='Kibbwarrior:BAAANQAECgcIBwAAAA==.Kiretsu:BAABNQAECn8cAAMOAAkK0BBpGAA1AQAPAAgKlw7w4gDDAQAOAAUK/w9pGAA1AQAAAA==.',
Kn='Knowén:BAAANQADCgYIBgAAAA==.',
Ko='Koder:BAAANQADCgYIDAAAAA==.Kovus:BAAANQAECgcIEwAAAA==.',
Kr='Kragami:BAAANQAECgQICwAAAA==.Krelien:BAAANQAECgUICgAAAA==.Krispee:BAABNQAECn8UAAIQAAgKvgce1ABzAQAQAAgKvgce1ABzAQAAAA==.Kristanya:BAABNQAECn8uAAIaAAgKRAhTCAA+AQAaAAgKRAhTCAA+AQAAAA==.Kristina:BAEANQAECggICAAAAA==.',
Ks='Ks:BAAANQAECgQIBAAAAA==.',
Ku='Kulaidmage:BAABNQAECn8dAAIPAAgKORWHsgAeAgAPAAgKORWHsgAeAgAAAA==.Kurtcowbain:BAAANQAECgYIEgAAAA==.Kushies:BAAANQADCgUIBQAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAFFAUIDAALAOoDAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAABNQAECn80AAImAAoK1SJ6AQCSAwAmAAoK1SJ6AQCSAwAAAA==.Lamashtu:BAABNQAECn8hAAIVAAgKpBX3HgBFAgAVAAgKpBX3HgBFAgAAAA==.Lasciel:BAAANQADCgcIBwAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layli:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.',
Le='Leddy:BAABNQAECn8fAAMIAAkKLxfEBQBFAgAIAAgKeRfEBQBFAgAVAAYKChJ0DwAXAQAAAA==.Leiman:BAAANQABCgQIBQAAAA==.Lemmy:BAAANQAECgcIBwAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAAANQAECgYIEwAAAA==.',
Li='Lightninjack:BAAANQAECgEIAQAAAA==.Lightsworn:BAAANQADCgEIAQAAAA==.Lilifa:BAABNQAECn8hAAIkAAcKiiHJDgCWAgAkAAcKiiHJDgCWAgAAAA==.Lilillidari:BAABNQAECn8eAAIcAAkKPByhHQCsAgAcAAkKPByhHQCsAgABNQAFFAcIGgAgAHUZAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFH8aAAQgAAcKdRkmAwAZAQADAAUKABn6BgCsAQAgAAQKmBgmAwAZAQAMAAEKAAAJOQAgAAA1AAQKfzwAAyAACgo2JaUKAEUDACAACgqsI6UKAEUDAAMACQoLIDcSACYDAAAA.Lilunholy:BAABNQAECn8UAAIDAAgK4xrNNQBRAgADAAgK4xrNNQBRAgABNQAFFAcIGgAgAHUZAA==.Linali:BAAANQAECgIIAgAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Lisey:BAAANQAECgEIAgAAAA==.Listari:BAAANQADCgQIBAAAAA==.Lisyao:BAAANQAECggIDwAAAA==.Littany:BAABNQAECn8gAAMNAAoKrws+aQDbAQANAAoKrws+aQDbAQAQAAcKUA4eygCHAQAAAA==.Livane:BAAANQAECgMIBQAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Looneytoones:BAAANQAECgUIBQAAAA==.Loralia:BAAANQADCggICAAAAA==.Lowground:BAAANQAECgEIAQAAAA==.',
Lu='Lucïna:BAABNQAECn8bAAIcAAcKYA3tSQB9AQAcAAcKYA3tSQB9AQAAAA==.Ludk:BAABNQAECn8uAAIMAAgKjiKpBAANAgAMAAgKjiKpBAANAgAAAA==.Luk:BAABNQAECn85AAMeAAoKaxWvKQD2AQAeAAoKaxWvKQD2AQAmAAUKqxKZGQAaAQABNQAECgoKHAAQAL8SAA==.Lumiela:BAAANQAECgUICQAAAA==.Luminah:BAAANQAECgIJAgAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQAECgEIAQAAAA==.Lunì:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Luxshot:BAAANQADCggIEAAAAA==.',
['Lê']='Lêxie:BAAANQADCgcIBwAAAA==.',
['Ló']='Lóner:BAABNQAECn8rAAMCAAoK3A2NLAA1AgACAAoKxg2NLAA1AgABAAUKOA3FHAD+AAAAAA==.',
['Lü']='Lüni:BAAANQADCgMIAwABNQAECgEIAQAHAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgQIBQAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECn8lAAIbAAoKxRBGUQD6AAAbAAoKxRBGUQD6AAAAAA==.Magicg:BAACNQAFFH8GAAIVAAUKuQWwCgBLAQAVAAUKuQWwCgBLAQA1AAQKfx8AAxUACQpdG5MVALMCABUACQpdG5MVALMCABQAAQqmCqD4ADwAAAAA.Magordito:BAABNQAECn8bAAIPAAgK3gfD8gClAQAPAAgK3gfD8gClAQABNQAECgoKKwACANwNAA==.Mairek:BAACNQAFFH8KAAIPAAUKmgwQEgDLAAAPAAUKmgwQEgDLAAA1AAQKfzcAAg8ACgoxHBVGAPcCAA8ACgoxHBVGAPcCAAAA.Maleigoron:BAABNQAECn8aAAIWAAkK1QnMjgDCAQAWAAkK1QnMjgDCAQAAAA==.Malkuri:BAABNQAECn8oAAMEAAkKixewKgD2AQAZAAgKMhfkgAALAgAEAAgKlxGwKgD2AQAAAA==.Malorysera:BAACNQAFFH8OAAMnAAQKliGrAwCYAAAnAAMK5xSrAwCYAAAfAAIK7SFUAwBiAAA1AAQKfyoABCcACgrSH8sBAHIBAB8ACQp2Hc4IAOkCABoABgpZF6AkAJ0BACcABAptHcsBAHIBAAAA.Marolt:BAAANQADCgMIAwABNQAECgoKHgAFAE8cAA==.Martrion:BAAANQABCgUIBQAAAA==.Matsuma:BAAANQAECgYICgAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAABNQAECn8WAAISAAcKOQdvJgBCAQASAAcKOQdvJgBCAQAAAA==.Menirva:BAABNQAECn8UAAIPAAgKYwrq5QC+AQAPAAgKYwrq5QC+AQABNQAECgkJKAAEAIsXAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAABNQAECn8VAAITAAgK+BJyKgCJAQATAAgK+BJyKgCJAQABNQAFFAUIDAALAOoDAA==.Metasham:BAACNQAFFH8MAAILAAUK6gPcEgBDAQALAAUK6gPcEgBDAQA1AAQKfzIAAgsACgptGp8mAOkCAAsACgptGp8mAOkCAAAA.',
Mi='Miiaa:BAABNQAECn8VAAMQAAgK7xy+dwA9AgAQAAcK5R++dwA9AgATAAEKIw5ZbgA1AAAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQAECgEIAgAAAA==.',
Mo='Moirasha:BAABNQAECn8YAAQWAAcKmQp8sABvAQAWAAcKmQp8sABvAQASAAIKRgLkeAA1AAAhAAEKAAB8MQAyAAAAAA==.Monkeydluffy:BAAANQAECgEIAQAAAA==.Monran:BAABNQAECn8YAAIKAAcKyAz+CwA4AQAKAAcKyAz+CwA4AQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgQIBgAAAA==.Morphingtime:BAABNQAECn8bAAQFAAcKWBmvGABxAQAYAAcK6hP6UQCUAQAFAAUKDBuvGABxAQAXAAUKwhXfPAA7AQAAAA==.Mortivus:BAAANQAECgcIEwAAAA==.',
Mu='Mudsworn:BAAANQAECgIIAgAAAA==.Muggs:BAAANQADCggIDgAAAA==.Mulvane:BAAANQAECgcIEwAAAA==.Mustachio:BAABNQAECn8cAAIPAAcKQxtbrAApAgAPAAcKQxtbrAApAgAAAA==.',
Mw='Mwc:BAACNQAFFH8MAAMBAAYKQhbhBgCjAQABAAUK5hHhBgCjAQACAAIKVCPVFQCcAAA1AAQKfxYAAwEACQqDJEkFADYDAAEACQqDJEkFADYDAAIABAp3FshpAAoBAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Nashia:BAAANQADCgMIAwAAAA==.Nazureshal:BAAANQADCggICAABNQAECgUIDQAHAAAAAA==.',
Ne='Neall:BAABNQAECn8YAAIlAAcKughWIgA4AQAlAAcKughWIgA4AQAAAA==.Negaryu:BAAANQAECgUICQAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nethryx:BAAANQADCgMIAwAAAA==.Nevets:BAAANQAECgYIEgAAAA==.',
Ni='Nightbird:BAAANQAECgMIAwAAAA==.Nightheals:BAAANQADCgYIBgABNQAECgcIIwAJAHQcAA==.',
No='Nonna:BAABNQAECn8uAAILAAgKHQlDNADvAAALAAgKHQlDNADvAAAAAA==.Noslrac:BAAANQAECgYIDQAAAA==.Notamonk:BAAANQAECgQIBQAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggINwAAAQ==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECn83AAIPAAoK4yM4CwCpAwAPAAoK4yM4CwCpAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAABNQAECn8ZAAIgAAgKlA+aTACFAQAgAAgKlA+aTACFAQAAAA==.',
Om='Omneg:BAAANQAECgQIBAAAAA==.',
On='Onlydks:BAABNQAECn8ZAAQgAAkK3g2sRwCfAQAgAAkK3g2sRwCfAQADAAMKjAtktACHAAAMAAEKAAA83QAhAAABNQAFFAQICgAdANwMAA==.Onlyslams:BAACNQAFFH8KAAMdAAQK3AxiAQAyAQAdAAQK3AxiAQAyAQAbAAIKggWOOABaAAA1AAQKfyUAAx0ACQpDHyoFANUCAB0ACQqNHSoFANUCABsABwpiGDOqALMBAAAA.Onlytrolling:BAAANQAECgQIBAAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orbaz:BAAANQADCgcIBgABNQAECggIFQAjAJ4MAA==.Orter:BAABNQAECn8aAAIDAAgKlBqnPAAuAgADAAgKlBqnPAAuAgAAAA==.',
Ot='Ottan:BAAANQADCgYICwAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.Ovo:BAAANQADCgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcICAAAAA==.Papsfear:BAABNQAECn8YAAIWAAcKghdBfgDrAQAWAAcKghdBfgDrAQAAAA==.Parceh:BAABNQAECn8nAAMJAAgKGx/kOgBzAgAJAAgKGx/kOgBzAgALAAgK4CJ6CADeAQAAAA==.',
Ph='Phydaux:BAAANQAECgMIBwAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgYIDQAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBQAHAAAAAA==.Prosciutto:BAABNQAECn8kAAMVAAoK/RcqFADEAgAVAAoK/RcqFADEAgAIAAEKbwdICwAyAAAAAA==.Proxima:BAAANQAECgEIAQAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAACNQAFFH8KAAIUAAQK7wMdGwASAQAUAAQK7wMdGwASAQA1AAQKfykAAxQACQp3DXByAMUBABQACQp3DXByAMUBAAgAAQq8AS4xACIAAAAA.Punn:BAAANQAECgcIDAABNQAECgoKJQAWAL4hAA==.Punnisher:BAABNQAECn8lAAMWAAoKviGOGgAcAwAWAAoKviGOGgAcAwASAAEKvhunbQBDAAAAAA==.Pureflow:BAABNQAECn8UAAIPAAgKpxqDhQBzAgAPAAgKpxqDhQBzAgAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAABNQAECn8WAAIbAAgKsRMOpgC+AQAbAAgKsRMOpgC+AQAAAA==.Quicks:BAABNQAECn8oAAIQAAoKGxtFUQChAgAQAAoKGxtFUQChAgAAAA==.Quáckys:BAAANQAECggICQAAAA==.',
Ra='Radünz:BAAANQABCgQIBwABNQAECgkJLwAFABkcAA==.Raelianna:BAAANQAECgQIDAABNQAECgoKNgAPAKojAA==.Raewyna:BAABNQAECn8XAAIZAAcKlwogvQCJAQAZAAcKlwogvQCJAQAAAA==.Rahruhai:BAABNQAECn8eAAQFAAoKTxziBwDeAgAFAAkK5h3iBwDeAgAXAAcKfR4SAwB6AgAYAAYKyhVDWwBlAQAAAA==.Rain:BAAANQAECgQIBwAAAA==.Raine:BAABNQAECn8YAAMLAAkKiBibbQDXAQALAAcK+hWbbQDXAQAJAAcKgh1EZwDXAQAAAA==.Rainingblood:BAABNQAECn8aAAIQAAgKsAWA/AAmAQAQAAgKsAWA/AAmAQAAAA==.Rainjar:BAABNQAECn8YAAIkAAgKDiJ/DAC7AgAkAAgKDiJ/DAC7AgAAAA==.Rancîd:BAABNQAECn8eAAQDAAgKYRKHWwChAQADAAgKYRKHWwChAQAMAAUKtwishgDjAAAgAAMKtAdRjwB7AAABNQAECgkJIgAbAMkNAA==.Raneeh:BAAANQABCgQIBAAAAA==.Ranron:BAABNQAECn8iAAMbAAkKyQ3BSAAOAQAbAAgKqwvBSAAOAQAlAAcKJQyPEAC3AAAAAA==.Raphael:BAABNQAECn8gAAMDAAgKJhUPXgCXAQADAAgKqhEPXgCXAQAMAAUK2hhnXQB8AQAAAA==.Rasik:BAABNQAECn8uAAIbAAgKmh3RFwCoAQAbAAgKmh3RFwCoAQAAAA==.Ravenblood:BAAANQAECgUICQAAAA==.Rayel:BAABNQAECn8aAAIUAAcKnx6CDgAJAgAUAAcKnx6CDgAJAgAAAA==.Raylyn:BAAANQAECgMIBQAAAA==.Raymotgus:BAAANQADCgEIAQAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQAECgEIAgAAAA==.Rhodrage:BAAANQADCgEIAQAAAA==.Rhome:BAABNQAECn8rAAMUAAkKSiQ2BQCfAwAUAAkKSiQ2BQCfAwAIAAEKABhNCQBJAAAAAA==.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAABNQAECn8nAAIUAAkKgBCnbgDSAQAUAAkKgBCnbgDSAQAAAA==.Ribald:BAAANQAECgUICQAAAA==.Rickgrimes:BAABNQAECn8zAAMgAAkKhSPtDwARAwAgAAgKTSHtDwARAwADAAgKRiD/KACVAgAAAA==.Risandra:BAAANQAECgcICQAAAA==.',
Ro='Roid:BAABNQAECn8gAAMNAAkKLw6aXAACAgANAAkKLw6aXAACAgAQAAIKawKZlgE9AAAAAA==.Rolph:BAAANQABCgUIBgABNQAECgkJHgAbALMNAA==.Rotcorpse:BAAANQAECggIDwAAAA==.',
Ru='Ruddam:BAAANQAECgQICwAAAA==.',
['Rä']='Räveñz:BAABNQAECn8lAAIRAAgKrRKNGwDHAQARAAgKrRKNGwDHAQAAAA==.',
Sa='Saintabes:BAACNQAFFH8SAAIUAAUK4BuSDQC0AQAUAAUK4BuSDQC0AQA1AAQKfyEAAhQACgrqH/I8AHYCABQACgrqH/I8AHYCAAAA.Saitame:BAAANQADCggICAAAAA==.Sakurah:BAABNQAECn8gAAMJAAkK4hmLVAAVAgAJAAkK4hmLVAAVAgALAAIKnQJRnQAjAAAAAA==.Samelan:BAAANQADCgUIBgAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanerinn:BAAANQAECgQIBAAAAA==.Sanicor:BAAANQAECgQIBAAAAA==.Sanrinn:BAABNQAECn8bAAIZAAgKOhd3FADPAQAZAAgKOhd3FADPAQAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAACNQAFFH8RAAIPAAUKAw09IwBtAQAPAAUKAw09IwBtAQA1AAQKfygAAg8ACgqLEzKJAGwCAA8ACgqLEzKJAGwCAAAA.Sarahjupiter:BAAANQAECgcIDQABNQAFFAUIEQAPAAMNAA==.Sargarach:BAAANQADCgEIAQAAAA==.Sarrin:BAAANQADCgQIBAABNQAECggILQAcAFcaAA==.',
Sc='Scapegoat:BAEANQAECgcIJgAAAQ==.Scraime:BAAANQAECgQIBQAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seger:BAAANQAECgMIAwAAAA==.Seilah:BAABNQAECn8ZAAIXAAcKniP5EADNAgAXAAcKniP5EADNAgAAAA==.Seliah:BAAANQAECgUIDQAAAA==.Senuya:BAAANQADCggICAABNQAECgkJHgAbALMNAA==.Seräph:BAABNQAECn8VAAILAAYKBBP5MwDwAAALAAYKBBP5MwDwAAAAAA==.',
Sh='Shadowglade:BAABNQAECn8vAAIYAAgKZBjlFgAnAQAYAAgKZBjlFgAnAQAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAAANQAECgQICQAAAA==.Shamizzle:BAABNQAECn8ZAAILAAkKlxEkYAABAgALAAkKlxEkYAABAgAAAA==.Shammydavis:BAABNQAECn8eAAIJAAgKWxxlRwBEAgAJAAgKWxxlRwBEAgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shiroikami:BAAANQADCgcICQABNQADCgIIAgAHAAAAAA==.Shocknorris:BAAANQADCgYIBgAAAA==.Shrapnel:BAABNQAECn8ZAAIZAAcKlATs7AAoAQAZAAcKlATs7AAoAQAAAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAABNQAECn8gAAIcAAgKJA02PwDCAQAcAAgKJA02PwDCAQAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.',
Sk='Skullchopper:BAAANQAECgMIAwABNQAECgcIJwAeAL4QAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAABNQAECn8jAAQSAAgKNR/4BgC0AAAWAAUKvRxCjADIAQASAAIKNCH4BgC0AAAhAAIKsx5KCACoAAAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAABNQAECn8uAAIoAAgK7wNoBADFAAAoAAgK7wNoBADFAAAAAA==.',
So='Solarica:BAAANQAECgMIAwAAAA==.Solciopath:BAAANQADCgUIBwAAAA==.Solómon:BAAANQAECgQIBQAAAA==.Sorabjr:BAAANQAECgQICQAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwAHAAAAAA==.Soulbreaker:BAABNQAECn8nAAIeAAcKvhB3NACfAQAeAAcKvhB3NACfAQAAAA==.Southy:BAAANQAECgYIEgAAAA==.',
Sp='Sparxs:BAAANQAECgUICQAAAA==.Spookz:BAAANQAECgEIAQAAAA==.',
St='Starblunder:BAAANQAECgIIAgAAAA==.Storglen:BAAANQADCgUIBQAAAA==.Stormdeth:BAAANQADCgUICAAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgAHAAAAAA==.Stylemonk:BAACNQAFFH8YAAIjAAcKuiUEAgB7AgAjAAcKuiUEAgB7AgA1AAQKfzAAAiMACgpVIjQBAKUCACMACgpVIjQBAKUCAAAA.',
Su='Sulfalloway:BAAANQAECggIEAAAAA==.Sumawfulot:BAABNQAECn8bAAIbAAgKjRs+ZABiAgAbAAgKjRs+ZABiAgAAAA==.Sunsparrow:BAAANQAECgQIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcICQAAAA==.Sweetheal:BAAANQADCgUIBQAAAA==.Swiftysarah:BAAANQADCggICAABNQAFFAUIEQAPAAMNAA==.',
Sy='Syraelia:BAAANQADCggICAAAAA==.Syvarris:BAABNQAECn8wAAQGAAoKeR8zAQDdAQAGAAkKxB8zAQDdAQAEAAUKWQjTTwDtAAAZAAEKah0uRAFXAAAAAA==.',
['Sî']='Sîpher:BAAANQAECgUIBAABNQAECgYIFQALAAQTAA==.',
Ta='Taeveren:BAAANQAECgcIBgAAAA==.Tamesßond:BAAANQAECgQICwAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQAECgUIBQAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAABNQAECn8mAAITAAcKhB6QFQBUAgATAAcKhB6QFQBUAgAAAA==.',
Te='Teacher:BAAANQAECgYIBgAAAA==.Teagan:BAAANQADCgYIEwAAAA==.Teagn:BAAANQABCgUIBgAAAA==.Teloran:BAAANQAECgIIAgAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEBNQAECn8jAAMEAAcKug/KOQCCAQAEAAcKug/KOQCCAQAGAAEKBgy9EwAyAAAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thelle:BAAANQAECgYICwABNQAFFAcIEwAcALAeAA==.Thewhitelion:BAAANQAECgQICQAAAA==.',
Ti='Tigg:BAACNQAFFH8OAAMgAAYKTBDvBADEAQAgAAYKTBDvBADEAQAMAAEKAAAXPwAVAAA1AAQKfysAAyAACgoZIVsYAMcCACAACgoZIVsYAMcCAAMAAQoAAOTYAD0AAAAA.Tikifiki:BAAANQAECgYIEAAAAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIIAgABNQAECgkJIgAbAMkNAA==.Toshidot:BAACNQAFFH8QAAIWAAYKLxIMCgDJAQAWAAYKLxIMCgDJAQA1AAQKfyoAAhYACQqFIWEfAAcDABYACQqFIWEfAAcDAAAA.Totemtila:BAAANQAECgMIBQABNQAECgoKJQAWAH8jAA==.Totendead:BAAANQABCgMIBQAAAA==.',
Tr='Translucent:BAABNQAECn8vAAIJAAkKhg5fNAASAQAJAAkKhg5fNAASAQAAAA==.Trazatra:BAABNQAECn8bAAMaAAoKpAuqKgBYAQAaAAgKYAqqKgBYAQAfAAYKLQ8dIwAtAQAAAA==.Truckah:BAABNQAECn8eAAIbAAkKsw1FGwCYAQAbAAkKsw1FGwCYAQAAAA==.Tràvdog:BAABNQAECn8UAAIbAAgKTRDsmQDbAQAbAAgKTRDsmQDbAQAAAA==.',
Tu='Tunalongarms:BAAANQAECgQICAABNQAECgYICQAHAAAAAA==.Tuonadari:BAAANQADCgUIDQAAAA==.Tuonai:BAABNQAECn8ZAAMjAAcKaQ1rOwA5AQAjAAcKaQ1rOwA5AQApAAMK/AH1LABWAAAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.Tustone:BAAANQADCgcICwAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQAECgIIAgAAAA==.',
Ul='Ularin:BAAANQAECgQIBAAAAA==.Ultimatum:BAAANQAECgUIDwAAAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwAHAAAAAA==.Vaelena:BAAANQADCgUIBQAAAA==.Vahla:BAAANQAECgEIAQABNQAECggILQAcAFcaAA==.Vailyt:BAAANQAECgQIBAAAAA==.Valkuridk:BAACNQAFFH8YAAMgAAYKqCYaAQCCAgAgAAYKgSYaAQCCAgADAAUKJSYKAwARAgA1AAQKfysAAyAACgr0JI8DAKoDACAACgrjJI8DAKoDAAMACArtJRglAKsCAAAA.Valorlight:BAAANQADCggICAAAAA==.Vandellor:BAAANQADCgQIBAABNQAECgkJHQARADYjAA==.Vandy:BAABNQAECn8gAAMUAAkK4xYFSwBEAgAUAAkKARUFSwBEAgAIAAQKqRbGEgD7AAAAAA==.',
Ve='Vedo:BAACNQAFFH8OAAIEAAUKRxGdBQDcAAAEAAUKRxGdBQDcAAA1AAQKfx0AAgQACgq3GfUUALYCAAQACgq3GfUUALYCAAAA.Vedora:BAABNQAECn8ZAAIVAAgKmBBpLADDAQAVAAgKmBBpLADDAQAAAA==.Velf:BAAANQADCgEIAQAAAA==.Veradis:BAAANQADCgYIEgAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virelith:BAAANQAECgEIAgAAAA==.Virulent:BAAANQAECgEIAQABNQAECggIHQAVALcaAA==.Vissarion:BAAANQAECgIIAgAAAA==.',
Vl='Vladak:BAAANQAECgcIDgAAAA==.',
Vo='Voc:BAAANQAECggIEgAAAA==.Voz:BAAANQAECgIIAgABNQAECggIHQAVALcaAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAABNQAECn8qAAIZAAoK5SBXEgBXAwAZAAoK5SBXEgBXAwAAAA==.',
Vy='Vyridiondk:BAAANQAECgQIBwAAAA==.Vyx:BAAANQAECgQICQAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Wallbeef:BAAANQAECgIIAgAAAA==.Waymán:BAAANQAECgIIAgAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Weelilcurse:BAAANQADCggIDgAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wh='Whuh:BAAANQAECgUIBQAAAA==.',
Wu='Wumply:BAACNQAFFH8OAAIVAAUKyQpYCQBuAQAVAAUKyQpYCQBuAQA1AAQKfyMAAhUACQqAFCohAC4CABUACQqAFCohAC4CAAAA.',
['Wà']='Wàyman:BAAANQAECgMIBQAAAA==.',
['Wä']='Wäyman:BAABNQAECn8tAAIKAAgK7BW3BQChAQAKAAgK7BW3BQChAQAAAA==.',
Xa='Xaranthia:BAABNQAECn8UAAIcAAkKOAmhQQCzAQAcAAkKOAmhQQCzAQAAAA==.',
Xe='Xenra:BAAANQAECgEIAQAAAA==.',
Xm='Xmcdizzle:BAABNQAECn8cAAIPAAcKQhjMxgD3AQAPAAcKQhjMxgD3AQAAAA==.',
Xy='Xylarra:BAABNQAECn8tAAMcAAgKVxoVEABrAQAcAAgKVxoVEABrAQAeAAIK/BcdXwB1AAAAAA==.',
Ya='Yautja:BAABNQAECn8qAAIEAAkKGhO6EgDwAAAEAAkKGhO6EgDwAAAAAA==.Yazule:BAABNQAECn8bAAIJAAgKbBfYVgANAgAJAAgKbBfYVgANAgAAAA==.',
Yo='Yodawg:BAABNQAECn8dAAIMAAgKOhdNPgAIAgAMAAgKOhdNPgAIAgAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgYIEAAHAAAAAA==.',
Yu='Yuenna:BAAANQADCggICAABNQAECgoKHgAFAE8cAA==.',
Za='Zairroth:BAAANQADCgYIBwAAAA==.Zamali:BAABNQAECn8hAAIMAAgKLAueYgBnAQAMAAgKLAueYgBnAQAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQAHAAAAAA==.Zartella:BAAANQAECgUICAABNQAECgYICwAHAAAAAA==.Zaxon:BAAANQAECgMIBQAAAA==.',
Ze='Zendraza:BAABNQAECn8aAAIfAAgKvQOLJwD2AAAfAAgKvQOLJwD2AAAAAA==.Zephyrion:BAACNQAFFH8QAAIMAAQKJRDcCQC1AAAMAAQKJRDcCQC1AAA1AAQKfzEAAgwACgooGIIhAKgCAAwACgooGIIhAKgCAAE1AAQKBwgUABMAqg4A.Zepplin:BAABNQAECn8WAAIGAAkK2Q/0BgAaAgAGAAkK2Q/0BgAaAgAAAA==.Zerenity:BAAANQAECgQIBgAAAA==.Zetro:BAABNQAECn82AAITAAoK1Qo4CgBWAQATAAoK1Qo4CgBWAQAAAA==.',
Zr='Zreydyn:BAAANQADCgcIFQAAAA==.',
Zu='Zuma:BAABNQAECn8nAAIOAAgKwBZZAwCSAQAOAAgKwBZZAwCSAQAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
