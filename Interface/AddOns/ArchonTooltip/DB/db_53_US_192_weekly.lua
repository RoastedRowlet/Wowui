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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Unknown-Unknown','Druid-Balance','Druid-Restoration','Mage-Fire','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Monk-Mistweaver','Warrior-Arms','Monk-Windwalker','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Frost','Shaman-Elemental','Priest-Holy','Priest-Shadow','Warlock-Demonology','Evoker-Devastation',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Actaeo:BAAANQAECggIAwAAAA==.',
Ae='Aerytha:BAABNQAECn8YAAIBAAkKCBKVlQBUAgABAAkKCBKVlQBUAgABNQAFFAUIEAACABIfAA==.',
Ak='Ako:BAABNQAECn8zAAMDAAkKNxeCGgAaAgADAAkKfBSCGgAaAgAEAAYKAxzopwDLAQAAAA==.',
Al='Alannaria:BAAANQAECgQIBwAAAA==.Alexecute:BAAANQAECgQICAAAAA==.Alx:BAAANQAECggIGwAAAQ==.',
Am='Amaranta:BAAANQABCgQIBAAAAA==.',
Ar='Archom:BAAANQAECgEIAQAAAA==.Ares:BAAANQAECgEIAQAAAA==.',
As='Ascendent:BAAANQADCgUICQAAAA==.',
Au='Aubry:BAAANQAECgUICAAAAA==.Audrey:BAABNQAECn84AAMFAAkK6yGRPQCvAgAFAAcKHyORPQCvAgAGAAgKwB1zGwB2AgAAAA==.',
Ba='Banjhãkari:BAAANQADCgUIBQAAAA==.',
Bo='Boarface:BAABNQAECn8YAAIHAAkKFBbzAwC5AgAHAAkKFBbzAwC5AgAAAA==.',
Bu='Burdên:BAABNQAECn8WAAIBAAcKDAMkRQEWAQABAAcKDAMkRQEWAQAAAA==.',
By='Byng:BAAANQADCgYIBgABNQAECgQIBQAIAAAAAA==.',
Ce='Cerolumin:BAAANQAECgQIBQAAAA==.',
Ch='Chamber:BAABNQAECn8VAAMJAAgKRRuGKgCBAgAJAAgKRRuGKgCBAgAKAAEKaAo2egAmAAAAAA==.Chamberr:BAAANQAECgQIBAAAAA==.Cheri:BAABNQAECn8gAAIJAAkKGgyBQQDvAQAJAAkKGgyBQQDvAQAAAA==.',
Co='Codum:BAAANQAECgYIDgAAAA==.',
Cr='Crowface:BAABNQAECn8uAAMLAAkKGyRFAACyAwALAAkKGyRFAACyAwABAAIKqwYmrwFaAAAAAA==.',
Da='Dackinson:BAAANQAECgEIAQABNQAECgkJIwAMAO0kAA==.Dackosaur:BAABNQAECn8jAAIMAAkK7SSHAQDKAwAMAAkK7SSHAQDKAwAAAA==.Daneikus:BAAANQAECgQIDwAAAA==.Daora:BAAANQAECgUIEwAAAA==.Daque:BAAANQAECgEIAQABNQAECgkJIwAMAO0kAA==.Darkenedone:BAABNQAECn8nAAQNAAkKHh/hLgBVAgANAAgKnRvhLgBVAgAOAAgK4BkHTwDVAQAPAAMKUhDgfACsAAAAAA==.',
De='Deathaura:BAAANQAECgUIDAAAAA==.Destiri:BAAANQAECgYIEwAAAA==.',
Do='Doggx:BAAANQADCggIKQAAAA==.',
Dr='Dracthyr:BAAANQAECgMIBAABNQAECgkJOAAFAOshAA==.Dragon:BAAANQAECgEIAQAAAA==.',
Ds='Ds:BAAANQAECgIIBAABNQAECgkJGAAMAJwjAA==.',
Du='Dumdum:BAAANQADCggIFQAAAA==.Dunharg:BAAANQAECgQIBwAAAA==.',
Dy='Dyredruidtwo:BAAANQAECgEIAwAAAA==.',
Ea='Earis:BAAANQADCgUIBgAAAA==.',
El='Elie:BAAANQADCgMIAwABNQAECgYIDgAIAAAAAA==.',
En='Enjoyby:BAAANQAECgQIBwAAAA==.Ensanglanter:BAABNQAECn8oAAMPAAkK9BhtKABQAgAPAAgKUBptKABQAgAOAAgKVBmTOQA7AgAAAA==.',
Er='Ernmaidinaa:BAAANQADCgMIAwAAAA==.',
Fe='Fearmenoob:BAAANQADCggICAAAAA==.',
Fr='Frankßuck:BAABNQAECn8VAAIFAAUK+ATnBgHzAAAFAAUK+ATnBgHzAAAAAA==.Friarstrange:BAABNQAECn8ZAAIQAAcKEA1GJABXAQAQAAcKEA1GJABXAQAAAA==.Frozarke:BAAANQADCgYJBgAAAA==.',
Ga='Gaebora:BAAANQADCgQIBAABNQAECgkJKAAPAPQYAA==.Gamblet:BAAANQAECgIIAQAAAA==.',
Ge='Genjiskhan:BAABNQAECn8jAAIRAAkK9h+qNgDlAgARAAkK9h+qNgDlAgAAAA==.',
Gi='Gimlidurak:BAAANQADCgQIBAAAAA==.',
Gp='Gpower:BAAANQADCgMIAwAAAA==.',
Ha='Hamus:BAAANQAECgEIBAAAAA==.Harakki:BAABNQAECn8XAAMPAAcKMBPiVABTAQAPAAYKMBPiVABTAQANAAYKrAo5gAD2AAAAAA==.',
He='Heather:BAAANQADCgYICAAAAA==.Hexaddict:BAAANQADCgEIAQAAAA==.',
Ho='Holyroran:BAAANQAECggIEAAAAA==.',
Ic='Icdeadpeeple:BAAANQAECgUIEQAAAA==.Icytouch:BAAANQADCgEIAgAAAA==.',
Ir='Irox:BAAANQADCgYIBgAAAA==.',
Ja='Jane:BAAANQADCgYIBgAAAA==.',
Je='Jellybeanrez:BAAANQAECgEIAQAAAA==.',
Ji='Jimlock:BAAANQAECgYIBgABNQAECgkJLgASAGchAA==.',
Jo='Jojolion:BAAANQAECgMIAwAAAA==.',
Ka='Kailani:BAAANQADCgcIEQAAAA==.Kalacia:BAABNQAECn8ZAAIBAAgKShRTwAACAgABAAgKShRTwAACAgAAAA==.Kanati:BAAANQADCggIEQAAAA==.',
Kh='Khazadum:BAAANQADCgEIAQAAAA==.',
Kr='Kritz:BAABNQAECn8oAAIMAAkKLxq4DACYAgAMAAkKLxq4DACYAgAAAA==.',
Ky='Kyuubii:BAAANQADCgcJBwAAAA==.',
Li='Linglinda:BAABNQAECn8wAAISAAkKmR2JDgD1AgASAAkKmR2JDgD1AgAAAA==.',
Lo='Lockwarior:BAAANQAECgcIEAABNQAFFAcIGQATAOcZAA==.',
Lu='Luciena:BAABNQAECn8aAAIUAAcKFBDKQwCgAQAUAAcKFBDKQwCgAQAAAA==.Lunarheals:BAAANQAECgQIBwAAAA==.Lunasong:BAAANQAECgYIEwAAAA==.',
Ma='Martielder:BAAANQADCgYIBwABNQAECgcIFQACAH8SAA==.Martyguard:BAABNQAECn8VAAICAAcKfxIBegCnAQACAAcKfxIBegCnAQAAAA==.',
Me='Melikehorny:BAABNQAECn8qAAIVAAkKfRqQDwD0AgAVAAkKfRqQDwD0AgAAAA==.',
Mo='Monkjimothy:BAABNQAECn8uAAMSAAkKZyEdCwAgAwASAAkKZyEdCwAgAwAQAAUKvhO/KQAeAQAAAA==.Moofasa:BAAANQADCgUICgAAAA==.Moonfailia:BAABNQAECn8ZAAIMAAcKIQWVMwD/AAAMAAcKIQWVMwD/AAABNQAECgkJLgAWAEIYAA==.Moonstrike:BAAANQAECgIIAwAAAA==.',
Ne='Nekonami:BAAANQAECgYIEQAAAA==.Neltharian:BAAANQADCggICAAAAA==.Nexhilum:BAAANQADCgEIAQABNQAECgUIDwAIAAAAAA==.',
No='Nookz:BAAANQADCgcICQAAAA==.Noox:BAAANQADCgcICgAAAA==.Nopalms:BAABNQAECn8YAAICAAgKcBNpYAD0AQACAAgKcBNpYAD0AQAAAA==.',
Od='Odinsknight:BAAANQAECgQIDgAAAA==.',
Ou='Outfoxdu:BAAANQADCgcIDgABNQAECgUICAAIAAAAAA==.',
Pa='Pallydude:BAAANQADCgYIBQAAAA==.',
Ph='Phreek:BAABNQAECn8WAAIBAAgKAw63ywDsAQABAAgKAw63ywDsAQAAAA==.',
Po='Popesguard:BAAANQAECgcIEQAAAA==.',
Pu='Puma:BAAANQADCgEIAQAAAA==.Puppyroran:BAAANQADCgYIBAAAAA==.',
Ra='Ra:BAAANQADCgQIBAAAAA==.Racinette:BAACNQAFFH8QAAICAAUKEh9pCADYAQACAAUKEh9pCADYAQA1AAQKfyEAAwIACQr/I4EJAHsDAAIACQr/I4EJAHsDAAQAAQpJE9yOAT8AAAAA.',
Re='Redia:BAAANQADCgQIBgAAAA==.Rei:BAAANQADCgQIBAAAAA==.',
Ri='Riverside:BAAANQAECgQIBQAAAA==.',
Ro='Roranmcstaby:BAAANQADCgIIAgAAAA==.',
Sa='Saaltaamea:BAAANQADCgMJAwAAAA==.Saelesth:BAAANQAECgIIAwAAAA==.Salvatora:BAAANQADCgYIBgAAAA==.Sambie:BAAANQAECgYIEgAAAA==.',
Sc='Scuffedfaith:BAAANQAECgQIBAAAAA==.Scuffedtotem:BAAANQAECgMIAwABNQAECgQIBAAIAAAAAA==.',
Se='Sefyra:BAABNQAECn8XAAIFAAcKgAW3vgCAAQAFAAcKgAW3vgCAAQAAAA==.Sentínel:BAAANQADCgEIAQAAAA==.Setelai:BAAANQAECgMJAwAAAA==.',
Sk='Skóll:BAAANQAECgcIEgAAAA==.',
Sl='Slimnipz:BAAANQAECgYIEQAAAA==.',
Sn='Sneakycress:BAAANQAECgUICgAAAA==.Snolo:BAAANQADCgUJBQAAAA==.',
So='Soulless:BAAANQAECgUIDQABNQAECgYIDwAIAAAAAA==.Soulstoned:BAAANQADCgYIBgAAAA==.',
Sp='Spiritwarior:BAACNQAFFH8ZAAMTAAcK5xmWAgB2AgATAAcK5xmWAgB2AgAXAAEKUAP1MwA/AAA1AAQKfykAAxMACQppHSk0AIwCABMACQppHSk0AIwCABcAAwoJGdDHAP4AAAAA.',
St='Starsky:BAAANQAECggICAAAAA==.Stone:BAAANQADCgEIAQABNQAECgkJOAAFAOshAA==.Strangelife:BAAANQABCgQIBAAAAA==.Strangesoul:BAAANQADCgYIBgAAAA==.Strangewood:BAABNQAECn8tAAMKAAkKsRIfIwAIAgAKAAkKsRIfIwAIAgAJAAIK2Q6QnQBhAAAAAA==.',
Sw='Swiftlee:BAAANQAECgQIBwAAAA==.',
Sy='Sylvan:BAAANQAECgEIAQABNQAFFAUIEAACABIfAA==.Sylvanà:BAAANQAECggICAAAAA==.',
Ta='Tasdan:BAAANQAECgEIBAAAAA==.',
Te='Tejas:BAAANQADCggJCgAAAA==.',
Th='Thotsnprayer:BAAANQADCgYICQAAAA==.Thunderfnk:BAAANQAECgcIEAAAAA==.Thursday:BAABNQAECn8YAAIMAAkKnCNfAwCBAwAMAAkKnCNfAwCBAwAAAA==.',
To='Tommym:BAAANQAECgcIEgAAAA==.',
Tr='Tradravia:BAAANQADCgcIDAAAAA==.Trickydice:BAAANQAECgUIEQAAAA==.',
Tw='Twentythree:BAAANQADCgYIBgABNQAECgQIBQAIAAAAAA==.',
Va='Valdyr:BAABNQAECn8aAAIEAAcK0hkMpgDPAQAEAAcK0hkMpgDPAQAAAA==.Varmo:BAAANQADCggIDgAAAA==.',
Vy='Vyrianath:BAAANQAECgUICwAAAA==.',
Wa='Wakwanda:BAABNQAECn8kAAMYAAkKeROWSwA/AgAYAAkKeROWSwA/AgAZAAgKJxMlIwAWAgAAAA==.Wardsky:BAAANQAECgIIBQAAAA==.Wawaweewa:BAAANQADCgIIAgABNQAECgcIEAAIAAAAAA==.',
Wi='Witheredhope:BAABNQAECn8dAAMEAAgK5AXm4QBRAQAEAAgK5AXm4QBRAQACAAEKvQGILQEmAAABNQAFFAYIFwAaAI0FAA==.',
Wr='Wreckthar:BAABNQAECn8qAAIEAAkKnCIZHQBNAwAEAAkKnCIZHQBNAwAAAA==.',
Ze='Zenetrawr:BAABNQAECn8pAAIbAAgKHQ0BGADGAQAbAAgKHQ0BGADGAQAAAA==.Zeri:BAAANQAECgEIAQAAAA==.',
['Zô']='Zôrra:BAAANQADCgUIBwAAAA==.',
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
