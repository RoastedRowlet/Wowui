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

local lookup = {'Paladin-Holy','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Druid-Balance','Mage-Fire','Mage-Arcane','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Arms','Monk-Windwalker','Shaman-Restoration','DemonHunter-Devourer','Monk-Mistweaver','Mage-Frost','Shaman-Elemental','Druid-Restoration','Priest-Holy','Priest-Shadow','Warlock-Demonology','Evoker-Devastation',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Actaeo:BAAANQAECggIAQAAAA==.',
Ae='Aerytha:BAAANQAECggIEAABNQAFFAUIDAABAJYeAA==.',
Ak='Ako:BAABNQAECoEnAAMCAAgKRxW5HwC8AQACAAgKvBO5HwC8AQADAAEKexxMWAFRAAAAAA==.',
Al='Alannaria:BAAANQAECgQIBAAAAA==.Alexecute:BAAANQAECgMIAwAAAA==.Alx:BAAANQAECggIEwAAAQ==.',
Am='Amaranta:BAAANQABCgQIBAAAAA==.',
Ar='Archom:BAAANQADCggJCAAAAA==.Ares:BAAANQADCgcIFQAAAA==.',
As='Ascendent:BAAANQADCgUICQAAAA==.',
Au='Aubry:BAAANQAECgUIBgAAAA==.Audrey:BAABNQAECoE0AAMEAAkKCyLHLwC7AgAEAAcK8CLHLwC7AgAFAAcKwxw+JAALAgAAAA==.',
Ba='Banjhãkari:BAAANQADCgUIBQAAAA==.',
Bo='Boarface:BAAANQAECggIDwAAAA==.',
Bu='Burdên:BAAANQAECgYIEQAAAA==.',
By='Byng:BAAANQADCgYIBgABNQAECgQIBAAGAAAAAA==.',
Ce='Cerolumin:BAAANQAECgQIBQAAAA==.',
Ch='Chamber:BAAANQAECgcIEgAAAA==.Chamberr:BAAANQAECgQIBAAAAA==.Cheri:BAABNQAECoEaAAIHAAgK0gwORQCwAQAHAAgK0gwORQCwAQAAAA==.',
Co='Codum:BAAANQAECgQICgAAAA==.',
Cr='Crowface:BAABNQAECoEoAAMIAAkK7iNMAACIAwAIAAkK7iNMAACIAwAJAAIKZQaMlAFaAAAAAA==.',
Da='Dackinson:BAAANQAECgEIAQABNQAECgkJHwAKAAMlAA==.Dackosaur:BAABNQAECoEfAAIKAAkKAyUrAQDOAwAKAAkKAyUrAQDOAwAAAA==.Daneikus:BAAANQAECgQIDgAAAA==.Daora:BAAANQAECgQICQAAAA==.Darkenedone:BAABNQAECoEhAAMLAAkKxB1RJwBpAgALAAgK3htRJwBpAgAMAAgKqhkARgDaAQAAAA==.',
De='Deathaura:BAAANQAECgUIBwAAAA==.Destiri:BAAANQAECgYIEQAAAA==.',
Do='Doggx:BAAANQADCggIJgAAAA==.',
Dr='Dracthyr:BAAANQAECgIIAgABNQAECgkJNAAEAAsiAA==.Dragon:BAAANQADCggIFQAAAA==.',
Ds='Ds:BAAANQAECgIIAgABNQAECgkJGAALAIseAA==.',
Du='Dumdum:BAAANQADCgcIFAAAAA==.Dunharg:BAAANQAECgQIBgAAAA==.',
Dy='Dyredruidtwo:BAAANQADCgcIDAAAAA==.',
Ea='Earis:BAAANQADCgUIBgAAAA==.',
El='Elie:BAAANQADCgMIAwABNQAECgQICgAGAAAAAA==.',
En='Enjoyby:BAAANQAECgQIBwAAAA==.Ensanglanter:BAABNQAECoEiAAMMAAkKshkeMQBGAgAMAAgK5RkeMQBGAgANAAgKpxgZJwArAgAAAA==.',
Er='Ernmaidinaa:BAAANQADCgMIAwAAAA==.',
Fe='Fearmenoob:BAAANQADCggICAAAAA==.',
Fr='Frankßuck:BAAANQAECgQIEQAAAA==.Friarstrange:BAAANQAECgUIDwAAAA==.Frozarke:BAAANQADCgYJBgAAAA==.',
Ga='Gaebora:BAAANQADCgQIBAABNQAECgkJIgAMALIZAA==.Gamblet:BAAANQAECgIIAQAAAA==.',
Ge='Genjiskhan:BAABNQAECoEgAAIOAAkKfiBhLwDtAgAOAAkKfiBhLwDtAgAAAA==.',
Gi='Gimlidurak:BAAANQADCgQIBAAAAA==.',
Gp='Gpower:BAAANQADCgMIAwAAAA==.',
Ha='Hamus:BAAANQAECgEIAQAAAA==.Harakki:BAAANQAECgYIEQAAAA==.',
He='Heather:BAAANQADCgYICAAAAA==.Hexaddict:BAAANQADCgEIAQAAAA==.',
Ho='Holyroran:BAAANQAECgUIDAAAAA==.',
Ic='Icdeadpeeple:BAAANQAECgUIDgAAAA==.Icytouch:BAAANQADCgEIAgAAAA==.',
Ir='Irox:BAAANQADCgYIBgAAAA==.',
Ja='Jane:BAAANQADCgYIBgAAAA==.',
Je='Jellybeanrez:BAAANQADCggICwAAAA==.',
Ji='Jimlock:BAAANQAECgYIBgABNQAECgkJKwAPAIAhAA==.',
Jo='Jojolion:BAAANQAECgMIAwAAAA==.',
Ka='Kailani:BAAANQADCgcIEQAAAA==.Kalacia:BAABNQAECoEXAAIJAAgKgRDBqgALAgAJAAgKgRDBqgALAgAAAA==.Kanati:BAAANQADCggIEQAAAA==.',
Kh='Khazadum:BAAANQADCgEIAQAAAA==.',
Kr='Kritz:BAABNQAECoEiAAIKAAkKtRk6CgCUAgAKAAkKtRk6CgCUAgAAAA==.',
Ky='Kyuubii:BAAANQADCgcJBwAAAA==.',
Li='Linglinda:BAABNQAECoErAAIPAAgKZh5gFACPAgAPAAgKZh5gFACPAgAAAA==.',
Lo='Lockwarior:BAAANQAECgcIDQABNQAFFAYIEwAQANkWAA==.',
Lu='Luciena:BAAANQAECgYIEAAAAA==.Lunarheals:BAAANQAECgQIBgAAAA==.Lunasong:BAAANQAECgYIEQAAAA==.',
Ma='Martielder:BAAANQADCgYIBwABNQAECgYIEAAGAAAAAA==.Martyguard:BAAANQAECgYIEAAAAA==.',
Me='Melikehorny:BAABNQAECoElAAIRAAgKKB2iEQDMAgARAAgKKB2iEQDMAgAAAA==.',
Mo='Monkjimothy:BAABNQAECoErAAMPAAkKgCEICQArAwAPAAkKgCEICQArAwASAAUKvhM+JQAmAQAAAA==.Moofasa:BAAANQADCgUICgAAAA==.Moonfailia:BAAANQAECgUIDwABNQAECggIJgATAHIaAA==.Moonstrike:BAAANQAECgEIAQAAAA==.',
Ne='Nekonami:BAAANQAECgYIDQAAAA==.Neltharian:BAAANQADCggICAAAAA==.Nexhilum:BAAANQADCgEIAQABNQAECgQICgAGAAAAAA==.',
No='Nookz:BAAANQADCgYICAAAAA==.Noox:BAAANQADCgcICgAAAA==.Nopalms:BAABNQAECoEYAAIBAAgKcBO/UgACAgABAAgKcBO/UgACAgAAAA==.',
Od='Odinsknight:BAAANQAECgQICwAAAA==.',
Ou='Outfoxdu:BAAANQADCgcIBwABNQAECgUICQAGAAAAAA==.',
Pa='Pallydude:BAAANQADCgYIBQAAAA==.',
Ph='Phreek:BAAANQAECgcIEwAAAA==.',
Po='Popesguard:BAAANQAECgUICQAAAA==.',
Pu='Puma:BAAANQADCgEIAQAAAA==.Puppyroran:BAAANQADCgYIBAAAAA==.',
Ra='Ra:BAAANQADCgQIBAAAAA==.Racinette:BAACNQAFFIEMAAIBAAUKlh7QBgDVAQABAAUKlh7QBgDVAQA1AAQKgSAAAwEACQqBI3YIAHkDAAEACQqBI3YIAHkDAAMAAQpJEzllAT8AAAAA.',
Re='Redia:BAAANQADCgQIBgAAAA==.Rei:BAAANQADCgQIBAAAAA==.',
Ri='Riverside:BAAANQAECgQIBAAAAA==.',
Ro='Roranmcstaby:BAAANQADCgIIAgAAAA==.',
Sa='Saaltaamea:BAAANQADCgMJAwAAAA==.Saelesth:BAAANQAECgEIAQAAAA==.Salvatora:BAAANQADCgYIBgAAAA==.Sambie:BAAANQAECgYIDgAAAA==.',
Sc='Scuffedfaith:BAAANQAECgQIBAAAAA==.Scuffedtotem:BAAANQAECgMIAwABNQAECgQIBAAGAAAAAA==.',
Se='Sefyra:BAAANQAECgUIDgAAAA==.Sentínel:BAAANQADCgEIAQAAAA==.Setelai:BAAANQAECgMJAwAAAA==.',
Sk='Skóll:BAAANQAECgcIEQAAAA==.',
Sl='Slimnipz:BAAANQAECgYIDwAAAA==.',
Sn='Sneakycress:BAAANQAECgIJAgAAAA==.Snolo:BAAANQADCgUJBQAAAA==.',
So='Soulless:BAAANQAECgUIDQABNQAECgYICAAGAAAAAA==.Soulstoned:BAAANQADCgYIBgAAAA==.',
Sp='Spiritwarior:BAACNQAFFIETAAMQAAYK2RbJBAAFAgAQAAYK2RbJBAAFAgAUAAEKUAOvLAA/AAA1AAQKgSYAAxAACQppHXsqAJYCABAACQppHXsqAJYCABQAAgrSFEreAKAAAAAA.',
St='Starsky:BAAANQAECggICAAAAA==.Stone:BAAANQADCgEIAQABNQAECgkJNAAEAAsiAA==.Strangelife:BAAANQABCgQIBAAAAA==.Strangesoul:BAAANQADCgYIBgAAAA==.Strangewood:BAABNQAECoEmAAIVAAgK8RMAIwDhAQAVAAgK8RMAIwDhAQAAAA==.',
Sw='Swiftlee:BAAANQAECgQIBgAAAA==.',
Sy='Sylvan:BAAANQADCggICAABNQAFFAUIDAABAJYeAA==.Sylvanà:BAAANQAECgcICAAAAA==.',
Ta='Tasdan:BAAANQAECgEIAQAAAA==.',
Te='Tejas:BAAANQADCggJCgAAAA==.',
Th='Thotsnprayer:BAAANQADCgYIBwAAAA==.Thunderfnk:BAAANQAECgcIDgAAAA==.Thursday:BAAANQAECggIEwABNQAECgkJGAALAIseAA==.',
To='Tommym:BAAANQAECgcIEQAAAA==.',
Tr='Tradravia:BAAANQADCgcIDAAAAA==.Trickydice:BAAANQAECgQICAAAAA==.',
Tw='Twentythree:BAAANQADCgYIBgABNQAECgQIBAAGAAAAAA==.',
Va='Valdyr:BAAANQAECgYIEwAAAA==.Varmo:BAAANQADCggIDgAAAA==.',
Vy='Vyrianath:BAAANQAECgUICQAAAA==.',
Wa='Wakwanda:BAABNQAECoEkAAMWAAkKeROhPwBHAgAWAAkKeROhPwBHAgAXAAgKhRR3HgAlAgAAAA==.Wardsky:BAAANQAECgIIAwAAAA==.Wawaweewa:BAAANQADCgIIAgABNQAECgcIDgAGAAAAAA==.',
Wi='Witheredhope:BAABNQAECoEdAAMDAAgKzwXpwwBbAQADAAgKzwXpwwBbAQABAAEKvQGREgEpAAABNQAFFAUIEQAYAOkGAA==.',
Wr='Wreckthar:BAABNQAECoEpAAIDAAkKNyPMEgBsAwADAAkKNyPMEgBsAwAAAA==.',
Ze='Zenetrawr:BAABNQAECoEiAAIZAAgKrgywFgC+AQAZAAgKrgywFgC+AQAAAA==.',
['Zô']='Zôrra:BAAANQADCgQIBAAAAA==.',
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
