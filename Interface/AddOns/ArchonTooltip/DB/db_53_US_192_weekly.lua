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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Mage-Fire','Mage-Arcane','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','DeathKnight-Frost','Warrior-Arms','Monk-Windwalker','Shaman-Restoration','DemonHunter-Devourer','Monk-Mistweaver','Mage-Frost','Shaman-Elemental','Druid-Restoration','Priest-Holy','Priest-Shadow','Warlock-Demonology','Evoker-Devastation',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=53,date='2026-09-29',data={Ae='Aerytha:BAAANQAECgUICAABNQAFFAUICAABAAgeAA==.',
Ak='Ako:BAABNQAECoEfAAMCAAgKtxQ5HACwAQACAAgKLBM5HACwAQADAAEKexxmLQFXAAAAAA==.',
Al='Alannaria:BAAANQAECgQIBAAAAA==.Alexecute:BAAANQAECgMIAwAAAA==.Alx:BAAANQAECggIEwAAAQ==.',
Am='Amaranta:BAAANQABCgQIBAAAAA==.',
Ar='Archom:BAAANQADCggJCAAAAA==.Ares:BAAANQADCgcIFQAAAA==.',
As='Ascendent:BAAANQADCgUICQAAAA==.',
Au='Aubry:BAAANQAECgEIAQAAAA==.Audrey:BAABNQAECoErAAMEAAgKOyM+KQC3AgAEAAcKuSI+KQC3AgAFAAYKqx0xJgDRAQAAAA==.',
Ba='Banjhãkari:BAAANQADCgUJBQAAAA==.',
Bo='Boarface:BAAANQAECgcIBwAAAA==.',
Bu='Burdên:BAAANQAECgQICwAAAA==.',
By='Byng:BAAANQADCgYIBgAAAA==.',
Ce='Cerolumin:BAAANQAECgQIBQAAAA==.',
Ch='Chamber:BAAANQAECgcIEgAAAA==.Chamberr:BAAANQAECgQIBAAAAA==.Cheri:BAABNQAECoEaAAIGAAgK0gy6PAC/AQAGAAgK0gy6PAC/AQAAAA==.',
Co='Codum:BAAANQAECgQICgAAAA==.',
Cr='Crowface:BAABNQAECoEhAAMHAAkKXyJFAACAAwAHAAkKXyJFAACAAwAIAAIKZQYUdQFeAAAAAA==.',
Da='Dackinson:BAAANQAECgEIAQABNQAECgkJGAAJAOkiAA==.Dackosaur:BAABNQAECoEYAAIJAAkK6SIiAgCDAwAJAAkK6SIiAgCDAwAAAA==.Daneikus:BAAANQAECgQICgAAAA==.Daora:BAAANQAECgMIBQAAAA==.Darkenedone:BAABNQAECoEeAAMKAAkK8ByIJABeAgAKAAgK8BqIJABeAgALAAgKqhkuNAD6AQAAAA==.',
De='Deathaura:BAAANQAECgUIBgAAAA==.Destiri:BAAANQAECgUIDwAAAA==.',
Do='Doggx:BAAANQADCggIJQAAAA==.',
Dr='Dragon:BAAANQADCggIDQAAAA==.',
Du='Dumdum:BAAANQADCgYIDQAAAA==.Dunharg:BAAANQAECgQIBgAAAA==.',
Dy='Dyredruidtwo:BAAANQADCgcIDAAAAA==.',
Ea='Earis:BAAANQADCgUIBgAAAA==.',
El='Elie:BAAANQADCgMIAwABNQAECgQICgAMAAAAAA==.',
En='Enjoyby:BAAANQAECgQIBwAAAA==.Ensanglanter:BAABNQAECoEbAAMNAAgKoBo3HwBCAgANAAgKpxg3HwBCAgALAAYKsRrbRgCWAQAAAA==.',
Er='Ernmaidinaa:BAAANQADCgMIAwAAAA==.',
Fe='Fearmenoob:BAAANQADCggICAAAAA==.',
Fr='Frankßuck:BAAANQAECgQICwAAAA==.Friarstrange:BAAANQAECgQICgAAAA==.Frozarke:BAAANQADCgYJBgAAAA==.',
Ga='Gaebora:BAAANQADCgQIBAABNQAECggIGwANAKAaAA==.',
Ge='Genjiskhan:BAABNQAECoEdAAIOAAkKfiCiIwAEAwAOAAkKfiCiIwAEAwAAAA==.',
Gp='Gpower:BAAANQADCgMIAwAAAA==.',
Ha='Hamus:BAAANQADCggIJQAAAA==.Harakki:BAAANQAECgUICwAAAA==.',
He='Heather:BAAANQADCgYICAAAAA==.Hexaddict:BAAANQADCgEIAQAAAA==.',
Ho='Holyroran:BAAANQAECgQIBwAAAA==.',
Ic='Icdeadpeeple:BAAANQAECgQICQAAAA==.Icytouch:BAAANQADCgEIAgAAAA==.',
Ir='Irox:BAAANQADCgYIBgAAAA==.',
Ja='Jane:BAAANQADCgYIBgAAAA==.',
Je='Jellybeanrez:BAAANQADCggICwAAAA==.',
Ji='Jimlock:BAAANQAECgYIBgABNQAECgkJJAAPAE8hAA==.',
Jo='Jojolion:BAAANQAECgMIAwAAAA==.',
Ka='Kailani:BAAANQADCgcIEQAAAA==.Kalacia:BAAANQAECgcIDgAAAA==.Kanati:BAAANQADCggIEQAAAA==.',
Kh='Khazadum:BAAANQADCgEIAQAAAA==.',
Kr='Kritz:BAABNQAECoEcAAIJAAkKtRmwBwCgAgAJAAkKtRmwBwCgAgAAAA==.',
Ky='Kyuubii:BAAANQADCgcJBwAAAA==.',
Li='Linglinda:BAABNQAECoEkAAIPAAgKZh72DwCpAgAPAAgKZh72DwCpAgAAAA==.',
Lo='Lockwarior:BAAANQAECgcIDQABNQAFFAUIDQAQAG8SAA==.',
Lu='Luciena:BAAANQAECgUICgAAAA==.Lunarheals:BAAANQAECgQIBgAAAA==.Lunasong:BAAANQAECgQICwAAAA==.',
Ma='Martielder:BAAANQADCgUIBQABNQAECgQICgAMAAAAAA==.Martyguard:BAAANQAECgQICgAAAA==.',
Me='Melikehorny:BAABNQAECoEfAAIRAAgKJhtSFACXAgARAAgKJhtSFACXAgAAAA==.',
Mo='Monkjimothy:BAABNQAECoEkAAMPAAkKTyHTBwAuAwAPAAkKTyHTBwAuAwASAAUKvhMtIQAqAQAAAA==.Moofasa:BAAANQADCgUICgAAAA==.Moonfailia:BAAANQAECgQICgABNQAECggIHwATAPUYAA==.Moonstrike:BAAANQADCgcIDQAAAA==.',
Ne='Nekonami:BAAANQAECgUJCgAAAA==.Neltharian:BAAANQADCggICAAAAA==.Nexhilum:BAAANQADCgEIAQABNQAECgQICgAMAAAAAA==.',
No='Nookz:BAAANQADCgMIAwAAAA==.Noox:BAAANQADCgMIAwAAAA==.Nopalms:BAAANQAECgcIEwAAAA==.',
Od='Odinsknight:BAAANQAECgQICwAAAA==.',
Pa='Pallydude:BAAANQADCgUIBQAAAA==.',
Ph='Phreek:BAAANQAECgYIEQAAAA==.',
Po='Popesguard:BAAANQAECgUICQAAAA==.',
Pu='Puma:BAAANQADCgEIAQAAAA==.Puppyroran:BAAANQADCgYIBAAAAA==.',
Ra='Ra:BAAANQADCgQIBAAAAA==.Racinette:BAACNQAFFIEIAAIBAAUKCB7rBADXAQABAAUKCB7rBADXAQA1AAQKgSAAAwEACQqBI2AGAIIDAAEACQqBI2AGAIIDAAMAAQpJE/86AUIAAAAA.',
Re='Redia:BAAANQADCgQIBgAAAA==.Rei:BAAANQADCgQIBAAAAA==.',
Ri='Riverside:BAAANQADCgQIBAABNQADCgYIBgAMAAAAAA==.',
Ro='Roranmcstaby:BAAANQADCgIIAgAAAA==.',
Sa='Saaltaamea:BAAANQADCgMJAwAAAA==.Saelesth:BAAANQADCgQIBAAAAA==.Salvatora:BAAANQADCgYIBgAAAA==.Sambie:BAAANQAECgQICAAAAA==.',
Sc='Scuffedfaith:BAAANQAECgQIBAAAAA==.Scuffedtotem:BAAANQAECgMIAwABNQAECgQIBAAMAAAAAA==.',
Se='Sefyra:BAAANQAECgQICQAAAA==.Sentínel:BAAANQADCgEIAQAAAA==.Setelai:BAAANQAECgMJAwAAAA==.',
Sk='Skóll:BAAANQAECgcIEQAAAA==.',
Sl='Slimnipz:BAAANQAECgQICQAAAA==.',
Sn='Sneakycress:BAAANQAECgIJAgAAAA==.Snolo:BAAANQADCgUJBQAAAA==.',
So='Soulless:BAAANQAECgUIDQAAAA==.Soulstoned:BAAANQADCgYIBgAAAA==.',
Sp='Spiritwarior:BAACNQAFFIENAAMQAAUKbxKtBwCNAQAQAAUKbxKtBwCNAQAUAAEKUANLJQBAAAA1AAQKgSMAAxAACQppHVsiAKYCABAACQppHVsiAKYCABQAAQoXBjzyAD0AAAAA.',
St='Stone:BAAANQADCgEIAQABNQAECggIKwAEADsjAA==.Strangelife:BAAANQABCgQIBAAAAA==.Strangewood:BAABNQAECoEfAAIVAAgK8RM8HQDxAQAVAAgK8RM8HQDxAQAAAA==.',
Sw='Swiftlee:BAAANQAECgQIBgAAAA==.',
Sy='Sylvan:BAAANQADCggICAABNQAFFAUICAABAAgeAA==.Sylvanà:BAAANQAECgcIBwAAAA==.',
Ta='Tasdan:BAAANQADCggIGgAAAA==.',
Te='Tejas:BAAANQADCggJCgAAAA==.',
Th='Thunderfnk:BAAANQAECgcIDgAAAA==.Thursday:BAAANQAECgcIEQABNQAECggIEAAMAAAAAA==.',
To='Tommym:BAAANQAECgcIEQAAAA==.',
Tr='Tradravia:BAAANQADCgcIDAAAAA==.Trickydice:BAAANQAECgIIBAAAAA==.',
Va='Valdyr:BAAANQAECgUIDQAAAA==.Varmo:BAAANQADCggIDgAAAA==.',
Vy='Vyrianath:BAAANQAECgQICAAAAA==.',
Wa='Wakwanda:BAABNQAECoEbAAMWAAgKXBQ+RAAOAgAWAAgKXBQ+RAAOAgAXAAgKBxKgHQAIAgAAAA==.Wardsky:BAAANQAECgIIAgAAAA==.Wawaweewa:BAAANQADCgIIAgABNQAECgcIDgAMAAAAAA==.',
Wi='Witheredhope:BAABNQAECoEaAAMDAAgKvgVqpwBhAQADAAgKvgVqpwBhAQABAAEKvQFI+QApAAABNQAFFAUIDQAYAPUDAA==.',
Wr='Wreckthar:BAABNQAECoEiAAIDAAkKwyIADgB6AwADAAkKwyIADgB6AwAAAA==.',
Ze='Zenetrawr:BAABNQAECoEaAAIZAAcKLQtbGQB1AQAZAAcKLQtbGQB1AQAAAA==.',
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
