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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Protection','Unknown-Unknown','Paladin-Holy','DeathKnight-Blood','Paladin-Retribution','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Warrior-Protection','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Priest-Discipline','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Shaman-Enhancement','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','DemonHunter-Devourer','Hunter-Marksmanship','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abraxos:BAAANQADCgEIAQAAAA==.',
Ar='Arcanejel:BAAANQABCgEIAQAAAA==.',
Au='Auruvirtus:BAAANQADCgEIAQAAAA==.',
Az='Azrielle:BAAANQADCgEIAgAAAA==.',
Ba='Barlartwo:BAABNQAECn8VAAMBAAYKLAdMFgCPAAABAAYKLAdMFgCPAAACAAEKAACcGgEAAAAAAA==.Bazts:BAAANQADCgQIBAAAAA==.Baztt:BAAANQAECgQIBwAAAA==.Bazty:BAAANQADCgEIAQAAAA==.',
Be='Belthazaar:BAAANQAECgUIDgAAAA==.',
Bi='Biller:BAAANQADCgcIHAAAAA==.',
Bl='Blade:BAABNQAECn82AAIDAAoKVyIXGgBQAwADAAoKVyIXGgBQAwAAAA==.Blarneystone:BAAANQAECgUICQAAAA==.Blitzed:BAAANQAECgcICwABNQAECgoKNgADAFciAA==.Bluemoon:BAAANQADCgQJBwAAAA==.',
Bo='Bootybleaps:BAACNQAFFH8RAAIDAAcKbhqZEQClAQADAAcKbhqZEQClAQA1AAQKf0YAAgMACgp2JCUJAKoDAAMACgp2JCUJAKoDAAAA.Bootybsneaks:BAAANQAECgYIBgAAAA==.Bosshoggy:BAAANQADCgEIAQAAAA==.',
Br='Breadth:BAAANQADCgUIBgAAAA==.Breakingwind:BAAANQAECgMIAwAAAA==.Brynhild:BAAANQAECgEIAQAAAA==.',
Bu='Bullievit:BAABNQAECn8zAAIEAAoKIh4dHADnAgAEAAoKIh4dHADnAgAAAA==.',
Ch='Chistery:BAAANQAECgMIBAAAAA==.',
Cm='Cmoobones:BAAANQAECgcICwAAAA==.',
Co='Cordi:BAAANQADCgcIDAAAAA==.',
Cr='Cropop:BAABNQAECn8jAAMFAAoKKx79BgChAgAFAAoKKx79BgChAgAGAAEK8wBDqQAEAAAAAA==.',
Da='Darallyn:BAAANQAECgcICgAAAA==.Davik:BAAANQAECgEIAQAAAA==.',
De='Delmair:BAAANQADCgYICQAAAA==.Demonicaxe:BAAANQADCgEIAQAAAA==.Dethcen:BAAANQAECgQIBAAAAA==.Deucalion:BAAANQADCgYICwAAAA==.',
Dr='Dracene:BAABNQAECn8UAAIHAAYKzwGQTQCyAAAHAAYKzwGQTQCyAAAAAA==.Dragosa:BAAANQADCgEIAQABNQAECggIDAAIAAAAAA==.Dreekxo:BAAANQAECgIIAgAAAA==.',
Du='Duf:BAAANQADCgEIAQAAAA==.',
Fa='Fafnir:BAABNQAECn8mAAMHAAoK/yAZCAAdAwAHAAoK/yAZCAAdAwAJAAIKtAZNywBVAAAAAA==.',
Fl='Flaymignon:BAAANQADCgQIBAAAAA==.Fleshsicle:BAABNQAECn8qAAIKAAgKzQkqOgAwAQAKAAgKzQkqOgAwAQAAAA==.Flixs:BAAANQADCgEIAQABNQADCggIAwAIAAAAAA==.',
Ga='Galyn:BAAANQAECgEIAQABNQAECgcICgAIAAAAAA==.Gamera:BAAANQAECgYICwAAAA==.Gankadin:BAABNQAECn8fAAILAAgKixQMvQCiAQALAAgKixQMvQCiAQAAAA==.',
Gb='Gb:BAABNQAECn8UAAMMAAcKHh0bJQAHAgAMAAcKHh0bJQAHAgANAAcK/RLjfQCfAQAAAA==.',
Ge='Gentile:BAAANQAECgUIBgAAAA==.',
Gl='Glassnops:BAABNQAECn8qAAIOAAoKZRK0WADhAQAOAAoKZRK0WADhAQAAAA==.',
Gr='Groobs:BAAANQADCgEIAgAAAA==.',
He='Hemlock:BAAANQADCgEIAQAAAA==.',
Ic='Icewolff:BAAANQADCgEIAQAAAA==.',
Ik='Ikinokoru:BAABNQAECn9jAAIPAAoKoSUsBABhAwAPAAoKoSUsBABhAwAAAA==.',
Ir='Irene:BAAANQADCgYIDAAAAA==.',
Je='Jeffren:BAAANQADCggIAwAAAA==.',
Ji='Jinsho:BAABNQAECn9GAAMDAAoKeSRfCACwAwADAAoKeSRfCACwAwAQAAEKHhm3MwBNAAAAAA==.',
Ju='Julie:BAAANQAECgUIBwAAAA==.',
Ko='Kovo:BAABNQAECn8WAAIRAAgKNwycXgAvAQARAAgKNwycXgAvAQABNQAFFAQICgASACURAA==.Kovowolf:BAACNQAFFH8KAAISAAQKJRG+CAARAQASAAQKJRG+CAARAQA1AAQKf1UAAxIACgo3IqsLABADABIACgo3IqsLABADAAQAAQoAABO1AC4AAAAA.',
La='Laoch:BAAANQADCgIIAgAAAA==.',
Le='Leatherpapi:BAAANQADCgQIBgAAAA==.Lemonhead:BAAANQADCgMIAwAAAA==.',
Li='Linsay:BAACNQAFFH8WAAIMAAcKVhdCAgBzAgAMAAcKVhdCAgBzAgA1AAQKf0MAAgwACgpIJCoFAAwDAAwACgpIJCoFAAwDAAAA.',
Ll='Llara:BAAANQAECgEIAQAAAA==.',
Lo='Lotieos:BAABNQAECn8mAAMTAAoKpwxtLwCxAQATAAoK5wttLwCxAQAUAAgK/gj4bABfAQAAAA==.Lovelypwr:BAABNQAECn8dAAQMAAoKNBY+GgB6AgAMAAkKEhY+GgB6AgANAAEKgAiM+AA8AAAVAAIK/wszFAA7AAAAAA==.',
Lu='Luçidity:BAABNQAECn8vAAMRAAkKVRKYTwBgAQARAAgKgRGYTwBgAQAWAAYK/AyprwAQAQAAAA==.',
Ma='Mannera:BAABNQAECn8eAAMNAAoK2BlwLgCuAgANAAoK2BlwLgCuAgAMAAEKGBA4VgA0AAAAAA==.Marcus:BAAANQAECggIDAAAAA==.Masaco:BAAANQAECgEIAQAAAA==.Matheris:BAABNQAECn8aAAIQAAkK+x/LCADEAgAQAAkK+x/LCADEAgAAAA==.Mawiyah:BAAANQAECgQIBAAAAA==.Max:BAAANQAECgIIAgABNQAECgoKUAAKADwhAA==.',
Mc='Mca:BAAANQAECggIDAAAAA==.',
Mi='Minibow:BAAANQADCgcIBwAAAA==.Ministry:BAAANQADCgEIAQAAAA==.',
Mo='Monker:BAAANQAECgEIAQAAAA==.Moonchai:BAAANQADCgYIBgABNQAECgYICwAIAAAAAA==.',
Mu='Murdrmittens:BAAANQADCgUICgABNQADCggIDAAIAAAAAA==.Muth:BAAANQAECggIDAAAAA==.Muthra:BAAANQAECgUIBwABNQAECggIDAAIAAAAAA==.Muthunter:BAAANQAECgUIDQABNQAECggIDAAIAAAAAA==.',
Ne='Neceob:BAAANQAECgEIAgAAAA==.Nehemia:BAAANQADCgEIAgAAAA==.Never:BAACNQAFFH8kAAIXAAkKTxjoAQCrAgAXAAkKTxjoAQCrAgA1AAQKfxsAAxcACgrWHrAKAPkCABcACgrWHrAKAPkCABgAAQo+JCkVAGQAAAAA.Nezukokamado:BAABNQAECn8cAAIGAAYKjgfZWQAeAQAGAAYKjgfZWQAeAQAAAA==.',
Ni='Nikallnight:BAAANQAECgIIAgAAAA==.Nitalzit:BAAANQAECgYIDgAAAA==.',
No='Nolan:BAAANQAECgQIBAAAAA==.',
Ob='Oblivionpwr:BAAANQAECgQIBQABNQAECgoKHQAMADQWAA==.',
Ok='Ok:BAAANQADCgEIAgAAAA==.',
Or='Oriah:BAAANQADCgMIAwAAAA==.',
Pa='Paliatarii:BAABNQAECn8jAAIUAAkKZROHKQBlAQAUAAkKZROHKQBlAQAAAA==.',
Po='Pokito:BAAANQAECggIBwAAAA==.',
Ra='Rabioso:BAAANQADCgEIAgAAAA==.Ragamon:BAAANQADCgYIAwAAAA==.',
Re='Reimu:BAAANQADCgUIBQAAAA==.Repentia:BAAANQAECgUIDwAAAA==.Revanok:BAAANQADCgMIAQAAAA==.',
Ro='Rockaden:BAAANQADCggICgABNQAECggIDAAIAAAAAA==.Roidsnmolly:BAAANQAECggIAQAAAA==.Roksharuwolf:BAABNQAECn8oAAIRAAkKzhe2KgD+AQARAAkKzhe2KgD+AQABNQAECggICQAIAAAAAA==.Ronnie:BAABNQAECn8jAAIUAAkKXwjCaABuAQAUAAkKXwjCaABuAQAAAA==.',
Ru='Runa:BAAANQAECgQIBQABNQAFFAQICgASACURAA==.',
Sa='Sadie:BAAANQAECgYICwAAAA==.Sahlberg:BAAANQADCggIEgAAAA==.Salebrah:BAAANQADCgEIAQAAAA==.',
Sc='Schnief:BAAANQADCgUIBQAAAA==.',
Se='Senkestsu:BAAANQAECgEIAQAAAA==.Septwenty:BAAANQAECgEIAQAAAA==.',
Sh='Shammtastiç:BAAANQAECgMIBAAAAA==.',
Sn='Sncak:BAAANQADCgcIBwAAAA==.',
So='Soren:BAAANQADCgEIAQAAAA==.',
Sp='Spiritwolf:BAACNQAFFH8FAAIZAAMKnQvoAwBDAAAZAAMKnQvoAwBDAAA1AAQKf0gAAhkACgosIVEHAEICABkACgosIVEHAEICAAAA.Spiroheals:BAAANQADCgEIAQAAAA==.',
Sw='Swagcity:BAABNQAECn8rAAMRAAoKcBVTPgB8AgARAAoKQRVTPgB8AgAaAAUKZxO5HgB0AQAAAA==.Swagsauce:BAAANQAECgIIAgAAAA==.',
Sy='Symphony:BAAANQADCggIJAAAAA==.Syrax:BAABNQAECn8eAAIbAAcKBxB8DwAUAQAbAAcKBxB8DwAUAQABNQAECgoKUAAKADwhAA==.Syrieal:BAABNQAECn9QAAMKAAoKPCH1DgA3AwAKAAoKPCH1DgA3AwATAAEKXhHxqwA2AAAAAA==.',
['Så']='Såssy:BAAANQAECgQIBAAAAA==.',
Ta='Taiyla:BAABNQAECn9JAAMcAAoKghHCEACaAQAOAAoKIBDjUAD2AQAcAAgKfQ3CEACaAQAAAA==.Talithiala:BAABNQAECn8oAAMMAAkKcxDjHgBXAQAMAAgKnA3jHgBXAQANAAgKGAXTlQDgAAAAAA==.Tallai:BAAANQADCgYICQAAAA==.Taurelin:BAAANQAECgMIAwAAAA==.Taurentastic:BAAANQAECgUIBwABNQAECgoKRgADAHkkAA==.',
Te='Tejano:BAAANQADCgIIAgAAAA==.',
Th='Therionwolf:BAAANQAECggICQAAAA==.Thorgrazer:BAAANQADCgYIBgABNQAECgoKLQAdAE4SAA==.Thorin:BAAANQADCgIIAgAAAA==.',
To='Toomuchpwr:BAAANQADCgQIBgABNQAECgoKHQAMADQWAA==.',
Tr='Treetopp:BAAANQADCgEIAQAAAA==.Trip:BAABNQAECn8iAAQWAAoKshvVoAA0AQAWAAUKMBTVoAA0AQAaAAUKyA5SIwAnAQARAAMKggxYpACLAAAAAA==.Tristran:BAAANQAECgQIBAABNQAECggIDAAIAAAAAA==.',
Ts='Tsabotavok:BAAANQADCgYICwAAAA==.',
Tu='Tubbybuddy:BAABNQAECn8rAAIaAAoKThMVDQAQAgAaAAoKThMVDQAQAgAAAA==.Tunafish:BAAANQADCgQIBAAAAA==.',
Un='Uniblue:BAACNQAFFH8RAAMWAAgK0BKrBAAwAgAWAAgK0BKrBAAwAgARAAIKDhfgIQClAAA1AAQKfy8AAxYACgo5H7A3AIACABYACQpjHrA3AIACABEACQoUInU9AIACAAAA.',
Va='Vamperella:BAAANQAECgQIDQAAAA==.Varashai:BAABNQAECn8nAAIeAAoKYRbBDwAxAgAeAAoKYRbBDwAxAgAAAA==.',
Wa='Wanye:BAABNQAECn8lAAMPAAoKnBnUQQClAgAPAAoKixjUQQClAgAfAAYKURaTMwCxAQAAAA==.',
We='Wenzr:BAAANQADCggIDAAAAA==.',
Wh='Whisperdeath:BAAANQADCgEIAQAAAA==.',
Wo='Wolffspirit:BAAANQABCgYICQABNQAFFAQICgASACURAA==.',
Yi='Yiumi:BAABNQAECn8mAAIgAAoKGg/lAQDRAQAgAAoKGg/lAQDRAQAAAA==.',
Yl='Ylvis:BAABNQAECn84AAIPAAoKPhC6YwBOAgAPAAoKPhC6YwBOAgAAAA==.',
Yo='You:BAABNQAECn8gAAMKAAoKnRWEPQAMAgAKAAoKnRWEPQAMAgATAAEKwgMzowAtAAAAAA==.',
Yu='Yulogee:BAAANQAECggIDwAAAA==.',
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
