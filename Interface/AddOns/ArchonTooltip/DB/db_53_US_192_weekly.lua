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

local lookup = {'Mage-Arcane','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Unknown-Unknown','Druid-Balance','Druid-Restoration','Mage-Fire','Druid-Guardian','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Shaman-Elemental','Priest-Holy','Priest-Shadow','Warlock-Demonology','Evoker-Devastation',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Actaeo:BAAANQAECggIBQAAAA==.',
Ae='Aerytha:BAABNQAECn8eAAIBAAoKYxHRlwBRAgABAAoKYxHRlwBRAgABNQAFFAYIEQACAGQeAA==.',
Ai='Aimpoint:BAAANQABCgYIBwAAAA==.',
Ak='Ako:BAABNQAECn9NAAMDAAoKJhi3CwDyAQADAAoKURa3CwDyAQAEAAYKuB2wqgDKAQAAAA==.',
Al='Alannaria:BAAANQAECgQIBAAAAA==.Alexecute:BAAANQAECgQIBQAAAA==.Alx:BAAANQAECggIFwAAAQ==.',
Am='Amaranta:BAAANQABCggICwAAAA==.',
Ar='Ares:BAAANQADCgcIFQAAAA==.',
As='Ascendent:BAAANQADCgUICQAAAA==.',
Au='Aubry:BAAANQAECgYIDwAAAA==.Audrey:BAABNQAECn8/AAMFAAoKQyORPgCuAgAFAAkKpCORPgCuAgAGAAgKPh68GwB1AgAAAA==.',
Bo='Boarface:BAABNQAECn8iAAIHAAoKHhX6AwC4AgAHAAoKHhX6AwC4AgAAAA==.',
Bu='Burdên:BAABNQAECn8bAAIBAAgKZANnSAEVAQABAAgKZANnSAEVAQAAAA==.',
By='Byng:BAAANQADCgYIBgABNQAECgUIBgAIAAAAAA==.',
Ce='Cerolumin:BAAANQAECgQIBQAAAA==.',
Ch='Chamber:BAABNQAECn8VAAMJAAgKRRsOKwCBAgAJAAgKRRsOKwCBAgAKAAEKaAo+fAAmAAAAAA==.Chamberr:BAAANQAECgQIBAAAAA==.Cheri:BAABNQAECn8nAAIJAAkKGgwQQgDvAQAJAAkKGgwQQgDvAQAAAA==.',
Co='Codum:BAABNQAECn8VAAIBAAgKlh+ZnABHAgABAAgKlh+ZnABHAgAAAA==.',
Cr='Crowface:BAABNQAECn8/AAMLAAoKlSNIAACxAwALAAoKlSNIAACxAwABAAIKqwYkswFaAAAAAA==.',
Da='Dackinson:BAAANQAECgEIAQABNQAECgoKKgAMADslAA==.Dackosaur:BAABNQAECn8qAAIMAAoKOyWRAQDKAwAMAAoKOyWRAQDKAwAAAA==.Daneikus:BAAANQAECgQIDgAAAA==.Daora:BAABNQAECn8YAAQNAAYKzxoJDgDcAQANAAYKzxoJDgDcAQAOAAMKgRD1TwDfAAAPAAEKAACGeQAAAAAAAA==.Darkenedone:BAABNQAECn8tAAQQAAoKexxjLwBVAgAQAAgKnRtjLwBVAgARAAgK4BnOTwDVAQASAAcKcw67TADjAAAAAA==.',
De='Deathaura:BAAANQAECgYICAAAAA==.Destiri:BAAANQAECgYIEQAAAA==.',
Do='Doggx:BAAANQAECgMIBAAAAA==.',
Dr='Dracthyr:BAAANQAECgIIAwABNQAECgoKPwAFAEMjAA==.Dragon:BAAANQADCggIFQAAAA==.',
Ds='Ds:BAAANQAECgIICQABNQAFFAIIBQAQAOQaAA==.',
Du='Dumdum:BAAANQADCggIGgAAAA==.Dunharg:BAAANQAECgYIBwAAAA==.',
Dy='Dyredruidtwo:BAAANQAECgYIBgAAAA==.',
Ea='Earis:BAAANQADCgUIBgAAAA==.',
El='Elie:BAAANQADCgMIAwABNQAECggIFQABAJYfAA==.',
En='Enjoyby:BAAANQAECgQIBwAAAA==.Ensanglanter:BAABNQAECn8pAAMSAAoKAhhRKQBOAgASAAkKChlRKQBOAgARAAgKVBlAOgA6AgAAAA==.',
Er='Ernmaidinaa:BAAANQADCgMIAwAAAA==.',
Fe='Fearmenoob:BAAANQADCggICAAAAA==.',
Fi='Fistwarior:BAAANQAECgcIDgABNQAFFAcIHwATAMofAA==.',
Fr='Frankßuck:BAABNQAECn8hAAIFAAgKHwXGoQDrAAAFAAgKHwXGoQDrAAAAAA==.Friarstrange:BAABNQAECn8dAAMUAAgKhBCdJABXAQAUAAcKEA6dJABXAQAVAAEKugXFTAAoAAAAAA==.Frozarke:BAAANQADCgYJBgAAAA==.',
Ga='Gaebora:BAAANQADCgQIBAABNQAECgoKKQASAAIYAA==.Gamblet:BAAANQAECggIAQAAAA==.',
Ge='Genjiskhan:BAABNQAECn8vAAIWAAoKcCLNDwDmAgAWAAoKcCLNDwDmAgAAAA==.',
Gi='Gimlidurak:BAAANQADCgQIBAAAAA==.',
Go='Gobbylynn:BAAANQADCgMIBAABNQAECgYIGwAXACMIAA==.',
Gp='Gpower:BAAANQADCgMIAwAAAA==.',
Ha='Hamus:BAAANQAECgQICQAAAA==.Harakki:BAABNQAECn8eAAMSAAkKqBGGVgBTAQASAAkKqBGGVgBTAQAQAAYKrApHgQD2AAAAAA==.',
He='Heather:BAAANQADCgYICAAAAA==.Hexaddict:BAAANQADCgEIAQAAAA==.',
Ho='Holyroran:BAAANQAECgcIEwAAAA==.',
Ic='Icdeadpeeple:BAAANQAECgUIDwAAAA==.Icytouch:BAAANQADCgEIAgAAAA==.',
Ir='Irox:BAAANQADCgYIBgAAAA==.',
Ja='Jane:BAAANQADCgYIBgAAAA==.',
Je='Jellybeanrez:BAAANQADCggICwAAAA==.',
Ji='Jimlock:BAAANQAECgYIBgABNQAECgoKNwAVAC8hAA==.',
Jo='Jojolion:BAAANQAECgMIAwAAAA==.',
Ka='Kailani:BAAANQADCgcIEQAAAA==.Kalacia:BAABNQAECn8cAAIBAAkKlhIjwgAAAgABAAkKlhIjwgAAAgAAAA==.Kanati:BAAANQADCggIEQAAAA==.',
Kh='Khazadum:BAAANQADCgEIAQAAAA==.',
Kr='Kritz:BAABNQAECn8xAAIMAAoKPRnbDACaAgAMAAoKPRnbDACaAgAAAA==.',
Ky='Kyuubii:BAAANQADCgcJBwAAAA==.',
Le='Leksi:BAAANQAECgUIBQAAAA==.',
Li='Linglinda:BAABNQAECn8+AAIVAAoK8x23DgD1AgAVAAoK8x23DgD1AgAAAA==.',
Lo='Lockwarior:BAAANQAECggIDgABNQAFFAcIHwATAMofAA==.',
Lu='Luciena:BAABNQAECn8dAAIPAAgKXQ+hRACgAQAPAAgKXQ+hRACgAQAAAA==.Lunarheals:BAAANQAECgQIBgAAAA==.Lunasong:BAABNQAECn8WAAIFAAgKbQMD/gAIAQAFAAgKbQMD/gAIAQAAAA==.',
Ma='Martielder:BAAANQADCgcIBwABNQAECggIGgACAHkSAA==.Martyguard:BAABNQAECn8aAAICAAgKeRIwewCnAQACAAgKeRIwewCnAQAAAA==.',
Me='Melikehorny:BAABNQAECn83AAIOAAoKERrdDwD0AgAOAAoKERrdDwD0AgAAAA==.',
Mo='Monkjimothy:BAABNQAECn83AAMVAAoKLyFHCwAgAwAVAAoKLyFHCwAgAwAUAAUKvhMwKgAeAQAAAA==.Moofasa:BAAANQADCgUICgAAAA==.Moonfailia:BAABNQAECn8hAAIMAAgKSwWJNAD/AAAMAAgKSwWJNAD/AAAAAA==.Moonstrike:BAAANQAECgIIAgAAAA==.',
Ne='Nekonami:BAAANQAECgYIDwAAAA==.Neltharian:BAAANQADCggICAAAAA==.Nexhilum:BAAANQADCgEIAQABNQAECgQIDAAIAAAAAA==.',
No='Nookz:BAAANQADCgcICQAAAA==.Noox:BAAANQADCgcICgAAAA==.Nopalms:BAABNQAECn8YAAICAAgKcBNQYQD0AQACAAgKcBNQYQD0AQAAAA==.',
['Nó']='Nóóx:BAAANQABCgQIBQAAAA==.',
['Nø']='Nøøx:BAAANQADCgUIBQAAAA==.',
Od='Odinsknight:BAAANQAECgQICwAAAA==.',
Ou='Outfoxdu:BAAANQADCggIEQABNQAECgYIGwAXACMIAA==.',
Pa='Pallydude:BAAANQADCgYIBQAAAA==.',
Ph='Phreek:BAABNQAECn8dAAIBAAoKIQ6ZzQDrAQABAAoKIQ6ZzQDrAQAAAA==.',
Po='Popesguard:BAABNQAECn8UAAIBAAkKVQNoNwEwAQABAAkKVQNoNwEwAQAAAA==.',
Pu='Puma:BAAANQADCgEIAQAAAA==.Puppyroran:BAAANQADCgYIBAAAAA==.',
Ra='Ra:BAAANQADCgQIBAAAAA==.Racinette:BAACNQAFFH8RAAICAAYKZB6uCADYAQACAAYKZB6uCADYAQA1AAQKfycAAwIACgqRI64JAHsDAAIACgqRI64JAHsDAAQAAQpJE8iUAT8AAAAA.',
Re='Redia:BAAANQADCgQIBgAAAA==.Rei:BAAANQADCgQIBAAAAA==.Relvanas:BAAANQADCgMIAwAAAA==.',
Ri='Riverside:BAAANQAECgUIBgAAAA==.',
Ro='Roranmcstaby:BAAANQADCgIIAgAAAA==.',
['Rø']='Røk:BAAANQADCgEIAQAAAA==.',
Sa='Saaltaamea:BAAANQADCgMJAwAAAA==.Saelesth:BAAANQAECgIIAgAAAA==.Salvatora:BAAANQADCgYIBgAAAA==.Sambie:BAABNQAECn8XAAIFAAgKRQQW9gAWAQAFAAgKRQQW9gAWAQAAAA==.',
Sc='Scuffedfaith:BAAANQAECgQIBAAAAA==.Scuffedtotem:BAAANQAECgMIAwABNQAECgQIBAAIAAAAAA==.',
Se='Sefyra:BAABNQAECn8eAAIFAAgK7QVqwQCAAQAFAAgK7QVqwQCAAQAAAA==.Sentínel:BAAANQADCgEIAQAAAA==.Setelai:BAAANQAECgMJAwAAAA==.',
Sk='Skóll:BAAANQAECgcIEQAAAA==.',
Sl='Slimnipz:BAABNQAECn8VAAITAAgKqSBDOwByAgATAAgKqSBDOwByAgAAAA==.',
Sn='Sneakycress:BAAANQAECgUIDAAAAA==.Snolo:BAAANQADCgUJBQAAAA==.Snowyrose:BAAANQADCgIIAQABNQAECgoKPgAVAPMdAA==.',
So='Soulless:BAAANQAECgUIDQABNQAECgoKKgAMAA8cAA==.Soulstoned:BAAANQADCgYIBgAAAA==.',
Sp='Spiritwarior:BAACNQAFFH8fAAMTAAcKyh/FAgByAgATAAcKyh/FAgByAgAXAAEKUAPaNAA/AAA1AAQKfzYAAxMACgpBHxoNAPYCABMACgpBHxoNAPYCABcABAqDGrRLACoBAAAA.',
St='Starsky:BAAANQAECggICAAAAA==.Stone:BAAANQADCgEIAQABNQAECgoKPwAFAEMjAA==.Strangedraco:BAAANQAECgQIBAAAAA==.Strangelife:BAAANQABCgQIBAAAAA==.Strangesoul:BAAANQADCgYIBgAAAA==.Strangewood:BAABNQAECn84AAMKAAoKKxiTCwB/AgAKAAoKKxiTCwB/AgAJAAIK2Q5MnwBhAAAAAA==.',
Sw='Swiftlee:BAAANQAECgQIBgAAAA==.',
Sy='Sylvan:BAAANQAECggICQABNQAFFAYIEQACAGQeAA==.Sylvanà:BAAANQAECggICgAAAA==.',
Ta='Tasdan:BAAANQAECgQICQAAAA==.',
Te='Tejas:BAAANQADCggICgAAAA==.',
Th='Thotsnprayer:BAAANQADCggIEwAAAA==.Thunderfnk:BAAANQAECgcIEAAAAA==.Thursday:BAABNQAECn8cAAIMAAoKuyJuAwCBAwAMAAoKuyJuAwCBAwABNQAFFAIIBQAQAOQaAA==.',
To='Tommym:BAAANQAECgcIEQAAAA==.',
Tr='Tradravia:BAAANQADCgcIDAAAAA==.Trickydice:BAABNQAECn8cAAIGAAcKFRUDGABKAQAGAAcKFRUDGABKAQAAAA==.',
Tw='Twentythree:BAAANQADCgYIBgABNQAECgUIBgAIAAAAAA==.',
Va='Valdyr:BAABNQAECn8iAAIEAAgKpRe+qADOAQAEAAgKpRe+qADOAQAAAA==.Varmo:BAAANQADCggIDgAAAA==.',
Vy='Vyrianath:BAAANQAECgUICQAAAA==.',
Wa='Wakwanda:BAABNQAECn8uAAMYAAoKShTQKwAXAgAYAAoKShTQKwAXAgAZAAgKJxN8IwAWAgAAAA==.Wardsky:BAAANQAECgIIAwAAAA==.Wawaweewa:BAAANQADCgIIAgABNQAECgcIEAAIAAAAAA==.',
Wi='Witheredhope:BAABNQAECn8lAAMEAAkKKAcYkQAwAQAEAAkKKAcYkQAwAQACAAEKvQHvMAEmAAABNQAFFAcIHQAaABgGAA==.',
Wr='Wreckthar:BAABNQAECn83AAIEAAoK8yKLFADWAgAEAAoK8yKLFADWAgAAAA==.',
Za='Zarrada:BAAANQAECgEIAQAAAA==.',
Ze='Zenetrawr:BAABNQAECn82AAIbAAoKqA1KCgBKAQAbAAoKqA1KCgBKAQAAAA==.',
['Zô']='Zôrra:BAAANQAECgQIBAAAAA==.',
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
