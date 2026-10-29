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

local lookup = {'Warlock-Destruction','Warrior-Arms','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Protection','Unknown-Unknown','DeathKnight-Blood','Paladin-Retribution','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Warrior-Protection','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Shaman-Enhancement','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','DemonHunter-Devourer','Hunter-Marksmanship','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abraxos:BAAANQABCgYICwAAAA==.',
Ar='Arcanejel:BAAANQAECgEIAQAAAA==.',
Az='Azrielle:BAAANQADCgEIAQAAAA==.',
Ba='Barlartwo:BAABNQAECn8UAAIBAAYKLAc9EQCRAAABAAYKLAc9EQCRAAAAAA==.Bazts:BAAANQADCgQIBAAAAA==.Baztt:BAAANQAECgQICAAAAA==.Bazty:BAAANQADCgEIAQAAAA==.',
Be='Belthazaar:BAAANQAECgUIEgAAAA==.',
Bi='Biller:BAAANQADCgcIHAAAAA==.',
Bl='Blade:BAABNQAECn82AAICAAoKVyIXGgBQAwACAAoKVyIXGgBQAwAAAA==.Blarneystone:BAAANQAECgUICgAAAA==.Blitzed:BAAANQAECgcICwABNQAECgoKNgACAFciAA==.Bluemoon:BAAANQADCgQJBwAAAA==.',
Bo='Bootybleaps:BAACNQAFFH8QAAICAAYK0xqZEQClAQACAAYK0xqZEQClAQA1AAQKf0YAAgIACgp2JCUJAKoDAAIACgp2JCUJAKoDAAAA.Bootybsneaks:BAAANQAECgYIBgAAAA==.',
Br='Breadth:BAAANQADCgUIBQAAAA==.Breakingwind:BAAANQADCggIBwAAAA==.Brynhild:BAAANQAECgEIAQAAAA==.',
Bu='Bullievit:BAABNQAECn8vAAIDAAoKQh0dHADnAgADAAoKQh0dHADnAgAAAA==.',
Ch='Chistery:BAAANQAECgMIBQAAAA==.',
Cm='Cmoobones:BAAANQAECgcIDQAAAA==.',
Co='Cordi:BAAANQADCgcICwAAAA==.',
Cr='Cropop:BAABNQAECn8iAAMEAAkKdx79BgChAgAEAAkKdx79BgChAgAFAAEK8wBDqQAEAAAAAA==.',
Da='Darallyn:BAAANQAECgYICQAAAA==.Davik:BAAANQAECgEIAwAAAA==.',
De='Delmair:BAAANQADCgYICQAAAA==.Demonicaxe:BAAANQADCgEIAQAAAA==.Dethcen:BAAANQAECgQIBAAAAA==.Deucalion:BAAANQADCgUICgAAAA==.',
Do='Dog:BAAANQAECgEIAwAAAA==.',
Dr='Dracene:BAABNQAECn8UAAIGAAYKzwGQTQCyAAAGAAYKzwGQTQCyAAAAAA==.Dragosa:BAAANQADCgEIAQABNQAECgYIDAAHAAAAAA==.Dreekxo:BAAANQAECgIIAgAAAA==.',
Du='Duf:BAAANQADCgEIAQAAAA==.',
Fa='Fafnir:BAABNQAECn8jAAIGAAoK/yAZCAAdAwAGAAoK/yAZCAAdAwAAAA==.',
Fl='Flaymignon:BAAANQADCgQIBAAAAA==.Fleshsicle:BAABNQAECn8qAAIIAAgKzQlBLQA7AQAIAAgKzQlBLQA7AQAAAA==.Flixs:BAAANQADCgEIAQABNQADCggIAwAHAAAAAA==.',
Ga='Galyn:BAAANQAECgEIAQABNQAECgYICQAHAAAAAA==.Gamera:BAAANQAECgYIDAAAAA==.Gankadin:BAABNQAECn8dAAIJAAgKuBMMvQCiAQAJAAgKuBMMvQCiAQAAAA==.',
Gb='Gb:BAABNQAECn8UAAMKAAcKHh0bJQAHAgAKAAcKHh0bJQAHAgALAAcK/RLjfQCfAQAAAA==.',
Ge='Gentile:BAAANQAECgUICAAAAA==.',
Gl='Glassnops:BAABNQAECn8mAAIMAAoKZRKPQwDpAQAMAAoKZRKPQwDpAQAAAA==.',
Gr='Groobs:BAAANQADCgEIAQAAAA==.',
Ic='Icewolff:BAAANQABCgMIBQAAAA==.',
Ik='Ikinokoru:BAABNQAECn9TAAINAAoK6iQZBQC7AwANAAoK6iQZBQC7AwAAAA==.',
Ir='Irene:BAAANQAECgEIAQAAAA==.',
Je='Jeffren:BAAANQADCggIAwAAAA==.',
Ji='Jinsho:BAABNQAECn9CAAMCAAoKeSRfCACwAwACAAoKeSRfCACwAwAOAAEKHhlaKgBRAAAAAA==.',
Ju='Julie:BAAANQAECgUIDAAAAA==.',
Ko='Kovo:BAAANQAECggIEAABNQAFFAMICQAPALsVAA==.Kovowolf:BAACNQAFFH8JAAIPAAMKuxU5CADYAAAPAAMKuxU5CADYAAA1AAQKf00AAw8ACgqtIasLABADAA8ACgqtIasLABADAAMAAQoAABO1AC4AAAAA.',
La='Laoch:BAAANQADCgIIAgAAAA==.',
Le='Leatherpapi:BAAANQADCgQIAwAAAA==.Lemonhead:BAAANQADCgMIAwAAAA==.',
Li='Linsay:BAACNQAFFH8WAAIKAAcKVhdCAgBzAgAKAAcKVhdCAgBzAgA1AAQKf0AAAgoACgpIJFcDABEDAAoACgpIJFcDABEDAAAA.',
Ll='Llara:BAAANQAECgEIAQAAAA==.',
Lo='Lotieos:BAABNQAECn8ZAAMQAAgK5gv4bABfAQAQAAgK/gj4bABfAQARAAcKBAu5RAAEAQAAAA==.Lovelypwr:BAABNQAECn8dAAQKAAoKNBY+GgB6AgAKAAkKEhY+GgB6AgALAAEKgAgNwwA7AAASAAIK/ws0EAA7AAAAAA==.',
Lu='Luçidity:BAABNQAECn8nAAMTAAgKfRGprwAQAQATAAYKjQuprwAQAQAUAAcKMgu9WQD/AAAAAA==.',
Ma='Mannera:BAABNQAECn8bAAMLAAoKbxlwLgCuAgALAAoKbxlwLgCuAgAKAAEKGBCXSAA0AAAAAA==.Marcus:BAAANQAECgYIDAAAAA==.Matheris:BAABNQAECn8aAAIOAAkK+x/LCADEAgAOAAkK+x/LCADEAgAAAA==.Mawiyah:BAAANQAECgQIBgAAAA==.Max:BAAANQAECgIIAwABNQAECgoKRgAIADwhAA==.',
Mc='Mca:BAAANQAECgMIAwAAAA==.',
Mi='Minibow:BAAANQADCgcIBwAAAA==.Ministry:BAAANQADCgEIAQAAAA==.',
Mo='Monker:BAAANQAECgEIAQAAAA==.Moonchai:BAAANQADCgYIBgABNQAECgUIBgAHAAAAAA==.',
Mu='Murdrmittens:BAAANQADCgUIBwABNQADCggICwAHAAAAAA==.Muth:BAAANQAECggIEQAAAA==.Muthra:BAAANQAECgUIBgABNQAECggIEQAHAAAAAA==.Muthunter:BAAANQAECgUIEQABNQAECggIEQAHAAAAAA==.',
Ne='Neceob:BAAANQAECgEIAgAAAA==.Nehemia:BAAANQABCgQIBQAAAA==.Never:BAACNQAFFH8kAAIVAAkKTxjoAQCrAgAVAAkKTxjoAQCrAgA1AAQKfxsAAxUACgrWHrAKAPkCABUACgrWHrAKAPkCABYAAQo+JDERAGcAAAAA.Nezukokamado:BAABNQAECn8cAAIFAAYKjgfZWQAeAQAFAAYKjgfZWQAeAQAAAA==.',
Ni='Nikallnight:BAAANQAECgIIAgAAAA==.Nitalzit:BAAANQAECgYIEAAAAA==.',
No='Nolan:BAAANQAECgQIBAAAAA==.',
Ob='Oblivionpwr:BAAANQAECgQIBgABNQAECgoKHQAKADQWAA==.',
Ok='Ok:BAAANQADCgEIAQAAAA==.',
Or='Oriah:BAAANQADCgMIAwAAAA==.',
Pa='Paliatarii:BAABNQAECn8hAAIQAAgKohP5SwDlAQAQAAgKohP5SwDlAQAAAA==.',
Po='Pokito:BAAANQAECggIAgAAAA==.',
Ra='Rabioso:BAAANQABCggIEAAAAA==.Ragamon:BAAANQADCgUIAgAAAA==.',
Re='Reimu:BAAANQADCgUIBQAAAA==.Repentia:BAAANQAECgYIDwAAAA==.',
Ro='Rockaden:BAAANQADCggICQABNQAECggIEQAHAAAAAA==.Roidsnmolly:BAAANQAECggIBAAAAA==.Roksharuwolf:BAABNQAECn8dAAIUAAkKbRZ+OQBvAQAUAAkKbRZ+OQBvAQABNQADCggIDwAHAAAAAA==.Ronnie:BAABNQAECn8jAAIQAAkKXwjCaABuAQAQAAkKXwjCaABuAQAAAA==.',
Ru='Runa:BAAANQAECgQICQABNQAFFAMICQAPALsVAA==.',
Sa='Sadie:BAAANQAECgYIDAAAAA==.Sahlberg:BAAANQADCggIEQAAAA==.Salebrah:BAAANQABCgYICgAAAA==.',
Sc='Schnief:BAAANQAECgEIAwAAAA==.',
Se='Senkestsu:BAAANQAECgEIAQAAAA==.Septwenty:BAAANQAECgEIAQAAAA==.',
Sh='Shammtastiç:BAAANQADCgEIAQAAAA==.',
Sn='Sncak:BAAANQADCgcIBwAAAA==.',
So='Soren:BAAANQABCgYIBwAAAA==.',
Sp='Spiritwolf:BAABNQAECn8/AAIXAAoKAyD/BwDbAgAXAAoKAyD/BwDbAgAAAA==.Spiroheals:BAAANQADCgEIAQAAAA==.',
Sw='Swagcity:BAABNQAECn8rAAMUAAoKcBVTPgB8AgAUAAoKQRVTPgB8AgAYAAUKZxO5HgB0AQAAAA==.Swagsauce:BAAANQAECgIIAwAAAA==.',
Sy='Symphony:BAAANQADCggIHwAAAA==.Syrax:BAABNQAECn8ZAAIZAAYKnhHuDgDmAAAZAAYKnhHuDgDmAAABNQAECgoKRgAIADwhAA==.Syrieal:BAABNQAECn9GAAMIAAoKPCH1DgA3AwAIAAoKPCH1DgA3AwARAAEKXhHxqwA2AAAAAA==.',
['Så']='Såssy:BAAANQAECgQIBAAAAA==.',
Ta='Taiyla:BAABNQAECn8/AAMaAAoKGxDCEACaAQAMAAoKxA1wRwDcAQAaAAgKfQ3CEACaAQAAAA==.Talithiala:BAABNQAECn8fAAMKAAgKihatIgDyAAAKAAYKAw+tIgDyAAALAAcKHgSKvgDfAAAAAA==.Tallai:BAAANQADCgYICQAAAA==.Taurelin:BAAANQAECgIIAgAAAA==.Taurentastic:BAAANQAECgEIAgABNQAECgoKQgACAHkkAA==.',
Te='Tejano:BAAANQADCgIIAgAAAA==.',
Th='Therionwolf:BAAANQADCggIDwAAAA==.Thorgrazer:BAAANQADCgYIBgABNQAECgoKKQAbAPYRAA==.Thorin:BAAANQADCgIIAgAAAA==.',
To='Toomuchpwr:BAAANQADCgQIBAABNQAECgoKHQAKADQWAA==.',
Tr='Trip:BAABNQAECn8hAAQTAAoKohvVoAA0AQATAAUKERTVoAA0AQAYAAUKyA5SIwAnAQAUAAMKggyYhgCRAAAAAA==.Tristran:BAAANQAECgQIBgABNQAECgYIDAAHAAAAAA==.',
Ts='Tsabotavok:BAAANQADCgYICwAAAA==.',
Tu='Tubbybuddy:BAABNQAECn8jAAIYAAkKkxJ8DQC6AQAYAAkKkxJ8DQC6AQAAAA==.Tunafish:BAAANQADCgQIBAAAAA==.',
Un='Uniblue:BAACNQAFFH8RAAMTAAgK0BKrBAAwAgATAAgK0BKrBAAwAgAUAAIKDhfgIQClAAA1AAQKfywAAxMACgoXH7A3AIACABMACQpjHrA3AIACABQACQq1IXU9AIACAAAA.',
Va='Vamperella:BAAANQAECgMIDgAAAA==.Varashai:BAABNQAECn8cAAIcAAoKuQqDIQAcAQAcAAoKuQqDIQAcAQAAAA==.',
Wa='Wanye:BAABNQAECn8lAAMNAAoKnBnUQQClAgANAAoKixjUQQClAgAdAAYKURaTMwCxAQAAAA==.',
We='Wenzr:BAAANQADCggICwAAAA==.',
Wh='Whisperdeath:BAAANQABCgUIBQAAAA==.',
Yi='Yiumi:BAABNQAECn8mAAIeAAoKGg8bAQD0AQAeAAoKGg8bAQD0AQAAAA==.',
Yl='Ylvis:BAABNQAECn80AAINAAoKYA+6YwBOAgANAAoKYA+6YwBOAgAAAA==.',
Yo='You:BAABNQAECn8gAAMIAAoKnRWEPQAMAgAIAAoKnRWEPQAMAgARAAEKwgMhjgAuAAAAAA==.',
Yu='Yulogee:BAAANQAECggIEAAAAA==.',
Za='Zabrozo:BAAANQADCgEIAQAAAA==.',
Ze='Zemzelett:BAABNQAECn8XAAIUAAYK9RbtggCdAQAUAAYK9RbtggCdAQAAAA==.Zephy:BAAANQAECgUIBgAAAA==.Zerofuntion:BAAANQAECgIIAgAAAA==.Zerokillz:BAAANQADCgEIAQAAAA==.',
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
