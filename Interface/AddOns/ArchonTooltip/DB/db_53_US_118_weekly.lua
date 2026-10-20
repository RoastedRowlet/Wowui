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

local lookup = {'Warrior-Arms','DeathKnight-Blood','Unknown-Unknown','Shaman-Enhancement','DemonHunter-Havoc','Druid-Feral','Paladin-Retribution','Shaman-Restoration','Warlock-Destruction','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Warrior-Protection','Hunter-BeastMastery','Priest-Holy','Shaman-Elemental','Priest-Shadow','Druid-Restoration','DeathKnight-Frost','Hunter-Survival','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Assassination','Paladin-Holy','Hunter-Marksmanship','DeathKnight-Unholy',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=53,date='2026-10-20',data={Ai='Aitharlis:BAAANQAECgEIAgAAAA==.',
Al='Alexya:BAAANQADCgYIBgAAAA==.Alphahawk:BAABNQAECn80AAIBAAoKrxFFdQA1AgABAAoKrxFFdQA1AgAAAA==.',
An='Antichamplol:BAAANQAECgEIAQAAAA==.',
Ap='Applepie:BAAANQAECgIIBwABNQAECgkJHgACABIfAA==.',
Ar='Aralia:BAAANQAECgUIBgABNQABCgIIAgADAAAAAA==.Aramis:BAAANQAECgQIBQABNQABCgIIAgADAAAAAA==.Arathram:BAABNQAECn8XAAIEAAoKLRMBFAApAgAEAAoKLRMBFAApAgABNQABCgIIAgADAAAAAA==.',
As='Askaria:BAAANQAECgMIAwABNQAFFAUICQAFAOoGAA==.Asmoday:BAAANQADCgYIDAABNQAECgUICwADAAAAAA==.Asunawa:BAAANQAECgMIBQAAAA==.',
Au='Aundarr:BAAANQAECgIJAwABNQAECgUICwADAAAAAA==.',
Ba='Balvos:BAAANQAFFAIIAgAAAA==.Bat:BAABNQAECn8WAAIGAAkKLyEGAQBQAgAGAAkKLyEGAQBQAgAAAA==.',
Be='Beradok:BAAANQAECgQIBQAAAA==.',
Bl='Bladerazor:BAAANQADCgEIAQAAAA==.',
Bo='Boomster:BAAANQAFFAgIBAAAAA==.',
Br='Bri:BAAANQAECgYIEwAAAA==.',
Ca='Calixta:BAABNQAECn8kAAIHAAoKvSBKIwA3AwAHAAoKvSBKIwA3AwAAAA==.Camel:BAAANQADCgQIAgAAAA==.',
Ce='Ceolen:BAAANQAECgQIBAAAAA==.',
Ch='Cherrypie:BAAANQAECgQIBAABNQAECgkJHgACABIfAA==.Chiffonpie:BAAANQADCgYIBgAAAA==.',
Co='Coquette:BAABNQAECn8bAAIBAAcK2w5LtACaAQABAAcK2w5LtACaAQAAAA==.',
Cp='Cptbarnacles:BAAANQAECggIDgAAAA==.',
Cr='Crab:BAAANQADCgMIAwABNQAECgoKOQAIACYfAA==.Cranberrypie:BAAANQAECggIDwABNQAECgkJHgACABIfAA==.Criscomaster:BAABNQAECn8iAAIJAAgKTxHNFADIAQAJAAgKTxHNFADIAQAAAA==.',
Cy='Cylla:BAABNQAECn86AAIKAAoKWiEXAgBaAwAKAAoKWiEXAgBaAwAAAA==.',
Da='Dazãr:BAAANQADCgUIBgAAAA==.',
De='Dethbycrisco:BAAANQADCgIIBAAAAA==.',
Di='Dilfdormu:BAACNQAFFH8LAAILAAQKUQfcDwD6AAALAAQKUQfcDwD6AAA1AAQKfzUABAsACgqzGJYTAHQCAAsACgqzGJYTAHQCAAwAAQoAAOBBACYAAA0AAQpaBmkoACAAAAAA.',
Do='Donkey:BAAANQAECgIIBQAAAA==.Doson:BAABNQAECn8uAAIOAAkKwxuSDwBpAgAOAAkKwxuSDwBpAgAAAA==.',
Dr='Dratak:BAACNQAFFH8pAAIPAAgKgRsHAABSAgAPAAgKgRsHAABSAgA1AAQKf0sAAg8ACgr4JRIAABQEAA8ACgr4JRIAABQEAAAA.Dratalt:BAABNQAFFH8TAAIPAAUKTxtCAACFAQAPAAUKTxtCAACFAQABNQAFFAgIKQAPAIEbAA==.Dreadfang:BAAANQADCgQIBAAAAA==.',
Ei='Eisdrameir:BAAANQADCgYICQAAAA==.',
El='Elitzai:BAAANQAECgcIEAAAAA==.Elspethstorm:BAAANQAECgUIEAAAAA==.',
Em='Emeralda:BAAANQAECgQIDAAAAA==.',
Ev='Evalueate:BAAANQAECgUJBgAAAA==.',
Fe='Feets:BAAANQAECgUICAABNQAECgoKIwAQALUfAA==.',
Fr='Frocknor:BAAANQAECgQICQAAAA==.',
Fu='Fuki:BAAANQAECgEIAQAAAA==.',
Ga='Galumian:BAACNQAFFH8uAAIRAAcKCyXwAADqAgARAAcKCyXwAADqAgA1AAQKfzYAAhEACgrgIRsFAKADABEACgrgIRsFAKADAAAA.',
Ge='Gergo:BAAANQADCgUICgAAAA==.Geron:BAAANQADCgYIBgABNQAECgoKJAAHAL0gAA==.',
Gr='Grasswonder:BAAANQADCgYIBgAAAA==.',
Gu='Guy:BAACNQAFFH8fAAILAAcKVxT9BAAdAgALAAcKVxT9BAAdAgA1AAQKfygAAgsACgppHkIPALQCAAsACgppHkIPALQCAAE1AAEKAwgDAAMAAAAA.',
Ha='Hailren:BAAANQAECgMIAwAAAA==.Haradali:BAABNQAECn8VAAISAAcKRg/XcgDIAQASAAcKRg/XcgDIAQAAAA==.',
Ho='Hondoe:BAAANQAECgUICwAAAA==.Hordehound:BAAANQADCgQIBAAAAA==.',
Ja='Jasminetea:BAABNQAECn8tAAMRAAoKcBosNwCLAgARAAoKcBosNwCLAgATAAEKAADbcwA+AAAAAA==.',
Ji='Jim:BAAANQAECgEIAgAAAA==.',
Ju='Judgment:BAAANQAECgUIBAABNQAECggIBgADAAAAAA==.',
Ka='Kairne:BAAANQAECgQIBQAAAA==.',
Ki='Kittybutt:BAAANQAECgYICwABNQAECgoKIwAQALUfAA==.',
Kr='Krizara:BAAANQAECgEIAQABNQAECgQICQADAAAAAA==.Kroth:BAABNQAECn83AAIUAAoKJg1cKwDDAQAUAAoKJg1cKwDDAQAAAA==.',
Ku='Kubfury:BAAANQAECgIIAgAAAA==.',
Le='Lediah:BAAANQAECgEIAwAAAA==.',
Li='Liilith:BAAANQADCgQIBAAAAA==.Lillia:BAABNQAECn8hAAMCAAkKBxnmBwC6AQACAAgKJRnmBwC6AQAVAAUKPxUJXQA0AQAAAA==.Lily:BAABNQAECn8bAAMBAAgKhxV3OQA0AQABAAgKhxV3OQA0AQAPAAIKlA0wOgBhAAAAAA==.Limparrow:BAAANQADCgUIDwAAAA==.',
Ln='Lnav:BAAANQADCgUIBgAAAA==.',
Lu='Lunaci:BAABNQAECn8bAAIMAAcKlB2HEQA7AgAMAAcKlB2HEQA7AgAAAA==.',
Ma='Madyn:BAAANQAECgEIAwAAAA==.Magnusson:BAABNQAECn8dAAIPAAcKSBntEQAIAgAPAAcKSBntEQAIAgAAAA==.Masutado:BAABNQAECn8iAAIKAAoKABQ1CgAoAgAKAAoKABQ1CgAoAgAAAA==.Maven:BAAANQAECgYICwAAAA==.Mayernnaise:BAAANQAECgEIAgAAAA==.',
Me='Mellitha:BAAANQAECgQJBgAAAA==.',
Mi='Misfortune:BAAANQAECgIIAgABNQAECgoKJAAHAL0gAA==.Mitsy:BAAANQADCgUIBQABNQAECggIGwABAIcVAA==.',
Mo='Montipython:BAAANQAECggICwAAAA==.Moons:BAABNQAECn88AAMQAAkKfSTQHAAkAwAQAAkKfSTQHAAkAwAWAAYKMhoCCQC0AQABNQAFFAUICQAFAOoGAA==.',
Mu='Munco:BAABNQAECn82AAIFAAoKyiAnDABKAwAFAAoKyiAnDABKAwAAAA==.Muncola:BAAANQAECgEIAwABNQAECgoKNgAFAMogAA==.Muncolito:BAAANQADCgEIAQABNQAECgoKNgAFAMogAA==.',
No='Notker:BAABNQAECn8dAAIRAAcKyxGLeQCuAQARAAcKyxGLeQCuAQAAAA==.',
Os='Osrs:BAAANQAECgYICQAAAA==.',
Pa='Pandorra:BAAANQADCgYICwAAAA==.Papaj:BAAANQABCggIEQAAAA==.Pasteurmoon:BAAANQAECgQIEQAAAA==.',
Pe='Peepingpanda:BAAANQADCgYIDQAAAA==.Penne:BAAANQADCgYIEwAAAA==.',
Pi='Pizzapie:BAABNQAECn8eAAMCAAkKEh83HADNAgACAAkKEh83HADNAgAVAAEKAABrsQAvAAAAAA==.',
Ra='Raffine:BAAANQADCgUICAAAAA==.Rango:BAAANQADCgQIBAAAAA==.',
Re='Rennik:BAABNQAECn85AAQXAAoKMyRfBgBLAgAXAAoKtCJfBgBLAgAJAAQKyiSEGgCYAQAYAAEKAABcJwBOAAAAAA==.Revenant:BAAANQAECgEIAQAAAA==.',
['Rú']='Rúnil:BAAANQADCggIEgAAAA==.',
Sa='Saeris:BAAANQADCgUIBQAAAA==.Sanise:BAAANQADCggIGAAAAA==.',
Sc='Scorewin:BAEBNQAECn8sAAIZAAkKViICAwBAAwAZAAkKViICAwBAAwAAAA==.',
Se='Seral:BAAANQADCgcIBwAAAA==.',
Sh='Shankdela:BAABNQAECn8XAAIaAAkKYwyTHgDcAAAaAAkKYwyTHgDcAAAAAA==.',
Si='Sinappi:BAABNQAECn8dAAIOAAcKnRoeFQAWAgAOAAcKnRoeFQAWAgAAAA==.Siñ:BAABNQAECn8nAAIaAAgKDgmRCgB6AQAaAAgKDgmRCgB6AQAAAA==.',
Sk='Skeetshootah:BAAANQAECgQICAAAAA==.Skunkstomper:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Skunkstömper:BAAANQAECgEIAgAAAA==.Skùnkstomper:BAAANQAECgEIAQAAAA==.Skúnkstomper:BAAANQAECgEIAQAAAA==.Skûnkstomper:BAAANQABCgIIAgABNQAECgEIAQADAAAAAA==.',
Sl='Slowbadon:BAABNQAECn8ZAAMbAAcKeQ4KigB+AQAbAAcKeQ4KigB+AQAHAAQKpQziMgHOAAAAAA==.',
St='Stakkzy:BAAANQAECgQIBwABNQAECggIFAAWAN8PAA==.Streetdruid:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Streetlight:BAABNQAECn8VAAMQAAcKKhBzxQB3AQAQAAYKvA1zxQB3AQAcAAMKyQ0tYgCgAAABNQAECgEIAQADAAAAAA==.Streetlizard:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Streetpriest:BAAANQAECgEIAQAAAA==.Streets:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Ta='Tank:BAABNQAECn83AAIPAAoK6R+4AgCDAwAPAAoK6R+4AgCDAwAAAA==.',
Te='Teafayd:BAAANQAECgEIBQAAAA==.',
Th='Thunderdot:BAABNQAECn8lAAITAAkKyiEBDQAbAwATAAkKyiEBDQAbAwAAAA==.',
Ti='Tigolock:BAAANQAECgQIBAABNQAECgQIBAADAAAAAA==.Tilvayne:BAACNQAFFH8NAAMdAAUKyw1bBQCZAAAVAAMKZgYuEgC6AAAdAAUKIQxbBQCZAAA1AAQKfzcAAxUACgqTHM0jAHICABUACQq3HM0jAHICAB0ACAoTHDISAEsBAAAA.',
To='Tomayter:BAABNQAECn8bAAIRAAcKEhmfagDfAQARAAcKEhmfagDfAQAAAA==.',
Tr='Trinitee:BAAANQADCgUIBwAAAA==.Trist:BAABNQAECn8lAAMHAAkK9Rg6ZABuAgAHAAkK9Rg6ZABuAgAbAAMKSxIT5gC1AAAAAA==.',
Tu='Turbogoat:BAABNQAECn8dAAIdAAgKuxlaPQAqAgAdAAgKuxlaPQAqAgAAAA==.',
Tw='Twowolves:BAABNQAECn8lAAQJAAkK1x16LgARAQAXAAYKjRyShADbAQAJAAMKkB96LgARAQAYAAMKVRMPHACgAAAAAA==.',
Va='Valthir:BAAANQADCgYIBgAAAA==.',
Xe='Xevic:BAAANQAECgEIAgABNQAECgUICwADAAAAAA==.',
Za='Zalar:BAAANQAECgEIBQABNQAECgoKOQAXADMkAA==.',
Ze='Zerene:BAABNQAECn8cAAIJAAcKCRF+FQDBAQAJAAcKCRF+FQDBAQAAAA==.',
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
