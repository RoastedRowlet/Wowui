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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Protection','Unknown-Unknown','Paladin-Holy','DeathKnight-Blood','Paladin-Retribution','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Warrior-Protection','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Priest-Discipline','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Shaman-Enhancement','Mage-Frost','Rogue-Assassination','DemonHunter-Devourer','Hunter-Marksmanship','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abraxos:BAAANQABCgYICwAAAA==.',
Ar='Arcanejel:BAAANQABCgEIAQAAAA==.',
Az='Azrielle:BAAANQADCgEIAQAAAA==.',
Ba='Barlartwo:BAABNQAECn8VAAMBAAYKLAdbNQDtAAABAAYKLAdbNQDtAAACAAEKAABNMwEAAAAAAA==.Bazts:BAAANQADCgQIBAAAAA==.Baztt:BAAANQAECgQIBwAAAA==.Bazty:BAAANQADCgEIAQAAAA==.',
Be='Belthazaar:BAAANQAECgUIEAAAAA==.',
Bi='Biller:BAAANQADCgcIHAAAAA==.',
Bl='Blade:BAABNQAECn82AAIDAAoKVyIXGgBQAwADAAoKVyIXGgBQAwAAAA==.Blarneystone:BAAANQAECgUICQAAAA==.Blitzed:BAAANQAECgcICgABNQAECgoKNgADAFciAA==.Bluemoon:BAAANQADCgQJBwAAAA==.',
Bo='Bootybleaps:BAACNQAFFH8RAAIDAAcKbhqZEQClAQADAAcKbhqZEQClAQA1AAQKf0YAAgMACgp2JCUJAKoDAAMACgp2JCUJAKoDAAAA.Bootybsneaks:BAAANQAECgYIBgAAAA==.',
Br='Breadth:BAAANQADCgUIBQAAAA==.Breakingwind:BAAANQAECgQICAAAAA==.Brynhild:BAAANQAECgEIAQAAAA==.',
Bu='Bullievit:BAABNQAECn83AAIEAAoK9R4dHADnAgAEAAoK9R4dHADnAgAAAA==.',
Ch='Chistery:BAAANQAECgMIBAAAAA==.Chopsaw:BAAANQAECgQIBAAAAA==.',
Cm='Cmoobones:BAAANQAECgcICQAAAA==.',
Co='Cordi:BAAANQAECgQIBAAAAA==.',
Cr='Cropop:BAABNQAECn8qAAMFAAoK+h79BgChAgAFAAoK+h79BgChAgAGAAEK8wBDqQAEAAAAAA==.',
Da='Darallyn:BAAANQAECggICwAAAA==.Davik:BAAANQAECgEIAQAAAA==.',
De='Deathroyal:BAAANQADCgEIAQAAAA==.Delmair:BAAANQADCgYICQAAAA==.Demonicaxe:BAAANQADCgEIAQAAAA==.Dethcen:BAAANQAECgQIAwAAAA==.Deucalion:BAAANQADCgUICgAAAA==.',
Dr='Dracene:BAABNQAECn8UAAIHAAYKzwGQTQCyAAAHAAYKzwGQTQCyAAAAAA==.Dragosa:BAAANQADCgEIAQABNQAECggIDgAIAAAAAA==.Dreekxo:BAAANQAECgIIAgAAAA==.',
Du='Duf:BAAANQADCgEIAQAAAA==.',
Fa='Fafnir:BAABNQAECn8qAAMHAAoK/yAZCAAdAwAHAAoK/yAZCAAdAwAJAAMKBAenyACGAAAAAA==.',
Fl='Flaymignon:BAAANQADCgQIBAAAAA==.Fleshsicle:BAABNQAECn8qAAIKAAgKzQmJRQAnAQAKAAgKzQmJRQAnAQAAAA==.Flixs:BAAANQADCgEIAQABNQAECggICAAIAAAAAA==.',
Ga='Gamera:BAAANQAECgYICgAAAA==.Gankadin:BAABNQAECn8iAAILAAgKRxUMvQCiAQALAAgKRxUMvQCiAQAAAA==.',
Gb='Gb:BAABNQAECn8UAAMMAAcKHh0bJQAHAgAMAAcKHh0bJQAHAgANAAcK/RLjfQCfAQAAAA==.',
Ge='Gentile:BAAANQAECgUIBAAAAA==.',
Gl='Glassnops:BAABNQAECn8qAAIOAAoKZRLsagDdAQAOAAoKZRLsagDdAQAAAA==.',
Gr='Groobs:BAAANQADCgEIAQAAAA==.',
He='Hemlock:BAAANQADCgEIAQAAAA==.',
Ic='Icewolff:BAAANQAECgMIAwAAAA==.',
Ik='Ikinokoru:BAABNQAECn98AAIPAAoK7yUwBABuAwAPAAoK7yUwBABuAwAAAA==.',
Ir='Irene:BAAANQADCgYICgAAAA==.',
Je='Jeffren:BAAANQAECggICAAAAA==.',
Ji='Jinsho:BAABNQAECn9GAAMDAAoKeSRfCACwAwADAAoKeSRfCACwAwAQAAEKHhlVPQBLAAAAAA==.',
Ju='Julie:BAAANQAECgUIBwAAAA==.',
Ko='Kovo:BAABNQAECn8hAAIRAAoKExA7QADTAQARAAoKExA7QADTAQABNQAFFAQICgASACURAA==.Kovowolf:BAACNQAFFH8KAAISAAQKJRGJCwAAAQASAAQKJRGJCwAAAQA1AAQKf2IAAxIACgpEIqsLABADABIACgpEIqsLABADAAQABQqlEE5fAKUAAAAA.',
La='Laoch:BAAANQADCgIIAgAAAA==.',
Le='Leatherpapi:BAAANQADCgQIAwAAAA==.Lemonhead:BAAANQADCgMIAwAAAA==.',
Li='Linsay:BAACNQAFFH8YAAIMAAgKtxdCAgBzAgAMAAgKtxdCAgBzAgA1AAQKf0QAAgwACgrbJLkFABkDAAwACgrbJLkFABkDAAAA.',
Ll='Llara:BAAANQAECgEIAQAAAA==.',
Lo='Lotieos:BAABNQAECn87AAMTAAoK/w7qMQDgAQATAAoK/w7qMQDgAQAUAAgK/gj4bABfAQAAAA==.Lovelypwr:BAABNQAECn8dAAQMAAoKNBY+GgB6AgAMAAkKEhY+GgB6AgAVAAIK/wsVGAA9AAANAAEKgAiM+AA8AAAAAA==.',
Lu='Luçidity:BAABNQAECn85AAMRAAoK7RC3RgC6AQARAAkKyRK3RgC6AQAWAAgKwAqprwAQAQAAAA==.',
Ma='Mannera:BAABNQAECn8gAAMNAAoK2BlwLgCuAgANAAoK2BlwLgCuAgAMAAEKGBBtZAA0AAAAAA==.Marcus:BAAANQAECggIDgAAAA==.Matheris:BAABNQAECn8aAAIQAAkK+x/LCADEAgAQAAkK+x/LCADEAgAAAA==.Mawiyah:BAAANQAECgQIAgAAAA==.Max:BAAANQAECgQIBQABNQAECgoKVwAKADwhAA==.',
Mc='Mca:BAAANQAECgcIEAAAAA==.',
Mi='Minibow:BAAANQAECgEIAQAAAA==.Ministry:BAAANQADCgEIAQAAAA==.',
Mo='Monker:BAAANQAECgEIAQAAAA==.Moonchai:BAAANQADCgYIBgABNQAECgYICwAIAAAAAA==.',
Mu='Murdrmittens:BAAANQADCgcICQABNQADCggICwAIAAAAAA==.Muth:BAAANQAECggICwAAAA==.Muthra:BAAANQAECgQIBQABNQAECggICwAIAAAAAA==.Muthunter:BAAANQAECgUIDQABNQAECggICwAIAAAAAA==.',
Ne='Neceob:BAAANQABCgMIAwAAAA==.Nehemia:BAAANQABCgQIBQAAAA==.Never:BAACNQAFFH8kAAIXAAkKTxjoAQCrAgAXAAkKTxjoAQCrAgA1AAQKfxsAAxcACgrWHrAKAPkCABcACgrWHrAKAPkCABgAAQo+JLYYAGIAAAAA.Nezukokamado:BAABNQAECn8cAAIGAAYKjgfZWQAeAQAGAAYKjgfZWQAeAQAAAA==.',
Ni='Nikallnight:BAAANQAECgIIAgAAAA==.Nitalzit:BAABNQAECn8ZAAIZAAYK6QBsKAAoAAAZAAYK6QBsKAAoAAAAAA==.',
No='Nolan:BAAANQAECgQIBAAAAA==.',
Ob='Oblivionpwr:BAAANQAECgQIBAABNQAECgoKHQAMADQWAA==.',
Ok='Ok:BAAANQADCgEIAQAAAA==.',
Or='Oriah:BAAANQADCgMIAwAAAA==.',
Pa='Paliatarii:BAABNQAECn8kAAIUAAoK3hJBKgCSAQAUAAoK3hJBKgCSAQAAAA==.Pallyfever:BAAANQAECgIIAgAAAA==.',
Po='Pokito:BAAANQAECggICAAAAA==.',
Ra='Rabioso:BAAANQABCggIEAAAAA==.Ragamon:BAAANQADCgYIAwAAAA==.',
Re='Reimu:BAAANQADCgUIBQAAAA==.Repentia:BAAANQAECgUIDwAAAA==.Revanok:BAAANQADCgQIBAAAAA==.',
Ro='Rockaden:BAAANQADCggICQABNQAECggICwAIAAAAAA==.Roksharuwolf:BAABNQAECn88AAIRAAoK4RoaIwBgAgARAAoK4RoaIwBgAgABNQAECgkJGQAaAAsRAA==.Ronnie:BAABNQAECn8jAAIUAAkKXwjCaABuAQAUAAkKXwjCaABuAQAAAA==.',
Ru='Runa:BAAANQAECgcICgABNQAFFAQICgASACURAA==.',
Sa='Sadie:BAAANQAECggIEQAAAA==.Sahlberg:BAAANQADCggIEQAAAA==.Salebrah:BAAANQADCgIIAgAAAA==.',
Sc='Schnief:BAAANQADCgUIBQAAAA==.',
Se='Senkestsu:BAAANQADCgYICwAAAA==.Septwenty:BAAANQAECgEIAQAAAA==.',
Sh='Shammtastiç:BAAANQAECgMIBgAAAA==.',
Si='Sinley:BAAANQAECgMIBQAAAA==.',
Sn='Sncak:BAAANQADCgcIBwAAAA==.',
So='Soren:BAAANQABCgYIBwAAAA==.',
Sp='Spiritwolf:BAACNQAFFH8FAAIaAAMKnQvOBABDAAAaAAMKnQvOBABDAAA1AAQKf1IAAhoACgq/IvAHAHQCABoACgq/IvAHAHQCAAAA.Spiroheals:BAAANQADCgEIAQAAAA==.',
Sw='Swagcity:BAABNQAECn8rAAMRAAoKcBVTPgB8AgARAAoKQRVTPgB8AgAbAAUKZxO5HgB0AQAAAA==.Swagsauce:BAAANQAECgIIAgAAAA==.',
Sy='Symphony:BAAANQADCggIIQAAAA==.Syrax:BAABNQAECn8mAAIZAAcKCBBLEgASAQAZAAcKCBBLEgASAQABNQAECgoKVwAKADwhAA==.Syrieal:BAABNQAECn9XAAMKAAoKPCH1DgA3AwAKAAoKPCH1DgA3AwATAAEKXhHxqwA2AAAAAA==.',
['Så']='Såssy:BAAANQAECgQIBwAAAA==.',
Ta='Taiyla:BAABNQAECn9TAAMcAAoKwBLCEACaAQAOAAoKXhHDWwADAgAcAAgKfQ3CEACaAQAAAA==.Talithiala:BAABNQAECn8tAAMMAAkKEBHWJABeAQAMAAgKUw7WJABeAQANAAgKGAWhrADaAAAAAA==.Tallai:BAAANQADCgYICQAAAA==.Taurelin:BAAANQAECgIIAgAAAA==.Taurentastic:BAAANQAECgUIBQABNQAECgoKRgADAHkkAA==.',
Te='Tejano:BAAANQADCgIIAgAAAA==.',
Th='Therionwolf:BAABNQAECn8ZAAIaAAkKCxHfEAC5AQAaAAkKCxHfEAC5AQAAAA==.Thorgrazer:BAAANQADCgYIBgABNQAECgoKLgAdAG8TAA==.Thorin:BAAANQADCgIIAgAAAA==.',
To='Toomuchpwr:BAAANQADCgQIBAABNQAECgoKHQAMADQWAA==.',
Tr='Trip:BAABNQAECn8jAAQWAAoKqBrVoAA0AQAWAAYK5RTVoAA0AQAbAAUKyA5SIwAnAQARAAMKggyXvwCLAAAAAA==.Tristran:BAAANQAECgUICQABNQAECggIDgAIAAAAAA==.',
Ts='Tsabotavok:BAAANQADCgYICwAAAA==.',
Tu='Tubbybuddy:BAABNQAECn8rAAIbAAoKThOKEAANAgAbAAoKThOKEAANAgAAAA==.Tunafish:BAAANQADCgQIBAAAAA==.',
Un='Uniblue:BAACNQAFFH8XAAMWAAkK5xSrBAAwAgAWAAkK5xSrBAAwAgARAAIK/iHgIQClAAA1AAQKfzEAAxYACgo5H7A3AIACABYACQpjHrA3AIACABEACQoUInU9AIACAAAA.',
Va='Vamperella:BAAANQAECgQIEQAAAA==.Varashai:BAABNQAECn83AAIeAAoKrRt4DACLAgAeAAoKrRt4DACLAgAAAA==.',
Wa='Wanye:BAABNQAECn8lAAMPAAoKnBnUQQClAgAPAAoKixjUQQClAgAfAAYKURaTMwCxAQAAAA==.',
We='Wenzr:BAAANQADCggICwAAAA==.',
Wh='Whisperdeath:BAAANQABCgUIBQAAAA==.',
Wo='Wolffbane:BAAANQAECggICAAAAA==.Wolffspirit:BAAANQAECgMIAwABNQAFFAQICgASACURAA==.',
Yi='Yiumi:BAABNQAECn8mAAIgAAoKGg+1AgDDAQAgAAoKGg+1AgDDAQAAAA==.',
Yl='Ylvis:BAABNQAECn84AAIPAAoKPhC6YwBOAgAPAAoKPhC6YwBOAgAAAA==.',
Yo='You:BAABNQAECn8gAAMKAAoKnRWEPQAMAgAKAAoKnRWEPQAMAgATAAEKwgMeuwAsAAAAAA==.',
Yu='Yulogee:BAAANQAECggICgAAAA==.',
Za='Zabrozo:BAAANQADCgEIAQAAAA==.',
Ze='Zemzelett:BAABNQAECn8XAAIRAAYK9RbtggCdAQARAAYK9RbtggCdAQAAAA==.Zephy:BAAANQAECgYICwAAAA==.Zerofuntion:BAAANQAECgIIAgAAAA==.Zerokillz:BAAANQADCgEIAQAAAA==.',
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
