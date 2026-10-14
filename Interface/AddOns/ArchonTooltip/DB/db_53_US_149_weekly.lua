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

local lookup = {'Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Hunter-BeastMastery','Shaman-Restoration','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','Warlock-Affliction','DeathKnight-Blood','DeathKnight-Unholy','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','Paladin-Protection','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Priest-Shadow','Monk-Brewmaster','Monk-Mistweaver','Druid-Restoration','DemonHunter-Havoc','Shaman-Elemental','Shaman-Enhancement','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Devourer','Priest-Holy','Hunter-Survival','Druid-Guardian','Priest-Discipline',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIBQAAAA==.Abadizzoo:BAAANQAECggIEAAAAA==.Abeyancë:BAABNQAECn8sAAMBAAkK0hnMWwCBAgABAAkK0hnMWwCBAgACAAIK8RKIAQFwAAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQABCgIIAgAAAA==.Airwrecka:BAABNQAECn8tAAIDAAkKIxyoGwDpAgADAAkKIxyoGwDpAgAAAA==.Aite:BAAANQAECgMIAwAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAEBNQAECn8eAAIBAAgKRRPeiQAOAgABAAgKRRPeiQAOAgABNQAECgkJFQAFAD4cAA==.Artvandelay:BAAANQAECgQIBgABNQAECggIJwAGAO0fAA==.',
As='Asukà:BAABNQAECn8gAAIHAAgKSBtqQABcAgAHAAgKSBtqQABcAgAAAA==.',
Au='Auchenile:BAABNQAECn8kAAMIAAgKSxZjEABPAgAIAAgKSxZjEABPAgAJAAMKzglrQACYAAAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICAAAAA==.',
Av='Avanoura:BAAANQADCggIDQABNQAECgUICQAEAAAAAA==.',
['Aé']='Aéd:BAAANQADCgcICwABNQAECgYICwAEAAAAAA==.',
Ba='Barkthas:BAAANQAECgcIEAAAAA==.',
Be='Bellarg:BAABNQAECn8eAAMKAAkKuRCgWgBEAgAKAAkKuRCgWgBEAgALAAEKzQfufAAvAAAAAA==.Belobog:BAAANQAECgYIBQAAAA==.Belyn:BAAANQAECgUIEAAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgUIBwAAAA==.Bloodadinz:BAAANQADCgcIBwAAAA==.',
Bo='Bonedaddy:BAABNQAECn8UAAIMAAcK9ROqPwDEAQAMAAcK9ROqPwDEAQAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAUIDwABALEkAA==.Bro:BAABNQAECn8hAAQKAAkKOBh2XgA5AgAKAAgKfhd2XgA5AgALAAIK6hjdTQCUAAANAAEKRhBiKQBFAAAAAA==.Brolich:BAABNQAECn8uAAMOAAkKFxT7PQAHAgAOAAkKFxT7PQAHAgAPAAEKlQpT3wAyAAABNQAECgkJIQAKADgYAA==.Broo:BAAANQAECgUICgABNQAECgkJIQAKADgYAA==.Brooak:BAAANQAECggIEAABNQAECgkJIQAKADgYAA==.Brother:BAAANQAECgUIBgABNQAECgkJIQAKADgYAA==.Brozeit:BAAANQAECggIDQABNQAECgkJIQAKADgYAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAABNQAECn8VAAIQAAgKtx3bGwCbAgAQAAgKtx3bGwCbAgAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFH8eAAMRAAcKdhnUAgD4AAASAAYKIhsRDQAKAgARAAMKyRTUAgD4AAA1AAQKfygABBIACQrQJM8xACcDABIACQo/JM8xACcDABMAAwqfIT8GAPsAABEAAQosJaw8AEoAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEIAQABNQAFFAIIBwAUAAUfAA==.',
Cl='Clare:BAABNQAECn8aAAIUAAkK3h/sDADLAgAUAAkK3h/sDADLAgAAAA==.Cloúd:BAAANQAECgQICgAAAA==.',
Da='Daddydimes:BAABNQAECn8dAAIVAAgKvhr3HQBAAgAVAAgKvhr3HQBAAgAAAA==.Darilol:BAAANQADCgYIBgABNQAECgYICwAEAAAAAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECn8mAAIOAAgKfSSZDQBCAwAOAAgKfSSZDQBCAwAAAA==.Demiize:BAABNQAECn8kAAIRAAkKkBr6AwD3AgARAAkKkBr6AwD3AgAAAA==.Demize:BAABNQAECn8uAAIGAAkKQRlJJgD9AgAGAAkKQRlJJgD9AgAAAA==.Demonflame:BAAANQAECgUIBQAAAA==.Demíze:BAAANQAECgQIBgAAAA==.Deshield:BAABNQAECn8lAAMWAAkKMyOwAwBbAwAWAAgKPyawAwBbAwAXAAkKbiH5FwBXAwAAAA==.Deus:BAABNQAECn8YAAISAAgKmAz/0wDcAQASAAgKmAz/0wDcAQAAAA==.Dewry:BAABNQAECn8XAAIYAAgKIx5eFwCbAgAYAAgKIx5eFwCbAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECn8vAAMZAAkK4yPiAQCaAwAZAAkK4yPiAQCaAwAVAAIK5xkDXQBnAAAAAA==.',
Di='Diemertz:BAAANQADCgQIBQAAAA==.Dingis:BAAANQADCggIDAABNQAECgYICwAEAAAAAA==.Divine:BAAANQAECgcICwABNQAECgkJJAAaALETAA==.Dizzo:BAABNQAECn8fAAIPAAcKOx3GPgAhAgAPAAcKOx3GPgAhAgAAAA==.',
Do='Doink:BAABNQAECn8aAAIKAAgKOxTpZwAgAgAKAAgKOxTpZwAgAgABNQAECgkJNAAbACsiAA==.Donnajuan:BAABNQAECn8ZAAICAAcK3Rz/QABeAgACAAcK3Rz/QABeAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIGAAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAUIEwAIABwiAA==.',
El='Elimere:BAABNQAECn8pAAIYAAkKWwzjKQDVAQAYAAkKWwzjKQDVAQAAAA==.Elvarg:BAABNQAECn8rAAIIAAgKnh51CgDCAgAIAAgKnh51CgDCAgAAAA==.Elywen:BAABNQAECn8sAAIGAAkK2SETHQAiAwAGAAkK2SETHQAiAwAAAA==.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQAECgIIAgAAAA==.',
Ex='Executè:BAAANQAECggIAgABNQAECggIJQAcADIhAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAYIEQAUALgeAA==.Finke:BAAANQAECgQIDQAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAcIFwAUANAbAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAAANQAECgcIDgAAAA==.',
Fr='Free:BAAANQAECgUIEAABNQAECgYIBgAEAAAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECn8uAAISAAkKaxB+ogA7AgASAAkKaxB+ogA7AgAAAA==.',
Gh='Ghostshadows:BAABNQAECn8iAAIQAAcK1CTAEQDsAgAQAAcK1CTAEQDsAgAAAA==.',
Gi='Gigazapper:BAABNQAECn8ZAAIdAAcKBRAvgQCeAQAdAAcKBRAvgQCeAQABNQAFFAIIBwAUAAUfAA==.Gizzlit:BAABNQAECn8bAAIeAAgK6BTSEgA5AgAeAAgK6BTSEgA5AgAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBQABNQAFFAYIDgAcAGghAA==.Gofetch:BAABNQAECn8lAAIGAAgKphwyPACzAgAGAAgKphwyPACzAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECn8nAAIGAAgK7R9VNgDFAgAGAAgK7R9VNgDFAgAAAA==.',
Gs='Gson:BAAANQAECggIDgAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECgkJFwAQAPkSAA==.Hakka:BAABNQAECn8XAAMQAAkK+RJ6PADZAQAQAAgK2gx6PADZAQAfAAcKJhMtIQDAAQAAAA==.Hal:BAAANQADCgYICwABNQAECgYIEwAEAAAAAA==.Hallack:BAAANQAECgYIEwAAAA==.',
He='Healingkiss:BAAANQAECgIIAwAAAA==.',
Hi='Hikingboots:BAABNQAECn8gAAIdAAcKawxSkQB1AQAdAAcKawxSkQB1AQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECn8gAAMSAAgKQB7IhgBwAgASAAgKQB7IhgBwAgARAAIKvQfANgBfAAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICgABNQAECgUIBgAEAAAAAA==.',
Il='Illani:BAAANQAECgEJAwAAAA==.Ilyanna:BAABNQAECn8mAAMLAAkK4RjiBwCDAgALAAgKCBviBwCDAgAKAAcKbwhhnQCXAQAAAA==.',
Im='Im:BAACNQAFFH8TAAMgAAcKeiG6AwBEAgAgAAYKXiC6AwBEAgAGAAEK6SVYLABuAAA1AAQKfywAAyAACQoDJl0EAI8DACAACQoDJl0EAI8DAAYAAQr0Jdg7AWIAAAAA.Immagical:BAAANQAECgEIAQAAAA==.Imscary:BAAANQAECgQIBQAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAAANQAECgQICwAAAA==.',
Je='Jenyaa:BAAANQADCggIEQAAAA==.',
Jh='Jhops:BAABNQAECn8nAAIdAAgKOB1uQQBtAgAdAAgKOB1uQQBtAgAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.',
Ke='Keju:BAAANQAECgEJAQAAAA==.Kerrigan:BAABNQAECn8lAAMhAAkKGBu8IwAnAgAhAAgKAR68IwAnAgAcAAUKGxDwVwAjAQAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJIwASAL4iAA==.Kookluhh:BAAANQAECgUIBwABNQAECgkJIwASAL4iAA==.Kozand:BAAANQADCgQIBwABNQAECgYICwAEAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgEIAQAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECggIJAAIAEsWAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAAANQAECgcIEQAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAYIEQAUALgeAA==.',
Ll='Llynryn:BAAANQAECgUICQAAAA==.',
Lo='Locktuah:BAAANQAECgQIBwABNQAECgYICwAEAAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECn8qAAISAAkK0iEiIwBQAwASAAkK0iEiIwBQAwABNQAFFAcIGgAhAMUfAA==.Magicmanzz:BAAANQAECgUIDwAAAA==.Magnifuso:BAAANQAECgUIDQAAAA==.Maguapa:BAAANQAECgUICgAAAA==.Malgata:BAAANQAECgQIDAAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECn8hAAIBAAkKBxnTYgBuAgABAAkKBxnTYgBuAgAAAA==.Mastab:BAABNQAECn8oAAMCAAkKgxmLMQCdAgACAAkKgxmLMQCdAgABAAIK4AwFZQF2AAAAAA==.',
Mc='Mchammerdin:BAABNQAECn8dAAMBAAgKvxY/hQAYAgABAAgKvxY/hQAYAgAUAAIK3hIjXwBbAAAAAA==.',
Me='Meat:BAABNQAECn8jAAMFAAgKvxxLCgA0AgAFAAcKvxxLCgA0AgAcAAEKAACukQAzAAAAAA==.',
Mi='Mikio:BAABNQAECn8ZAAIDAAcKagpWXgBTAQADAAcKagpWXgBTAQAAAA==.Milinka:BAABNQAECn8pAAIiAAkKlBy8IgDgAgAiAAkKlBy8IgDgAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECgkJMAAhAAwjAA==.',
Mo='Moiryn:BAAANQADCgIIAgAAAA==.',
My='Myshaman:BAABNQAECn8bAAMHAAcKmxT9bADBAQAHAAcKmxT9bADBAQAdAAEKQAkXNgExAAAAAA==.',
Na='Navillus:BAACNQAFFH8TAAIIAAUKHCILAgAOAgAIAAUKHCILAgAOAgA1AAQKf4AAAwgACQpkJk8AAPgDAAgACQpkJk8AAPgDAAkACQqxH8sHACkDAAAA.',
No='Noxi:BAAANQAECgYIDQAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECggIIwAUAOUkAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECgkJJQAWADMjAA==.',
Op='Ophindis:BAABNQAECn8iAAMOAAgKQx6LHwC0AgAOAAgKQx6LHwC0AgAPAAEKcQrv3gAyAAAAAA==.',
Os='Osten:BAAANQAECgUIDQAAAA==.',
Pa='Pagoda:BAABNQAECn8kAAMaAAkKsROiFAAtAgAaAAkKsROiFAAtAgAVAAQKNhYFRwDhAAAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECn8ZAAIGAAYKyyHEfAARAgAGAAYKyyHEfAARAgAAAA==.',
Pi='Pintsize:BAAANQABCgcICQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Pr='Praystation:BAAANQAECgIIAgAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECn8iAAIXAAkKqRZ9PgDNAgAXAAkKqRZ9PgDNAgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAEAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECn8wAAMBAAkKpReEXQB8AgABAAkKpReEXQB8AgAUAAYKLAkXOwATAQAAAA==.Rennx:BAACNQAFFH8eAAIDAAcK8BugAwB/AgADAAcK8BugAwB/AgA1AAQKfyEAAgMACQq+Jb0FAKgDAAMACQq+Jb0FAKgDAAAA.Reznik:BAABNQAECn8nAAIOAAgKxBlzQQD1AQAOAAgKxBlzQQD1AQAAAA==.',
Ri='Rika:BAAANQAECgEIAQAAAA==.Ringmasta:BAAANQAECgIIAwAAAA==.Riot:BAABNQAECn8tAAIGAAkK5BpfNwDCAgAGAAkK5BpfNwDCAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAABNQAECn8aAAMfAAYK2xuTGQAKAgAfAAYK2xuTGQAKAgAQAAEKbxXRmgA+AAAAAA==.',
['Rè']='Rènza:BAAANQAECggICgAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECggIHQABAJAZAA==.Saphia:BAECNQAFFH8RAAIUAAYKuB4rAgAYAgAUAAYKuB4rAgAYAgA1AAQKfysAAhQACQpvJV4BAMsDABQACQpvJV4BAMsDAAAA.Saphyr:BAECNQAFFH8IAAIOAAYKyBXsBgDzAQAOAAYKyBXsBgDzAQA1AAQKfxcAAw4ACQpNH0sSABkDAA4ACQpNH0sSABkDAA8AAwquCle0AIIAAAE1AAUUBggRABQAuB4A.',
Sb='Sblakedragon:BAAANQAECgYIBwAAAA==.',
Sc='Scarydude:BAABNQAECn8VAAIhAAgK2RYEJwAJAgAhAAgK2RYEJwAJAgAAAA==.',
Se='Sevrin:BAABNQAECn8rAAMVAAkKGB4UEgDKAgAVAAkKGB4UEgDKAgAZAAEKAAA0MAA3AAAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAAANQAECgQICwABNQAECgYIBQAEAAAAAA==.Sheesh:BAABNQAECn80AAMbAAkKKyIlCABAAwAbAAkKKyIlCABAAwADAAQKnRa7agAcAQAAAA==.Shinru:BAABNQAECn80AAMCAAkKIyLIDABhAwACAAkKIyLIDABhAwABAAMK7xU4MwHGAAAAAA==.Shrikedk:BAAANQADCgIIAgABNQAECgkJGgAUAN4fAA==.',
Si='Sickdayze:BAABNQAECn8eAAICAAgKZh7aJwDHAgACAAgKZh7aJwDHAgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECggIHgACAGYeAA==.Sickntired:BAAANQADCgMJAwABNQAECggIHgACAGYeAA==.Sicktides:BAAANQADCgYICAABNQAECggIHgACAGYeAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECn8eAAIHAAcKLRXgewCUAQAHAAcKLRXgewCUAQAAAA==.',
Sn='Snaffu:BAAANQAECgYICgAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAABNQAECn8kAAMbAAkK/CM1AwCUAwAbAAkK/CM1AwCUAwADAAEKAADNpABLAAABNQAFFAUIDwABALEkAA==.Sophie:BAACNQAFFH8PAAIBAAUKsSSgBwDQAQABAAUKsSSgBwDQAQA1AAQKfzAAAgEACQptJkgHAL8DAAEACQptJkgHAL8DAAAA.Sophisticate:BAABNQAECn8kAAIjAAkKFSB8AQBVAwAjAAkKFSB8AQBVAwABNQAFFAUIDwABALEkAA==.Sophiz:BAABNQAECn8hAAIhAAkKux3QDgD9AgAhAAkKux3QDgD9AgABNQAFFAUIDwABALEkAA==.Sophlax:BAABNQAECn8lAAIiAAkKYCLdCQByAwAiAAkKYCLdCQByAwABNQAFFAUIDwABALEkAA==.Sophs:BAABNQAECn8cAAMHAAYKWxUWfgCNAQAHAAYKWxUWfgCNAQAdAAUKkBn8mQBgAQABNQAFFAUIDwABALEkAA==.Sophz:BAABNQAECn8YAAIPAAgKiyH9GAD2AgAPAAgKiyH9GAD2AgABNQAFFAUIDwABALEkAA==.Sox:BAABNQAECn8tAAIkAAkKtCVoAQDQAwAkAAkKtCVoAQDQAwAAAA==.',
Sp='Spicynoodle:BAABNQAECn8kAAIGAAkKaxsNOwC3AgAGAAkKaxsNOwC3AgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAABNQAECn8dAAIVAAgKJh4YFACzAgAVAAgKJh4YFACzAgAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECn8cAAISAAgK3RR2rAAoAgASAAgK3RR2rAAoAgAAAA==.',
Su='Sua:BAACNQAFFH8ZAAIXAAcKshI5CAAvAgAXAAcKshI5CAAvAgA1AAQKfyIAAhcACQoDIBQwAPwCABcACQoDIBQwAPwCAAAA.Suksuksuk:BAAANQABCgQICAAAAA==.Supergogeta:BAABNQAECn8gAAMbAAgKVBV8JgDqAQAbAAgKVBV8JgDqAQADAAUKKg9jagAdAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEgAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECn8mAAIXAAgKvh7EVgCEAgAXAAgKvh7EVgCEAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgIIBAAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgQIBQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgUIBgAAAA==.Thrayne:BAAANQABCgMIAwAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECggIIgAOAEMeAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECn8dAAIlAAgK9BbaBQA7AgAlAAgK9BbaBQA7AgAAAA==.',
Tw='Twofow:BAAANQAECgQICAAAAA==.',
Ty='Tyranis:BAEBNQAECn8VAAIFAAkKPhx/BAD7AgAFAAkKPhx/BAD7AgAAAA==.Tyê:BAABNQAECn8gAAMJAAkKlBUKGgAgAgAJAAgKTRUKGgAgAgAIAAEKAAAuPQAxAAAAAA==.',
['Té']='Témalabécane:BAACNQAFFH8HAAISAAQKshlLJwBFAQASAAQKshlLJwBFAQA1AAQKfyEAAhIACQqOILIwACoDABIACQqOILIwACoDAAAA.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUJBwAAAA==.Valériana:BAAANQADCgIIAgAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vi='Visable:BAAANQAECgUIBwAAAA==.',
Vo='Voiddemon:BAAANQADCgEIAQAAAA==.Voltage:BAAANQAECgQIDQABNQAECgYIGQAGAMshAA==.',
Vu='Vulgnash:BAABNQAECn80AAIPAAkK4yJABwCKAwAPAAkK4yJABwCKAwAAAA==.Vult:BAABNQAECn8qAAIMAAkKgxyrHQCZAgAMAAkKgxyrHQCZAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Welgo:BAAANQAECggIDgAAAA==.Welmage:BAAANQAECgIIAgABNQAECggIDgAEAAAAAA==.',
Wi='Wickeddemon:BAAANQAECgIIAgAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECn8mAAISAAgKMB8lTQDnAgASAAgKMB8lTQDnAgAAAA==.',
Xe='Xerra:BAABNQAECn8sAAIhAAkK4h+4CgAvAwAhAAkK4h+4CgAvAwAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYICgAAAA==.Yemoja:BAAANQAECgQIBAAAAA==.',
Yi='Yikes:BAAANQADCgQIBAABNQAECgkJNAAbACsiAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAAANQAECgYICwAAAA==.',
Ze='Zeit:BAAANQAECggIEgABNQAECgkJIQAKADgYAA==.Zelgie:BAABNQAECn8mAAICAAgKYhsfLwCnAgACAAgKYhsfLwCnAgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.Zin:BAAANQADCgYIDAAAAA==.',
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
