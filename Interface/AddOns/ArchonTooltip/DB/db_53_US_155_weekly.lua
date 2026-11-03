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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Hunter-Survival','Priest-Discipline','DeathKnight-Blood','Shaman-Enhancement','Paladin-Holy','Mage-Frost','Mage-Arcane','Evoker-Devastation','Druid-Restoration','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Druid-Guardian','Warlock-Destruction','Evoker-Preservation','Priest-Holy','Priest-Shadow','Warlock-Demonology','Druid-Balance','Hunter-BeastMastery','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Warrior-Fury','Warrior-Protection','DeathKnight-Frost','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Mage-Fire','Monk-Mistweaver','DemonHunter-Vengeance','Evoker-Augmentation','Rogue-Outlaw',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abashai:BAABNQAECn8gAAMBAAoK6RnsNwDbAQABAAoK6RnsNwDbAQACAAIKOAIUlABkAAAAAA==.',
Ae='Aellyria:BAAANQAECgcICQAAAA==.Aerrikon:BAAANQAECgEIAQABNQAECgkJIAADAFkbAA==.',
Ai='Ainsworth:BAEANQAECgMIAwABNQAECgkJKAAEACoOAA==.',
Ak='Akaili:BAABNQAECn8eAAMFAAoKORLwMwAcAgAFAAoKORLwMwAcAgAGAAEKAAAVXAEeAAAAAA==.',
Al='Alexiya:BAABNQAECn8gAAIHAAgKHBK6EQDlAQAHAAgKHBK6EQDlAQAAAA==.Allacari:BAABNQAECn8eAAIIAAcK6RVbBgCYAQAIAAcK6RVbBgCYAQAAAA==.Allumer:BAAANQAECgEIAQAAAA==.Alodir:BAAANQAECgcIBQAAAA==.Alstadin:BAAANQADCgMJAwAAAA==.Alucardd:BAAANQAECgIIAwAAAA==.',
Am='Amanda:BAABNQAECn80AAIJAAoKlREFAwAnAgAJAAoKlREFAwAnAgAAAA==.Amonamarth:BAABNQAECn8bAAIKAAoK1wkWUgDNAAAKAAoK1wkWUgDNAAAAAA==.',
An='Anabelleigh:BAAANQABCggIEQAAAA==.Andrise:BAABNQAECn8mAAQFAAcKdBxTXgD0AQAFAAcKdBxTXgD0AQALAAcKRBdTGwCvAQAGAAUKyRgoigCLAQAAAA==.Annathesia:BAAANQADCgEIAQAAAA==.Antibear:BAABNQAECn8jAAMDAAkKBRXIRgD9AQADAAkKBRXIRgD9AQAKAAQKihGhnQCeAAAAAA==.',
Ap='Apol:BAABNQAECn8oAAIMAAkKvxAbUQCcAQAMAAkKvxAbUQCcAQAAAA==.',
Ar='Arachne:BAABNQAECn8zAAMNAAoKQxmfBADdAgANAAkK1xmfBADdAgAOAAkKAg5BpgAsAQAAAA==.Arafina:BAAANQABCgUICQABNQAECgoKOwAMAEURAA==.Arakar:BAABNQAECn87AAIMAAoKRRHZMQAlAgAMAAoKRRHZMQAlAgAAAA==.Aralynne:BAAANQAECgcIDwAAAA==.Arcee:BAAANQADCgIIAgAAAA==.Arch:BAABNQAECn8WAAIPAAUKLgvXJwDzAAAPAAUKLgvXJwDzAAAAAA==.Ardori:BAAANQAECgYICgABNQAECgoKLAAQAPcdAA==.Arlïnn:BAAANQAECgQIBgABNQAECgcICwARAAAAAA==.Armorya:BAABNQAECn9CAAMSAAoKVR5YMgBtAgASAAoKVR5YMgBtAgATAAEKdwnFXQAqAAAAAA==.Armyofone:BAAANQAECgQICAAAAA==.Artaius:BAABNQAECn8iAAIUAAoKcyWQCADyAgAUAAoKcyWQCADyAgAAAA==.Arthonius:BAAANQADCgQIBAAAAA==.Arthuun:BAAANQAECggIEAAAAA==.Artom:BAAANQADCgUJBQAAAA==.',
As='Ashaw:BAAANQADCgYIBgAAAA==.Astariel:BAAANQADCggIDgABNQAECgkJFwAVABgMAA==.Astarog:BAABNQAECn8XAAMWAAcKUgzxFQBTAQAWAAcKUgzxFQBTAQAPAAIKDgXqOABHAAAAAA==.',
At='Atafloosy:BAEBNQAECn8jAAIFAAkK4R9KOwByAgAFAAkK4R9KOwByAgAAAA==.Athelf:BAABNQAECn80AAISAAoK8h8rHwDFAgASAAoK8h8rHwDFAgAAAA==.Athelfstein:BAAANQAECggICAAAAA==.Attina:BAAANQADCggICAAAAA==.',
Au='Aubriell:BAAANQAECgcIDwAAAA==.',
Ay='Ayrnerdam:BAAANQAECgYIDgAAAA==.',
Az='Azureas:BAAANQAECgEIAQAAAA==.',
Ba='Babelfish:BAABNQAECn8dAAITAAgKORakHgDzAQATAAgKORakHgDzAQAAAA==.Bagleflinger:BAAANQAECgQICAAAAA==.Baldr:BAAANQAECgQJBgAAAA==.Batarang:BAABNQAECn8fAAIBAAcK+wqYKQB4AQABAAcK+wqYKQB4AQAAAA==.',
Be='Bealzulbub:BAAANQABCgQIBwAAAA==.Bearbarian:BAABNQAECn86AAIUAAoKhgpZIgCEAQAUAAoKhgpZIgCEAQAAAA==.Beastkael:BAAANQAECgUICwAAAA==.Beg:BAABNQAECn8hAAIXAAkKBBCyXwACAgAXAAkKBBCyXwACAgAAAA==.Belfalas:BAAANQABCgQICAAAAA==.Beliir:BAAANQADCggICAABNQAECgkJKwATALMcAA==.Berghain:BAAANQADCgQIAgAAAA==.Berick:BAAANQAECgEIAgAAAA==.Betzalel:BAABNQAECn8eAAIXAAkKvBKKXQAJAgAXAAkKvBKKXQAJAgAAAA==.Beytryx:BAAANQAECgIIAwAAAA==.',
Bi='Bittycakes:BAAANQAECgIIAgAAAA==.',
Bl='Blackstar:BAAANQAECgMIAwAAAA==.Bladeoftruth:BAABNQAECn8iAAIKAAoK7R+lFwDwAgAKAAoK7R+lFwDwAgAAAA==.Blaize:BAAANQADCgYICQAAAA==.Blessette:BAAANQAECgUIBQABNQAECgoKLwAXABAjAA==.Blitzwing:BAAANQAECgUIBgAAAA==.Bloodyaggro:BAAANQAECgYICgAAAA==.',
Bo='Bobapstab:BAAANQADCgIIAgAAAA==.Bodin:BAAANQADCgcIBwAAAA==.Bonnabelle:BAACNQAFFH8LAAIXAAQKZgcJGAAAAQAXAAQKZgcJGAAAAQA1AAQKfzkAAhcACgoPE9ApAG8CABcACgoPE9ApAG8CAAAA.Boombawks:BAAANQAECggICQAAAA==.Bor:BAAANQAECgYIDQABNQAECgoKIgAUAHMlAA==.Bos:BAABNQAECn8eAAIYAAgKtxqmGgB2AgAYAAgKtxqmGgB2AgAAAA==.Bowtoahh:BAAANQABCgEIAQABNQAECgcIGAAZAIIXAA==.',
Br='Brewnelle:BAAANQADCggIDgABNQAECggIGgAQAHgZAA==.Briest:BAAANQAECgQIBAABNQAECggIGgAQAHgZAA==.Bristra:BAAANQAECgUIBQABNQAECgYICQARAAAAAA==.Brownbar:BAAANQAECgYICQAAAA==.Bruid:BAABNQAECn8aAAMQAAgKeBnhJgDqAQAQAAcKzBfhJgDqAQAaAAcKvhI4TwCiAQAAAA==.Bruneigin:BAAANQAECggIEQAAAA==.',
Ca='Cailey:BAAANQAECgUICQAAAA==.Calzone:BAAANQADCgYIBgAAAA==.Cambria:BAAANQADCgEIAQABNQAECgIIAwARAAAAAA==.Cardian:BAAANQADCgcIEwAAAA==.Caridin:BAAANQADCgYIEgAAAA==.Carmey:BAAANQAECgQIAwABNQAECgUIBwARAAAAAA==.Carrin:BAABNQAECn9QAAISAAkKxSJMHwDEAgASAAkKxSJMHwDEAgAAAA==.Castanza:BAAANQADCggICAAAAA==.Catalyia:BAABNQAECn81AAIbAAoKrxfVTQCFAgAbAAoKrxfVTQCFAgAAAA==.Catris:BAABNQAECn8ZAAIYAAYKygaqNwClAAAYAAYKygaqNwClAAAAAA==.Catset:BAABNQAECn8cAAIaAAgK9wdnWwBlAQAaAAgK9wdnWwBlAQAAAA==.',
Ch='Charades:BAAANQADCgYIDAAAAA==.Charlton:BAAANQAECggIDwABNQAECgoKJAAWACENAA==.Chazzo:BAABNQAECn8hAAIcAAoKGBOQfgAeAgAcAAoKGBOQfgAeAgAAAA==.Chazzy:BAAANQADCgcIBwAAAA==.Chila:BAAANQAECggIEwAAAA==.',
Co='Commy:BAABNQAECn8dAAMOAAgKXxAjzQDsAQAOAAgKXxAjzQDsAQANAAEKng3nQgA+AAAAAA==.Concorde:BAAANQAECgUICgAAAA==.Copiousconns:BAABNQAECn8rAAIVAAkKIQttJQBIAQAVAAkKIQttJQBIAQAAAA==.Corinne:BAAANQADCggIDQAAAA==.Corlock:BAAANQADCgYIDAAAAA==.Cornholy:BAAANQADCgMIAwAAAA==.',
Cr='Craitos:BAAANQABCgYIDQAAAA==.Cranjis:BAAANQAECgYIBgAAAA==.Crimsonfury:BAABNQAECn8YAAIdAAYK6QjoTAC9AAAdAAYK6QjoTAC9AAAAAA==.',
Cu='Cubos:BAABNQAECn89AAMZAAoKBSZLAgDVAwAZAAoKBSZLAgDVAwAVAAEKISQ5HQBqAAAAAA==.Cutlash:BAAANQAECggIEAAAAA==.Cutslash:BAAANQAECgIIAgABNQAECggIEAARAAAAAA==.',
Da='Daemona:BAABNQAECn8uAAMdAAoKXhNUMwARAgAdAAoKXhNUMwARAgAeAAEKAAB1WgAAAAAAAA==.Daieniceis:BAABNQAECn8cAAIbAAcKgASJ2gBLAQAbAAcKgASJ2gBLAQAAAA==.Dalkurn:BAACNQAFFH8RAAIQAAYKOiLoAQBXAgAQAAYKOiLoAQBXAgA1AAQKfysAAhAACQrrI/wHAEQDABAACQrrI/wHAEQDAAAA.',
De='Decayy:BAACNQAFFH8LAAIKAAUKlRiMDgBrAQAKAAUKlRiMDgBrAQA1AAQKfyMAAgoACQqIImAWAPoCAAoACQqIImAWAPoCAAAA.Deceptakahn:BAABNQAECn8vAAIUAAgKKgYzNgD0AAAUAAgKKgYzNgD0AAAAAA==.Decimus:BAAANQAECgMIAwABNQAECgoKNgAbADIZAA==.Derailedbeef:BAACNQAFFH8KAAMcAAQKZBTLFwDKAAAcAAQKLw/LFwDKAAAfAAEKzh+oAwBIAAA1AAQKfzsAAxwACgrTHVskAJACABwACgq4HVskAJACAB8ABArDGhQXAC0BAAAA.Deydoralia:BAABNQAECn9VAAIMAAoK0COVCQBpAwAMAAoK0COVCQBpAwAAAA==.',
Di='Diabeetus:BAAANQADCgQICAAAAA==.Diô:BAAANQADCggICAAAAA==.',
Dl='Dlwlrma:BAABNQAECn8UAAMHAAkKyw+8EwBAAQAHAAcKBRK8EwBAAQAaAAYKVgWAhgC4AAAAAA==.',
Dn='Dnme:BAABNQAECn8mAAIeAAoKkhHMKQD1AQAeAAoKkhHMKQD1AQAAAA==.',
Do='Doieha:BAAANQADCggIEQABNQAECgoKLAAQAPcdAA==.Doneldus:BAAANQAECggIEwAAAA==.Dool:BAABNQAECn8VAAIeAAcKqQpELwDoAAAeAAcKqQpELwDoAAAAAA==.Dorfdragon:BAABNQAECn8lAAIPAAkKowpdEQDyAAAPAAkKowpdEQDyAAAAAA==.Dorfe:BAABNQAECn85AAICAAoKCBX3CgD9AQACAAoKCBX3CgD9AQAAAA==.Dorflock:BAAANQAECgcIBwAAAA==.',
Dr='Drakona:BAAANQABCgQICAAAAA==.Drakthur:BAAANQADCgcIGQAAAA==.Draximus:BAAANQADCgUIBQAAAA==.Dreamfyre:BAAANQADCgYIBgAAAA==.Drewgarymore:BAABNQAECn87AAMaAAoKgBOBHQDiAQAaAAoKzhGBHQDiAQAUAAcKDhcLHwCmAQAAAA==.Drough:BAAANQAECgQICgABNQAECgoKMgAgAOgXAA==.Drzeal:BAAANQADCggIDgAAAA==.',
Du='Dukker:BAAANQABCgIIAgAAAA==.Dumblêdorê:BAAANQADCgMIAwABNQAFFAYIDwASAPEPAA==.Durandall:BAACNQAFFH8PAAISAAYK8Q92CADDAQASAAYK8Q92CADDAQA1AAQKfzQAAhIACgruHocpAJMCABIACgruHocpAJMCAAAA.Durleap:BAAANQAECgcIDwAAAA==.Durthmaul:BAABNQAECn8ZAAIGAAgKnAZWXwAtAQAGAAgKnAZWXwAtAQABNQAFFAYIDwASAPEPAA==.',
Dw='Dwarflock:BAABNQAECn8bAAIZAAgKGhW5ZwAkAgAZAAgKGhW5ZwAkAgAAAA==.',
Dy='Dylpickl:BAABNQAECn8VAAIeAAkKUx3KCwAiAwAeAAkKUx3KCwAiAwAAAA==.Dylán:BAAANQAECgQIBAAAAA==.Dymàs:BAABNQAECn8cAAIhAAcKwAaeYQAeAQAhAAcKwAaeYQAeAQAAAA==.',
Ef='Eft:BAAANQABCgQIBAAAAA==.',
El='Elliemae:BAAANQAECgQIBAABNQAECgoKOAAMAGMfAA==.Elow:BAAANQADCgIIAgAAAA==.Elyiet:BAAANQAECgUICQAAAA==.',
Er='Erazminash:BAAANQAECgMJBAAAAA==.Erkenbrand:BAAANQAECgEIAQABNQAECggIHAAcAEQcAA==.',
Es='Esdeáth:BAAANQADCgIIAgAAAA==.Esmae:BAABNQAECn8WAAIFAAgK+A/fYwBYAQAFAAgK+A/fYwBYAQAAAA==.Ess:BAABNQAECn8YAAITAAYKegp1NwClAAATAAYKegp1NwClAAAAAA==.',
Et='Etabagodeeks:BAAANQAECgYICQAAAA==.',
Ev='Evalina:BAAANQADCgQIBAABNQAECgYICQARAAAAAA==.Evvie:BAABNQAECn8WAAIVAAgK9wRAEwClAAAVAAgK9wRAEwClAAAAAA==.',
Ex='Executiepie:BAAANQADCggICAAAAA==.',
Fa='Fabulosoo:BAABNQAECn8dAAISAAcKsxvefgAsAgASAAcKsxvefgAsAgAAAA==.Falcondor:BAAANQADCgMIAwAAAA==.Fallin:BAAANQAECgUIBQAAAA==.Fantarius:BAACNQAFFH8PAAIXAAYKuhRvEACPAQAXAAYKuhRvEACPAQA1AAQKfzwAAxcACgo4IVMgAKsCABcACgo4IVMgAKsCAAkAAQqIBYouACgAAAAA.Fantazee:BAAANQADCgUIBQABNQAFFAYIDwAXALoUAA==.Fatdono:BAAANQAECggIEgAAAA==.',
Fi='Fibbs:BAABNQAECn8hAAIUAAkKDRxGEgA+AgAUAAkKDRxGEgA+AgAAAA==.Fikti:BAABNQAECn80AAMiAAoK+BfqBACDAgAiAAgKuxvqBACDAgAZAAcKEhSnqgB9AQAAAA==.Firetongue:BAAANQADCgUIBQAAAA==.Firocios:BAABNQAECn8iAAIMAAcKBRMngwCRAQAMAAcKBRMngwCRAQAAAA==.',
Fl='Flaminia:BAAANQADCgUICQAAAA==.Flatiron:BAAANQADCgcIDQABNQAECgcIGQAjAM4LAA==.',
Fo='Fossilz:BAAANQADCggJCAAAAA==.Foxybeans:BAAANQADCgYICgAAAA==.',
Fr='Fran:BAABNQAECn8kAAIIAAYK0RFgBwBgAQAIAAYK0RFgBwBgAQABNQAECgkJLAAIAFsUAA==.Frieda:BAAANQABCgIIAgAAAA==.Frink:BAABNQAECn8ZAAMjAAcKzguLKwAGAQAjAAcKzguLKwAGAQAkAAEKAACiNgAeAAAAAA==.Frostyfella:BAACNQAFFH8SAAMOAAcK3haoFwC7AQAOAAYKyRqoFwC7AQANAAEKMAerDgBTAAA1AAQKf0AAAg4ACgpsInMaAGwDAA4ACgpsInMaAGwDAAE1AAEKAggCABEAAAAA.',
Fu='Furman:BAAANQADCgMIAwAAAA==.Fuzzycakes:BAAANQADCggICAAAAA==.',
['Fá']='Fáith:BAABNQAECn8WAAIHAAYKKw1sHwAeAQAHAAYKKw1sHwAeAQAAAA==.',
Ga='Garypotter:BAABNQAECn84AAIeAAoK8yGBDAAaAwAeAAoK8yGBDAAaAwAAAA==.Gazooks:BAAANQADCgYIEwAAAA==.',
Ge='Gelantria:BAAANQADCgcIBwAAAA==.',
Gi='Gillacs:BAAANQADCgMJAwAAAA==.',
Gl='Gleave:BAABNQAECn8yAAIbAAoKUyIiHgAfAwAbAAoKUyIiHgAfAwAAAA==.Glâdiátor:BAAANQADCgMIAwAAAA==.',
Go='Goodbrew:BAABNQAECn8VAAIjAAgKRgo2PQAsAQAjAAgKRgo2PQAsAQAAAA==.',
Gr='Greyfear:BAAANQABCgYIBgABNQAECgkJKQAcACEPAA==.Greystoke:BAAANQADCgQIBAAAAA==.Greyvee:BAAANQAECgIIBwAAAA==.Grimtide:BAAANQAECgYIDQABNQAECgoKIgAUAHMlAA==.Grindelbald:BAABNQAECn8bAAMOAAkK0hL6kwBYAgAOAAkK0hL6kwBYAgAlAAIK4ghxCQByAAAAAA==.',
Gt='Gtfofupá:BAABNQAECn8XAAIKAAcKvxZCOwArAQAKAAcKvxZCOwArAQAAAA==.',
Gu='Gulraan:BAAANQAECggIDAAAAA==.Gushee:BAABNQAECn8jAAIfAAkK2RnIDgDBAQAfAAkK2RnIDgDBAQAAAA==.',
Gw='Gwenn:BAAANQADCgYIEgAAAA==.',
Gy='Gyes:BAAANQAECgYICQAAAA==.',
Ha='Hadez:BAAANQADCgcICwAAAA==.Hae:BAAANQADCgIIAgAAAA==.Haegan:BAAANQABCgYIBwAAAA==.Hagioszoe:BAAANQAECgUIDAAAAA==.Hairypoóter:BAAANQADCgUICQAAAA==.Haldor:BAAANQAECggICAABNQAECgoKJAAWACENAA==.Hanamari:BAACNQAFFH8OAAIjAAYKRAa8BwB0AQAjAAYKRAa8BwB0AQA1AAQKfyIAAyMACQrgFmkhACACACMACQrgFmkhACACACYAAQrrAR5WAB0AAAAA.Harakrron:BAAANQAECgMIAwAAAA==.Harleyquìnn:BAAANQAECgMIAwAAAA==.Harydresden:BAABNQAECn8fAAIOAAgKOAT20ADdAAAOAAgKOAT20ADdAAAAAA==.Hawkesmage:BAAANQAECgQIBAAAAA==.Hawkslayer:BAABNQAECn8aAAISAAYKQgaqAwGqAAASAAYKQgaqAwGqAAAAAA==.Hazule:BAAANQAECgIIAwABNQAECggIHQAFAPcYAA==.',
He='Healadín:BAAANQAECgYIBgAAAA==.Hedgelord:BAACNQAFFH8TAAIaAAUKThpaDAD0AAAaAAUKThpaDAD0AAA1AAQKfywAAhoACgruHVIQAIICABoACgruHVIQAIICAAAA.Heyboyy:BAABNQAECn8aAAIQAAgKrhmCFAA5AgAQAAgKrhmCFAA5AgABNQAFFAQIBQAbAEsYAA==.',
Hi='Hisky:BAAANQAECgQIBwAAAA==.',
Ho='Hobe:BAABNQAECn8YAAIZAAcKsh/AXABBAgAZAAcKsh/AXABBAgAAAA==.Holytruck:BAAANQADCgEIAQAAAA==.Hoodmagik:BAAANQABCgYIBwABNQAECgkJHQAZADMVAA==.Hornadus:BAAANQADCgMIAwAAAA==.Hornride:BAAANQADCgMIAwAAAA==.',
Hu='Humoresque:BAAANQAECgYIEwAAAA==.Huntaredead:BAAANQAECgQIBgABNQAECgoKJQAZAL4hAA==.',
Ic='Icyblades:BAABNQAECn8eAAIDAAkKfwumZwBzAQADAAkKfwumZwBzAQAAAA==.',
If='Ifellbehind:BAAANQADCgUIBQAAAA==.',
Il='Ilidania:BAAANQAECgYICQAAAA==.Ilyna:BAABNQAECn8iAAIZAAcKgQpcsgBrAQAZAAcKgQpcsgBrAQAAAA==.',
Im='Immortalnut:BAABNQAECn8UAAIPAAcKjwhYIABSAQAPAAcKjwhYIABSAQAAAA==.',
In='Inori:BAAANQADCgcIBwAAAA==.Interrupted:BAAANQAECgIIAgAAAA==.',
It='Itscell:BAAANQADCgEIAQAAAA==.Ittyycakes:BAAANQAECgMIAwAAAA==.',
Ja='Jackypan:BAAANQADCgUIBQAAAA==.Jaedis:BAAANQAECgYIDgAAAA==.Jaktar:BAABNQAECn8VAAIbAAkKXwjHjwDqAQAbAAkKXwjHjwDqAQAAAA==.Jane:BAAANQAECgQIBAAAAA==.Janet:BAABNQAECn8bAAIgAAkKrhA8FADiAQAgAAkKrhA8FADiAQAAAA==.Jani:BAAANQADCgQIBAABNQAECgkJGwAgAK4QAA==.Janiina:BAAANQADCgYIDQAAAA==.Japheth:BAAANQAECgIIAwAAAA==.',
Je='Jeroung:BAAANQABCgQIAgABNQAECgkJKQAcACEPAA==.Jezak:BAAANQAECgQIBAABNQAECgcIBQARAAAAAA==.',
Jo='Jol:BAAANQABCgQIBAAAAA==.Jone:BAAANQAECgcIEQAAAA==.Joobs:BAABNQAECn8XAAIVAAkKGAzeFADHAQAVAAkKGAzeFADHAQAAAA==.Joosh:BAAANQAECgYIBgAAAA==.',
Js='Jslice:BAACNQAFFH8LAAIcAAUKmg/gFQB5AQAcAAUKmg/gFQB5AQA1AAQKfyEAAhwACQrHIOtGALUCABwACQrHIOtGALUCAAAA.',
Ju='Juda:BAAANQAECgUICAAAAA==.Jurant:BAAANQABCgQJAwAAAA==.Jurucil:BAAANQAECgQIBQAAAA==.',
Ka='Kaelys:BAABNQAECn8hAAMMAAYK3xEReQAZAQAMAAYK3xEReQAZAQASAAEKAAAV0wEdAAAAAA==.Kahliea:BAAANQAECgUIEwAAAA==.Kaidance:BAAANQAECggICgAAAA==.Kaisaze:BAABNQAECn8mAAIhAAoKAwyOMwCaAQAhAAoKAwyOMwCaAQAAAA==.Kamiga:BAAANQAECgYIBgABNQAECgoKLAAQAPcdAA==.Kapachka:BAAANQAECgcIEAAAAA==.Karbide:BAAANQAECgIIAgAAAA==.Kardisa:BAAANQABCgIIAgAAAA==.Kateri:BAAANQAECgQIBQAAAA==.Katmarie:BAAANQAECgQICgAAAA==.Kazothor:BAABNQAECn8ZAAIKAAYKghuvPgAcAQAKAAYKghuvPgAcAQAAAA==.',
Ke='Kelborne:BAAANQAECgUIBwAAAA==.Keria:BAACNQAFFH8VAAIdAAgKYh0jAgCMAgAdAAgKYh0jAgCMAgA1AAQKf0IAAh0ACgr9JeMCAMYDAB0ACgr9JeMCAMYDAAAA.Keyz:BAAANQAECgcICwAAAA==.',
Kh='Kharfáz:BAAANQAECgMIAwAAAA==.',
Ki='Kibbwarrior:BAAANQAECggIDAAAAA==.Kiretsu:BAABNQAECn8cAAMNAAkK0BBpGAA1AQAOAAgKlw7w4gDDAQANAAUK/w9pGAA1AQAAAA==.',
Kn='Knowén:BAAANQADCggIDgAAAA==.',
Ko='Koder:BAAANQADCgYIDAAAAA==.Kovus:BAABNQAECn8WAAIUAAgKrwgYMQDUAAAUAAgKrwgYMQDUAAAAAA==.',
Kr='Kragami:BAAANQAECgcIEQAAAA==.Krelien:BAAANQAECgUICgAAAA==.Krispee:BAABNQAECn8UAAISAAgKvgce1ABzAQASAAgKvgce1ABzAQAAAA==.Kristanya:BAABNQAECn88AAIWAAoKKwjcEgCLAQAWAAoKKwjcEgCLAQAAAA==.Kristina:BAEBNQAECn8XAAIcAAkKvxHNYACjAQAcAAkKvxHNYACjAQAAAA==.',
Ks='Ks:BAAANQAECgQIBAAAAA==.',
Ku='Kulaidmage:BAABNQAECn8fAAIOAAgKGRaHsgAeAgAOAAgKGRaHsgAeAgAAAA==.Kurtcowbain:BAAANQAECgYIEgAAAA==.Kushies:BAAANQADCgUIBQAAAA==.',
Ky='Kynetik:BAAANQAECggICAABNQAFFAUIDAAGAOoDAA==.Kyttin:BAAANQADCggICAAAAA==.',
La='Ladamirea:BAABNQAECn9GAAInAAoKwSN6AQCSAwAnAAoKwSN6AQCSAwAAAA==.Lamashtu:BAABNQAECn8lAAIYAAgKtBb3HgBFAgAYAAgKtBb3HgBFAgAAAA==.Lasciel:BAAANQADCgcIBwAAAA==.Lashar:BAAANQADCgYIBgAAAA==.Layli:BAAANQADCgIIAgABNQAECgIIAgARAAAAAA==.Layssar:BAAANQAECgMIAgAAAA==.',
Le='Leddy:BAABNQAECn8wAAMJAAoKzBbEBQBFAgAJAAkKAhfEBQBFAgAYAAgKJRRtFQDMAQAAAA==.Leiman:BAAANQABCgQIBQAAAA==.Lemmy:BAAANQAECgcIBwAAAA==.Lenabug:BAAANQABCgIIAgAAAA==.Lexiê:BAABNQAECn8cAAIFAAkKfxJJbgDAAQAFAAkKfxJJbgDAAQAAAA==.',
Li='Lightninjack:BAAANQAECgEIAQAAAA==.Lightsworn:BAAANQADCgEIAQAAAA==.Lilifa:BAABNQAECn8mAAImAAkKSR7JDgCWAgAmAAkKSR7JDgCWAgAAAA==.Lilillidari:BAABNQAECn8eAAIdAAkKPByhHQCsAgAdAAkKPByhHQCsAgABNQAFFAcIGwADAHUZAA==.Lillirann:BAAANQAECgEIAQAAAA==.Lilmontaro:BAACNQAFFH8bAAQDAAcKdRn6BgCsAQADAAUKABn6BgCsAQAhAAQKmBhgCQD7AAAKAAEKAAAJOQAgAAA1AAQKf00AAyEACgpMJaUKAEUDACEACgojJKUKAEUDAAMACQpAJDcSACYDAAAA.Lilunholy:BAABNQAECn8UAAIDAAgK4xrNNQBRAgADAAgK4xrNNQBRAgABNQAFFAcIGwADAHUZAA==.Linali:BAAANQAECgYIBwAAAA==.Lirianna:BAAANQADCgMIAwAAAA==.Lisey:BAAANQAECgIIAwAAAA==.Listari:BAAANQADCgQIBAAAAA==.Lisyao:BAABNQAECn86AAMGAAkK3As1PwCcAQAGAAkK3As1PwCcAQAFAAgKWAuNYQBgAQAAAA==.Littany:BAABNQAECn8rAAMMAAoKNRA+aQDbAQAMAAoKNRA+aQDbAQASAAcKXg8eygCHAQAAAA==.Littlenappy:BAAANQAECgEIAQAAAA==.Livane:BAAANQAECgQICAAAAA==.',
Lo='Loestus:BAAANQADCgQIBAAAAA==.Looneytoones:BAAANQAECgUIBQAAAA==.Loralia:BAAANQADCggIEAAAAA==.Lowground:BAAANQAECgEIAQAAAA==.',
Lu='Lucïna:BAABNQAECn8gAAIdAAkKEwztSQB9AQAdAAkKEwztSQB9AQAAAA==.Ludk:BAABNQAECn89AAIKAAoKUiK8CgDOAgAKAAoKUiK8CgDOAgAAAA==.Luk:BAABNQAECn9JAAMeAAoKaxUOGADAAQAeAAoKaxUOGADAAQAnAAUKqxKZGQAaAQABNQAECgoKKQASAAEXAA==.Lumiela:BAABNQAECn8aAAISAAgKHgX13wDfAAASAAgKHgX13wDfAAAAAA==.Luminah:BAAANQAECgIIAwAAAA==.Lunacy:BAAANQADCgYICgAAAA==.Luni:BAAANQAECgIIAgAAAA==.Lunì:BAAANQADCgQIBAABNQAECgIIAgARAAAAAA==.Luxmortic:BAAANQAECggIDwAAAA==.Luxshot:BAAANQADCggIEAAAAA==.',
['Lê']='Lêxie:BAAANQADCgcIDQAAAA==.',
['Ló']='Lóner:BAABNQAECn88AAMCAAoK9RGNLAA1AgACAAoKxg2NLAA1AgABAAoKDBFcNgDiAQAAAA==.',
['Lü']='Lüni:BAAANQADCgMIAwABNQAECgIIAgARAAAAAA==.',
Ma='Macbayne:BAAANQADCgEIAQAAAA==.Maebe:BAAANQAECgcICAAAAA==.Mageblaster:BAAANQADCgYICgAAAA==.Maggnut:BAABNQAECn8sAAIcAAoK3RMXkwDsAQAcAAoK3RMXkwDsAQAAAA==.Magicg:BAACNQAFFH8HAAIYAAYK9AWwCgBLAQAYAAYK9AWwCgBLAQA1AAQKfykAAxgACgoRHpMVALMCABgACgoRHpMVALMCABcAAQqmCqD4ADwAAAAA.Magordito:BAABNQAECn8bAAIOAAgK3gfD8gClAQAOAAgK3gfD8gClAQABNQAECgoKPAACAPURAA==.Mairek:BAACNQAFFH8OAAIOAAUK3g+UHwDgAAAOAAUK3g+UHwDgAAA1AAQKf0kAAg4ACgrtHd0kAJACAA4ACgrtHd0kAJACAAAA.Maleigoron:BAABNQAECn8aAAIZAAkK1QnMjgDCAQAZAAkK1QnMjgDCAQAAAA==.Malkuri:BAABNQAECn82AAMbAAoKMhljLABiAgAbAAkKMhljLABiAgAEAAgKlxGwKgD2AQAAAA==.Malorysera:BAACNQAFFH8PAAMoAAUKDyAXBgDlAAAoAAQKGBcXBgDlAAAPAAIK7SHwBQBZAAA1AAQKfzoABCgACgqBI3ABABQDACgACgqgIXABABQDAA8ACQp2Hc4IAOkCABYABgpZF6AkAJ0BAAAA.Marolt:BAAANQAECgEIAQABNQAECgoKLAAQAPcdAA==.Martrion:BAAANQABCgUIBQAAAA==.',
Mc='Mcbasketball:BAAANQAECgIIAgAAAA==.',
Me='Mechaljaxon:BAABNQAECn8WAAIVAAcKOQdvJgBCAQAVAAcKOQdvJgBCAQAAAA==.Menirva:BAABNQAECn8UAAIOAAgKYwrq5QC+AQAOAAgKYwrq5QC+AQABNQAECgoKNgAbADIZAA==.Merv:BAAANQAECgUIBgAAAA==.Metapal:BAABNQAECn8VAAITAAgK+BJyKgCJAQATAAgK+BJyKgCJAQABNQAFFAUIDAAGAOoDAA==.Metasham:BAACNQAFFH8MAAIGAAUK6gPcEgBDAQAGAAUK6gPcEgBDAQA1AAQKfzIAAgYACgptGp8mAOkCAAYACgptGp8mAOkCAAAA.',
Mi='Miiaa:BAABNQAECn8XAAMSAAgK7xy+dwA9AgASAAcK5R++dwA9AgATAAEKIw5ZbgA1AAAAAA==.Mijoy:BAAANQAECgQIBAAAAA==.Milane:BAAANQAECgQIBgAAAA==.',
Mo='Moirasha:BAABNQAECn8eAAQZAAkKVAl8sABvAQAZAAkKVAl8sABvAQAVAAIKRgLkeAA1AAAiAAEKAAB8MQAyAAAAAA==.Monkeydluffy:BAAANQAECgEIAQAAAA==.Monran:BAABNQAECn8fAAILAAgK1wytFgBlAQALAAgK1wytFgBlAQAAAA==.Moonwood:BAAANQADCgYIBgAAAA==.Moosand:BAAANQAECgUICAABNQAECgcIBQARAAAAAA==.Morphingtime:BAABNQAECn8gAAQHAAkKthmvGABxAQAaAAcKoBX6UQCUAQAHAAUKDBuvGABxAQAQAAcKpBXfPAA7AQAAAA==.Mortivus:BAABNQAECn8VAAMDAAcKABSyPAD1AAADAAYKmhWyPAD1AAAhAAUK9AyncgDVAAAAAA==.',
Mu='Mudsworn:BAAANQAECgIIAgAAAA==.Muggs:BAAANQADCggIDgAAAA==.Mulvane:BAABNQAECn8WAAIXAAgKfxVvXgCLAQAXAAgKfxVvXgCLAQAAAA==.Mustachio:BAABNQAECn8eAAIOAAgKURlbrAApAgAOAAgKURlbrAApAgAAAA==.',
Mw='Mwc:BAACNQAFFH8MAAMBAAYKQhbhBgCjAQABAAUK5hHhBgCjAQACAAIKVCPVFQCcAAA1AAQKfxYAAwEACQqDJEkFADYDAAEACQqDJEkFADYDAAIABAp3FshpAAoBAAAA.',
Mz='Mziao:BAAANQADCggIFQAAAA==.',
Na='Naiara:BAAANQAECgQIBAAAAA==.Nashia:BAAANQADCgUIBQAAAA==.Nazureshal:BAAANQADCggICAABNQAECgUIDQARAAAAAA==.',
Ne='Neall:BAABNQAECn8eAAIgAAkKpApWIgA4AQAgAAkKpApWIgA4AQAAAA==.Negaryu:BAAANQAECgUIDwAAAA==.Ner:BAAANQADCgEIAQAAAA==.Nethryx:BAAANQADCgMIAwAAAA==.Nevets:BAABNQAECn8iAAIBAAkK8QykRwCVAQABAAkK8QykRwCVAQAAAA==.Nezanot:BAAANQAECgYIBgAAAA==.',
Ni='Nightbird:BAAANQAECgcICwAAAA==.Nightheals:BAAANQADCggIDQABNQAECgcIJgAFAHQcAA==.',
No='Nonna:BAABNQAECn89AAIGAAoKGgn8VABNAQAGAAoKGgn8VABNAQAAAA==.Noslrac:BAAANQAECgcIDwAAAA==.Notamonk:BAAANQAECggIDwAAAA==.Notbysight:BAAANQADCgYIBgAAAA==.Notorious:BAAANQAECggIQwAAAQ==.',
Nu='Nuina:BAAANQADCgMIAwAAAA==.',
Ny='Nyxjr:BAAANQADCgIJAgAAAA==.',
Ob='Oblast:BAABNQAECn89AAIOAAoKKyU4CwCpAwAOAAoKKyU4CwCpAwAAAA==.',
Od='Odb:BAAANQADCgQIBAAAAA==.Odirtyblasta:BAAANQADCgYIBgAAAA==.',
Ol='Olmanjankins:BAABNQAECn8ZAAIhAAgKlA+aTACFAQAhAAgKlA+aTACFAQAAAA==.',
Om='Omneg:BAAANQAECgQIBAAAAA==.',
On='Oneshotdeath:BAAANQAECgYIBAABNQAECgkJHQAaAI0JAA==.Onlydks:BAABNQAECn8aAAQhAAkK3g2sRwCfAQAhAAkK3g2sRwCfAQADAAMKjAtktACHAAAKAAEKAAA83QAhAAABNQAFFAUICwAfAIwNAA==.Onlyslams:BAACNQAFFH8LAAMfAAUKjA1iAQAyAQAfAAUKjA1iAQAyAQAcAAIKggWOOABaAAA1AAQKfzEAAx8ACQoaIlwCAOYCAB8ACQoaIlwCAOYCABwABwpiGDOqALMBAAAA.Onlytrolling:BAAANQAECggIDwAAAA==.',
Oo='Ooze:BAAANQADCgMIAwAAAA==.',
Or='Orbaz:BAAANQADCgcIBgABNQAECgoKHQAjAEYNAA==.Orter:BAABNQAECn8gAAIDAAkKWRunPAAuAgADAAkKWRunPAAuAgAAAA==.',
Ot='Ottan:BAAANQAECgEIAQAAAA==.',
Ov='Overkill:BAAANQAECgMIAwAAAA==.Ovo:BAAANQADCgMIAwAAAA==.',
Pa='Pandorasfox:BAAANQADCgcICAAAAA==.Papsfear:BAABNQAECn8YAAIZAAcKghdBfgDrAQAZAAcKghdBfgDrAQAAAA==.Parceh:BAABNQAECn82AAMGAAoKsCBvGACEAgAGAAkKayJvGACEAgAFAAkKIh/kOgBzAgAAAA==.',
Ph='Phydaux:BAABNQAECn8XAAIbAAYK7xeHpAAkAQAbAAYK7xeHpAAkAQAAAA==.',
Pi='Pinkponyclub:BAAANQADCggICAAAAA==.Pizzaman:BAAANQAECgcIDwAAAA==.',
Pr='Pringle:BAAANQADCgYIEgABNQAECgQIBQARAAAAAA==.Prosciutto:BAABNQAECn8+AAMYAAoKfBr2DABcAgAYAAoKfBr2DABcAgAJAAEKbwfHFgAuAAAAAA==.Proxima:BAAANQAECgcICAAAAA==.',
Pt='Ptoughneigh:BAAANQAECgQIBAAAAA==.',
Pu='Puckish:BAACNQAFFH8KAAIXAAQK7wMdGwASAQAXAAQK7wMdGwASAQA1AAQKfykAAxcACQp3DXByAMUBABcACQp3DXByAMUBAAkAAQq8AS4xACIAAAAA.Punn:BAAANQAECgcIDAABNQAECgoKJQAZAL4hAA==.Punnisher:BAABNQAECn8lAAMZAAoKviGOGgAcAwAZAAoKviGOGgAcAwAVAAEKvhunbQBDAAAAAA==.Pureflow:BAABNQAECn8YAAIOAAkK1xuDhQBzAgAOAAkK1xuDhQBzAgAAAA==.',
['Pä']='Päiñ:BAAANQADCgUIBQAAAA==.',
Qu='Quackers:BAABNQAECn8dAAIcAAkKUhIOpgC+AQAcAAkKUhIOpgC+AQAAAA==.Quicks:BAABNQAECn8qAAISAAoKHRtFUQChAgASAAoKHRtFUQChAgAAAA==.Quáckys:BAAANQAECggICwAAAA==.Quárters:BAAANQAECggICAAAAA==.',
Ra='Radünz:BAAANQABCgQIBwABNQAECgoKQAAHAEYdAA==.Raelianna:BAAANQAECgQIDAABNQAECgoKPAAOAJglAA==.Raewyna:BAABNQAECn8ZAAIbAAgK+AkgvQCJAQAbAAgK+AkgvQCJAQAAAA==.Rahruhai:BAABNQAECn8sAAQQAAoK9x1+BgBIAwAQAAoK9x1+BgBIAwAHAAkK5h3iBwDeAgAaAAcKGBVDWwBlAQAAAA==.Rain:BAAANQAECgQIBwAAAA==.Raine:BAABNQAECn8ZAAMGAAoKEhebbQDXAQAGAAgKdRSbbQDXAQAFAAcKgh1EZwDXAQAAAA==.Rainingblood:BAABNQAECn8fAAISAAgKyga+0wD0AAASAAgKyga+0wD0AAAAAA==.Rainjar:BAABNQAECn8bAAImAAgKniJ/DAC7AgAmAAgKniJ/DAC7AgAAAA==.Rancîd:BAABNQAECn8eAAQDAAgKYRKHWwChAQADAAgKYRKHWwChAQAKAAUKtwishgDjAAAhAAMKtAdRjwB7AAABNQAECgoKMgAgAOgXAA==.Raneeh:BAAANQABCgQIBAAAAA==.Ranron:BAABNQAECn8yAAMgAAoK6BdpCQAEAgAgAAoKyhZpCQAEAgAcAAgKag3blgAbAQAAAA==.Raphael:BAABNQAECn8nAAMDAAkKlRYPXgCXAQADAAgKKhIPXgCXAQAKAAcK/RdnXQB8AQAAAA==.Rasik:BAABNQAECn89AAIcAAoKeR3ILgBdAgAcAAoKeR3ILgBdAgAAAA==.Ravenblood:BAAANQAECgcICgAAAA==.Rayel:BAABNQAECn8dAAIXAAkKeBuCMABLAgAXAAkKeBuCMABLAgAAAA==.Raylyn:BAAANQAECgUIDAAAAA==.Raymotgus:BAAANQADCgEIAQAAAA==.Razzak:BAAANQAECgYICAABNQAECgcIBQARAAAAAA==.',
Rh='Rhadamancus:BAAANQAECgIIAwAAAA==.Rhani:BAAANQAECgQIBQAAAA==.Rheanon:BAAANQAECgQIBgAAAA==.Rhodrage:BAAANQADCgEIAQAAAA==.Rhome:BAACNQAFFH8GAAIXAAIKjRvdIQCeAAAXAAIKjRvdIQCeAAA1AAQKfy8AAxcACgrhIzYFAJ8DABcACgrhIzYFAJ8DAAkAAQoAGPYSAEUAAAAA.Rhox:BAAANQADCggJEQAAAA==.',
Ri='Rialu:BAABNQAECn8rAAIXAAoKkA+nbgDSAQAXAAoKkA+nbgDSAQAAAA==.Ribald:BAAANQAECgUICQAAAA==.Rickgrimes:BAABNQAECn8zAAMhAAkKhSPtDwARAwAhAAgKTSHtDwARAwADAAgKRiD/KACVAgAAAA==.Risandra:BAAANQAECgcICQABNQAECgoKLAAQAPcdAA==.',
Ro='Roid:BAABNQAECn8gAAMMAAkKLw6aXAACAgAMAAkKLw6aXAACAgASAAIKawKZlgE9AAAAAA==.Rolph:BAAANQAECgYIBgABNQAECgkJKQAcACEPAA==.Rotcorpse:BAAANQAECggIDwAAAA==.',
Ru='Ruddam:BAAANQAECgYIDgAAAA==.',
['Rä']='Räveñz:BAABNQAECn8wAAIUAAkKdRONGwDHAQAUAAkKdRONGwDHAQAAAA==.',
Sa='Saintabes:BAACNQAFFH8UAAIXAAcKORbFCADgAQAXAAcKORbFCADgAQA1AAQKfysAAhcACgpvIpQXAO0CABcACgpvIpQXAO0CAAAA.Saioya:BAAANQAECgYICgABNQAECgoKLAAQAPcdAA==.Saitame:BAAANQADCggICAAAAA==.Sakurah:BAABNQAECn8pAAMFAAoKhBqLVAAVAgAFAAoKhBqLVAAVAgAGAAIKnQKi8gAhAAAAAA==.Sandara:BAAANQADCgMIAwAAAA==.Sanerinn:BAAANQAECgQICAAAAA==.Sanicor:BAAANQAECgQIBAAAAA==.Sanrinn:BAABNQAECn8sAAMbAAkKmh0qHgCiAgAbAAkKmh0qHgCiAgAIAAQKdwS0DACTAAAAAA==.Sappy:BAAANQAECgEIAQAAAA==.Sarahboom:BAACNQAFFH8TAAIOAAYK/Ak9IwBtAQAOAAYK/Ak9IwBtAQA1AAQKfzQAAg4ACgrDGGpdANMBAA4ACgrDGGpdANMBAAAA.Sarahjupiter:BAAANQAECgcIDQABNQAFFAYIEwAOAPwJAA==.Sargarach:BAAANQADCgEIAQAAAA==.Sarrin:BAAANQADCgQIBAABNQAECgoKPAAdAJAaAA==.Savaant:BAAANQADCgIIAgAAAA==.',
Sc='Scapegoat:BAEANQAECggIMgAAAQ==.Scraime:BAAANQAECgQICAAAAA==.Scrubbles:BAAANQAECgMIAwAAAA==.',
Se='Seekýefirst:BAAANQADCgcIBwAAAA==.Seethe:BAAANQADCgYIBgAAAA==.Seger:BAAANQAECgcIDgAAAA==.Seilah:BAABNQAECn8cAAIQAAcKRCT5EADNAgAQAAcKRCT5EADNAgAAAA==.Seliah:BAAANQAECgUIDQAAAA==.Senpai:BAAANQADCgUIBQAAAA==.Senuya:BAAANQADCggICAABNQAECgkJKQAcACEPAA==.Seräph:BAABNQAECn8aAAIGAAcKahHgaAASAQAGAAcKahHgaAASAQABNQAECgoKFQAaANIMAA==.',
Sh='Shadowglade:BAABNQAECn9CAAIaAAoKihUFGgAGAgAaAAoKihUFGgAGAgAAAA==.Shadowmourne:BAAANQABCgIIAgAAAA==.Shalltear:BAABNQAECn8ZAAIeAAYKqgLFPgB8AAAeAAYKqgLFPgB8AAAAAA==.Shamizzle:BAABNQAECn8hAAIGAAkK3xMkYAABAgAGAAkK3xMkYAABAgAAAA==.Shammydavis:BAABNQAECn8nAAIFAAkKESDCHAClAgAFAAkKESDCHAClAgAAAA==.Shaølinstørm:BAAANQADCgMIAwAAAA==.Shiftybud:BAAANQADCgQICwAAAA==.Shinobi:BAAANQAECgEIAQAAAA==.Shiroikami:BAAANQAECggIDwABNQADCgIIAgARAAAAAA==.Shocknorris:BAAANQADCgYIBgAAAA==.Shrapnel:BAABNQAECn8dAAIbAAcK7QTs7AAoAQAbAAcK7QTs7AAoAQAAAA==.Shuna:BAEANQADCgYIBgABNQAECgkJKAAEACoOAA==.Shàmwôw:BAAANQADCgYIBAAAAA==.Shàytan:BAABNQAECn8gAAIdAAgKJA02PwDCAQAdAAgKJA02PwDCAQAAAA==.',
Si='Sinistral:BAAANQAECgIIAgAAAA==.Sinvyx:BAAANQAECgYIBQAAAA==.',
Sk='Skullchopper:BAAANQAECgUIBwABNQAECgkJMgAeAAsOAA==.',
Sl='Slise:BAAANQADCgIIAwAAAA==.',
Sm='Smithers:BAABNQAECn8yAAQVAAoKMxxhFACdAAAZAAYKzxlCjADIAQAiAAMKlBuUEADfAAAVAAIKNCFhFACdAAAAAA==.',
Sn='Snappycakes:BAAANQAECgEIAQAAAA==.Sneakybunny:BAABNQAECn89AAIpAAoKaAU4BQALAQApAAoKaAU4BQALAQAAAA==.',
So='Solarica:BAAANQAECgQICwAAAA==.Solciopath:BAAANQAECgcIBgABNQAECgkJJgAmAEkeAA==.Solómon:BAAANQAECgQIBQAAAA==.Sorab:BAAANQAECgIIAgAAAA==.Sorabjr:BAAANQAECgYIEAAAAA==.Sorin:BAAANQADCgYIBgABNQAECgcICwARAAAAAA==.Soulbreaker:BAABNQAECn8yAAMeAAkKCw6MIQBbAQAeAAkKCw6MIQBbAQAdAAEK6wcpfAAnAAAAAA==.Southy:BAAANQAECgYIEgAAAA==.',
Sp='Sparxs:BAAANQAECgUIDAAAAA==.Spookz:BAAANQAECgEIAQAAAA==.',
St='Starblunder:BAAANQAECgIIAgAAAA==.Storglen:BAAANQADCgUIBQAAAA==.Stormdeth:BAAANQADCgUICAAAAA==.Stormmystic:BAAANQAECgIIAgAAAA==.Stormwild:BAAANQADCgUJBQABNQAECgIIAgARAAAAAA==.Stylemonk:BAACNQAFFH8bAAIjAAgKfSIEAgB7AgAjAAgKfSIEAgB7AgA1AAQKf0QAAiMACgqrJp4AAIMDACMACgqrJp4AAIMDAAAA.',
Su='Sulfalloway:BAAANQAECggIEwAAAA==.Sumawfulot:BAABNQAECn8cAAIcAAgKRBw+ZABiAgAcAAgKRBw+ZABiAgAAAA==.Sunsparrow:BAAANQAECgUIAgAAAA==.',
Sw='Swankdave:BAAANQADCgcICQAAAA==.Sweetheal:BAAANQAECgYICwAAAA==.Swiftysarah:BAAANQAECgIIAgABNQAFFAYIEwAOAPwJAA==.',
Sy='Syraelia:BAAANQADCggICAAAAA==.Syvarris:BAABNQAECn86AAQIAAoKxR/5AgDxAgAIAAkKGyD5AgDxAgAEAAUKWQjTTwDtAAAbAAEKah0uRAFXAAAAAA==.',
['Sî']='Sîpher:BAABNQAECn8VAAQaAAoK0gyAKgByAQAaAAkKUwqAKgByAQAHAAcKBg//IAANAQAUAAEKAAD2UgBYAAAAAA==.',
Ta='Taeveren:BAABNQAECn8VAAMSAAcKLAcM5gDWAAASAAYKLAcM5gDWAAATAAEKAABAZABPAAAAAA==.Tamesßond:BAAANQAECgcIDwAAAA==.Tandaiff:BAAANQADCgYIBgAAAA==.Tanguo:BAAANQAECgUIBQAAAA==.Tanksnotanks:BAAANQADCgYJFAAAAA==.Tanleron:BAAANQADCgMIAwAAAA==.Tarayn:BAABNQAECn8rAAITAAkKsxyQFQBUAgATAAkKsxyQFQBUAgAAAA==.',
Te='Teacher:BAABNQAECn8WAAMFAAgKKxG8TACtAQAFAAgKKxG8TACtAQAGAAgKYAQ4cgD6AAAAAA==.Teagan:BAAANQADCgYIEwAAAA==.Teagn:BAAANQABCgUIBgAAAA==.Teliertei:BAAANQADCgYIBgABNQAECgoKLAAQAPcdAA==.Teloran:BAAANQAECgIIAgAAAA==.Tenac:BAAANQADCggIDgAAAA==.Teoritta:BAEBNQAECn8oAAMEAAkKKg7KOQCCAQAEAAcKug/KOQCCAQAIAAMK2Qp8DgBYAAAAAA==.Terllin:BAAANQADCgQIBAAAAA==.',
Th='Thelionheart:BAAANQAECgYICgAAAA==.Thelle:BAAANQAECgYICwABNQAFFAgIFQAdAGIdAA==.Thewhitelion:BAAANQAECgcIDQAAAA==.Thundermoo:BAAANQAECgIIAgAAAA==.',
Ti='Tigg:BAACNQAFFH8OAAMhAAYKTBDvBADEAQAhAAYKTBDvBADEAQAKAAEKAAAXPwAVAAA1AAQKfysAAyEACgoZIVsYAMcCACEACgoZIVsYAMcCAAMAAQoAAOTYAD0AAAAA.Tikifiki:BAAANQAECgYIEAAAAA==.Tilatank:BAAANQABCgMIAwABNQAECgoKKQAZAHskAA==.',
To='Tokin:BAAANQADCgYICgAAAA==.Toochill:BAAANQADCgEIAQAAAA==.Toodoo:BAAANQADCgIIAgABNQAECgoKMgAgAOgXAA==.Toshidot:BAACNQAFFH8QAAIZAAYKLxIMCgDJAQAZAAYKLxIMCgDJAQA1AAQKfyoAAhkACQqFIWEfAAcDABkACQqFIWEfAAcDAAAA.Totemtila:BAAANQAECgMIBwABNQAECgoKKQAZAHskAA==.Totendead:BAAANQABCgMIBQAAAA==.',
Tr='Translucent:BAABNQAECn8/AAIFAAkKKxLNNQATAgAFAAkKKxLNNQATAgAAAA==.Trazatra:BAABNQAECn8kAAMWAAoKIQ2qKgBYAQAWAAkK0Q2qKgBYAQAPAAcKmxbZDQA2AQAAAA==.Truckah:BAABNQAECn8pAAIcAAkKIQ+WZACYAQAcAAkKIQ+WZACYAQAAAA==.Tràvdog:BAABNQAECn8XAAIcAAgKVBDsmQDbAQAcAAgKVBDsmQDbAQAAAA==.',
Tu='Tunalongarms:BAAANQAECgQICAABNQAECgYICQARAAAAAA==.Tuonadari:BAAANQADCgUIDQAAAA==.Tuonai:BAABNQAECn8gAAMjAAcKaQ1rKQAWAQAjAAcKaQ1rKQAWAQAkAAMK/AH1LABWAAAAAA==.Tusknus:BAAANQAECgIIAgAAAA==.Tustone:BAAANQAECgUIDAAAAA==.',
Ty='Tylordis:BAAANQADCgYICgAAAA==.',
['Tý']='Týr:BAAANQAECgIIAgAAAA==.',
Ul='Ularin:BAAANQAECgYIBgAAAA==.Ultimatum:BAAANQAECgYIDwAAAA==.',
Un='Uncledaddy:BAAANQAECgUIBQAAAA==.',
Ur='Ursôc:BAAANQABCgQIAwABNQAFFAYIEwAOAPwJAA==.',
Us='Usodead:BAAANQADCgQIBAAAAA==.Usosquishy:BAAANQAECgcIEgAAAA==.',
Va='Vader:BAAANQADCgIIAgABNQAECgIIAwARAAAAAA==.Vaelena:BAAANQADCgUIBQAAAA==.Vahla:BAAANQAECgEIAQABNQAECgoKPAAdAJAaAA==.Vailyt:BAAANQAECgYIDwAAAA==.Valkuridk:BAACNQAFFH8eAAMhAAcKeyYaAQCCAgAhAAcKYiYaAQCCAgADAAUKJSYKAwARAgA1AAQKfz4AAyEACgrSJiEBAH8DACEACgrDJiEBAH8DAAMACArtJRglAKsCAAAA.Valorlight:BAAANQAECgIIAgAAAA==.Vandellor:BAAANQADCgQIBAABNQAECgoKIgAUAHMlAA==.Vandy:BAABNQAECn8gAAMXAAkK4xYFSwBEAgAXAAkKARUFSwBEAgAJAAQKqRbGEgD7AAAAAA==.',
Ve='Vedo:BAACNQAFFH8PAAMEAAYKkhNDDQDGAAAEAAUKRxFDDQDGAAAbAAEKdRquJABfAAA1AAQKfycAAgQACgqYHpwIAJgCAAQACgqYHpwIAJgCAAAA.Vedora:BAABNQAECn8fAAIYAAkKyBBpLADDAQAYAAkKyBBpLADDAQAAAA==.Velf:BAAANQADCgEIAQAAAA==.Vestiege:BAAANQABCgYIBwAAAA==.Vetro:BAAANQAECgIIAgAAAA==.Vexalyah:BAAANQAECgUIBAAAAA==.Vexy:BAAANQAECgQIBAAAAA==.',
Vi='Vinland:BAAANQADCgYIEgAAAA==.Vinsmokesanj:BAAANQADCgQIBAAAAA==.Virelith:BAAANQAECgYICwAAAA==.Virulent:BAAANQAECgEIAQABNQAECggIHgAYALcaAA==.Visell:BAAANQAECgEIAQAAAA==.Vissarion:BAAANQAECgIIAgAAAA==.',
Vl='Vladak:BAAANQAECgcIDgAAAA==.',
Vo='Voc:BAAANQAECggIEgAAAA==.Voz:BAAANQAECgMIAgABNQAECggIHgAYALcaAA==.',
Vu='Vulkin:BAAANQAECgIIAwAAAA==.',
Vv='Vv:BAABNQAECn88AAIbAAoK5SBXEgBXAwAbAAoK5SBXEgBXAwAAAA==.',
Vy='Vyridiondk:BAAANQAECgUIDAAAAA==.Vyx:BAAANQAECgUICgAAAA==.',
Wa='Waggi:BAAANQAECgQIBQAAAA==.Wallbeef:BAAANQAECgIIAgAAAA==.Waymán:BAAANQAECgQIBgAAAA==.',
We='Weebjones:BAAANQADCgQIBAAAAA==.Wegberto:BAAANQADCggICAAAAA==.',
Wh='Whuh:BAAANQAECgUIBQAAAA==.',
Wu='Wumply:BAACNQAFFH8OAAIYAAUKyQpYCQBuAQAYAAUKyQpYCQBuAQA1AAQKfyMAAhgACQqAFCohAC4CABgACQqAFCohAC4CAAAA.',
['Wà']='Wàyman:BAAANQAECgQICAAAAA==.',
['Wä']='Wäyman:BAABNQAECn86AAILAAoK6RPFDgDuAQALAAoK6RPFDgDuAQAAAA==.',
Xa='Xaranthia:BAABNQAECn8UAAIdAAkKOAmhQQCzAQAdAAkKOAmhQQCzAQAAAA==.',
Xe='Xenra:BAAANQAECgEIAQAAAA==.',
Xm='Xmcdizzle:BAABNQAECn8iAAIOAAkKYxfMxgD3AQAOAAkKYxfMxgD3AQAAAA==.',
Xy='Xylarra:BAABNQAECn88AAMdAAoKkBqJFwAlAgAdAAoKkBqJFwAlAgAeAAIK/BcdXwB1AAAAAA==.',
Ya='Yautja:BAABNQAECn80AAIEAAoKkhViLADoAQAEAAoKkhViLADoAQAAAA==.Yazule:BAABNQAECn8dAAIFAAgK9xjYVgANAgAFAAgK9xjYVgANAgAAAA==.',
Yo='Yodawg:BAABNQAECn8fAAIKAAgKiRhNPgAIAgAKAAgKiRhNPgAIAgAAAA==.Yoruba:BAAANQADCgMIAwABNQAECgcIFwAWAFIMAA==.',
Yu='Yuenna:BAAANQADCggICAABNQAECgoKLAAQAPcdAA==.',
Za='Zairroth:BAAANQADCgYICQAAAA==.Zamali:BAABNQAECn8hAAIKAAgKLAueYgBnAQAKAAgKLAueYgBnAQAAAA==.Zantris:BAAANQADCgUIBwABNQAECgQIBQARAAAAAA==.Zartella:BAAANQAECgUICQABNQAECgYICwARAAAAAA==.Zaxon:BAAANQAECgMIBQAAAA==.',
Ze='Zendraza:BAABNQAECn8iAAIPAAkKmARuEAACAQAPAAkKmARuEAACAQAAAA==.Zephyrion:BAACNQAFFH8QAAIKAAQKJRBcFgD7AAAKAAQKJRBcFgD7AAA1AAQKfzMAAgoACgp+G4IhAKgCAAoACgp+G4IhAKgCAAE1AAQKCgopABMAyA0A.Zepplin:BAABNQAECn8eAAIIAAkKWBEbBQDXAQAIAAkKWBEbBQDXAQAAAA==.Zerenity:BAAANQAECgUIBwAAAA==.Zetro:BAABNQAECn88AAITAAoKlQzrGwBbAQATAAoKlQzrGwBbAQAAAA==.',
Zr='Zreydyn:BAAANQADCgcIHAAAAA==.',
Zu='Zuma:BAABNQAECn82AAINAAoKgxb1BgAVAgANAAoKgxb1BgAVAgAAAA==.Zuraxxus:BAAANQABCgMIAwAAAA==.',
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
