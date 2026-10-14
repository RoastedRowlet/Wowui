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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Paladin-Holy','DemonHunter-Devourer','Unknown-Unknown','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Mage-Frost','Paladin-Retribution','Mage-Arcane','Shaman-Restoration','Warrior-Arms','Evoker-Preservation','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Druid-Restoration','Druid-Balance',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Absolver:BAAANQADCgYIDwAAAA==.',
Ad='Adabisi:BAAANQADCgEIBAAAAA==.Addu:BAAANQADCgMIAwAAAA==.Adiforis:BAABNQAECn8eAAMBAAgK1hNpNQD/AQABAAgK1hNpNQD/AQACAAMKcQW9pACHAAAAAA==.Adobo:BAABNQAECn8zAAIDAAkKEBWZRgBZAgADAAkKEBWZRgBZAgAAAA==.Adolhay:BAAANQADCgMIAwAAAA==.',
Al='Aljeron:BAAANQADCgIJAgAAAA==.Allysson:BAAANQAECgYIEgAAAA==.Alrekur:BAAANQAECgQIBAAAAA==.Alyestra:BAAANQAECgMIAwAAAA==.',
An='Animyst:BAAANQAECgcIDwABNQAECgkJKAAEAHoeAA==.Anipaltu:BAABNQAECn8cAAIFAAkKKx3BHgD0AgAFAAkKKx3BHgD0AgABNQAECgkJKAAEAHoeAA==.Aniron:BAAANQAECgUICQABNQAECgkJKAAEAHoeAA==.Anirot:BAABNQAECn8oAAIEAAkKeh5KFgAfAwAEAAkKeh5KFgAfAwAAAA==.Annalissa:BAAANQADCgYIBgAAAA==.',
Ar='Aranta:BAAANQAECgYIEQAAAA==.Arieldhas:BAAANQADCggIFwAAAA==.',
As='Astren:BAAANQAECgUIDgAAAA==.Asynsia:BAABNQAECn8nAAIGAAgKZyEHDQARAwAGAAgKZyEHDQARAwAAAA==.',
['Aõ']='Aõnar:BAAANQADCgEIAQAAAA==.',
Ba='Bartholomew:BAAANQAECgMIBAABNQAECgkJOAAEAHEdAA==.',
Be='Beertje:BAAANQAECgEIAgAAAA==.Bellemore:BAAANQAECgQIAgAAAA==.',
Bi='Bienfaiseur:BAABNQAECn8cAAIEAAcKOSbgGQALAwAEAAcKOSbgGQALAwAAAA==.Bigdamhero:BAAANQADCgIIAgAAAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Blackcode:BAAANQAECgYICwAAAA==.',
Br='Breadbringer:BAAANQADCggICwAAAA==.Breezybb:BAAANQADCgQIBAAAAA==.',
Bu='Buckshotapie:BAAANQADCgIIAgAAAA==.Bulgrim:BAAANQADCgYIDQAAAA==.Bunrÿl:BAAANQAECgIIAgAAAA==.Busterheiman:BAAANQADCgYIDwAAAA==.Butterrz:BAAANQADCgMIAwABNQAECgYIEAAHAAAAAA==.',
Ce='Cearylin:BAAANQAECgUIBQAAAA==.Cerealkillah:BAAANQADCgMIAwAAAA==.',
Ch='Chasy:BAAANQADCgIIAgABNQAECgYIDwAHAAAAAA==.Cheerwine:BAAANQADCggICAAAAA==.Cherypoptart:BAAANQAECgYIEgAAAA==.Chrismeister:BAAANQAECgEIAgAAAA==.',
Ci='Citrate:BAAANQADCggIDAAAAA==.',
Co='Coomaka:BAAANQADCgUIBQAAAA==.Coraggioso:BAAANQAECgIIBAAAAA==.Corbenik:BAABNQAECn8cAAIIAAcKBhM0KgCIAQAIAAcKBhM0KgCIAQAAAA==.',
Cr='Crodock:BAAANQABCgQIBgAAAA==.',
Cy='Cypress:BAAANQADCgYIBgAAAA==.',
['Cä']='Cähira:BAAANQADCgcIFgAAAA==.',
Da='Dainaira:BAAANQAECgYIEAAAAA==.Daisia:BAAANQABCgIIAgAAAA==.Darowen:BAAANQAECggIDQAAAA==.Daul:BAAANQAECggIEAAAAA==.',
De='Delti:BAAANQADCgUIBQABNQAECgcIHQAGANcbAA==.Demonsmind:BAABNQAECn8WAAQJAAgKewzVHQB+AQAJAAcK9QrVHQB+AQAKAAYK7ghw3AALAQALAAEKFQsILQA7AAAAAA==.Derien:BAABNQAECn8nAAIMAAgKvBqRDQBVAgAMAAgKvBqRDQBVAgAAAA==.Devlyn:BAAANQADCgcIHQAAAA==.',
Do='Donkeyteeth:BAAANQAECgcIDwAAAA==.',
Dr='Dromak:BAAANQAECgUIBQAAAA==.Drynn:BAAANQADCgYIBgAAAA==.Drywater:BAABNQAECn8bAAINAAYK8A9eFQBTAQANAAYK8A9eFQBTAQAAAA==.',
El='Elfblood:BAABNQAECn8cAAIJAAcKxwTjJABKAQAJAAcKxwTjJABKAQAAAA==.Elvion:BAAANQADCgQIBAAAAA==.',
Em='Emitsabah:BAAANQADCgUIBQAAAA==.Emongar:BAAANQADCgcIBwAAAA==.',
Fa='Fabulosa:BAAANQAECgcIDgAAAA==.Faith:BAAANQAECgUIBgAAAA==.',
Fi='Finite:BAAANQADCgYICAABNQAECgcIHgAOALYUAA==.Firebug:BAAANQAECgUIDAAAAA==.',
Fl='Flyke:BAAANQAECgYIEAAAAA==.Flyscrossmap:BAAANQADCgUIBgAAAA==.',
Fn='Fnwarlock:BAAANQAECgEIAQAAAA==.',
Fr='Frieren:BAACNQAFFH8YAAMNAAcKbxQTBADTAAAPAAUKWBc/GwCdAQANAAMKERATBADTAAA1AAQKfyAAAw8ACQo9IvU7AA4DAA8ACQo9IvU7AA4DAA0AAQp2HWZIADIAAAAA.',
Fu='Furnok:BAABNQAECn8ZAAMDAAcKBA9UgwCYAQADAAcKBA9UgwCYAQAQAAUKDQgKzADLAAAAAA==.',
Ga='Galethia:BAAANQADCgUIBgAAAA==.Garmjackyl:BAAANQADCgMIAQAAAA==.',
Gh='Ghandaloren:BAAANQADCgUIBQAAAA==.Ghia:BAAANQADCgUIBQABNQAECgEIAgAHAAAAAA==.Ghortash:BAAANQABCgYJCwAAAA==.Ghutz:BAABNQAECn82AAIRAAkK5BLRbgBDAgARAAkK5BLRbgBDAgAAAA==.',
Go='Gonja:BAAANQADCgUICAAAAA==.',
Gu='Gumbercules:BAABNQAECn8cAAISAAcK1gjJKwBIAQASAAcK1gjJKwBIAQAAAA==.',
Ha='Harina:BAAANQABCgMIAgAAAA==.',
He='Hearthglen:BAAANQAECgYIDwAAAA==.',
Ho='Hollet:BAAANQAECgQIBgAAAA==.Holykill:BAABNQAECn8dAAIIAAcKzwvzMwBAAQAIAAcKzwvzMwBAAQAAAA==.',
Hu='Hunttard:BAAANQADCggIHAAAAA==.',
Hy='Hydrack:BAAANQADCgYIBAAAAA==.Hylen:BAABNQAECn8hAAMLAAkK2xIECQD1AQALAAcKpxcECQD1AQAKAAMKzQiCFwGRAAAAAA==.',
['Hë']='Hëllboy:BAAANQABCgMIAwAAAA==.',
Ib='Ibrandul:BAABNQAECn8XAAIOAAgKoxATrQDAAQAOAAgKoxATrQDAAQAAAA==.',
Ic='Iceepop:BAAANQABCgMIAwAAAA==.',
Ir='Iroha:BAAANQADCgMIAwAAAA==.Ironhuntress:BAAANQAECgMIAwAAAA==.',
It='Ithro:BAAANQAECgcIEgAAAA==.',
Iy='Iyachtu:BAAANQADCgEIAQAAAA==.',
Ja='Jarlo:BAABNQAECn8XAAITAAYKUhERTACLAQATAAYKUhERTACLAQAAAA==.',
Je='Jeffarg:BAAANQAECgEIAQABNQAECgkJLgAUADQaAA==.Jefficiently:BAABNQAECn8uAAQUAAkKNBpyQgChAgAUAAkKLhlyQgChAgAVAAYKPRXlOgB0AQAWAAQKjx1tDAANAQAAAA==.Jestus:BAAANQADCgQIAwAAAA==.',
Jo='Jormungandr:BAAANQAECgcIEwAAAA==.',
Ju='Juandolf:BAAANQAECgEIAQAAAA==.Juanhunglow:BAAANQADCgUIDwAAAA==.Jularity:BAAANQAECgEJAQAAAA==.',
Ka='Kadryan:BAAANQADCgcIDQAAAA==.Kaeldric:BAAANQAECgIIBAAAAA==.Kairilynn:BAAANQAECgEIAQAAAA==.Kalinea:BAABNQAECn8eAAIUAAkK7xCQZgBFAgAUAAkK7xCQZgBFAgAAAA==.',
Ke='Kellice:BAAANQAECgEIAQAAAA==.Keruptadin:BAAANQAECgYICAAAAA==.',
Kh='Khedriss:BAAANQAECgYIEgAAAA==.',
Ko='Konerik:BAAANQABCgQIDgAAAA==.Kope:BAABNQAECn8nAAISAAgKmB9oDADdAgASAAgKmB9oDADdAgAAAA==.',
Kr='Krugor:BAAANQAECgIIBAAAAA==.Kruptis:BAAANQADCgQIBAAAAA==.Kryptikz:BAAANQADCgEIAQABNQAECgYIEAAHAAAAAA==.Krystoferson:BAAANQAECgUIDQAAAA==.',
Ku='Kurdis:BAAANQABCgUIBwAAAA==.',
['Kà']='Kàw:BAAANQADCggJIAAAAA==.',
La='Labiy:BAAANQADCgYIDAAAAA==.Lalatína:BAAANQADCgYIBgAAAA==.',
Le='Leelu:BAAANQADCgQIBAABNQADCgcIFgAHAAAAAA==.Leianii:BAAANQADCggIHgAAAA==.',
Lh='Lhondar:BAAANQADCgYICgAAAA==.',
Li='Lifehammer:BAAANQADCggIDAABNQAECgkJJwAGAPAbAA==.Likkaru:BAAANQADCgMIBAAAAA==.Liljess:BAAANQADCgYJBgABNQAECgMIAwAHAAAAAA==.Lillat:BAAANQAECgQIBAAAAA==.Littlepop:BAAANQADCgcIDQAAAA==.',
Lu='Luciamar:BAAANQADCggICAABNQAFFAUIEgASAFUUAA==.Lumi:BAAANQADCgYIEgAAAA==.',
Ly='Lyarith:BAAANQADCgUIBwAAAA==.',
['Lì']='Lìesson:BAEANQAECgcIEwAAAA==.',
Ma='Mackaroni:BAAANQADCgEIAQABNQAECgEIAgAHAAAAAA==.Magesca:BAABNQAECn8aAAINAAcK5ROBDADvAQANAAcK5ROBDADvAQAAAA==.Makkagg:BAABNQAECn8ZAAIXAAcK4hcUDQDlAQAXAAcK4hcUDQDlAQAAAA==.',
Me='Megastorm:BAAANQABCgQIBAAAAA==.Merillion:BAAANQABCgIIAgAAAA==.',
Mg='Mghtymage:BAAANQADCggIEwAAAA==.',
Mi='Milagrosa:BAAANQAECgcIDwAAAA==.Millanya:BAAANQADCgcIBwAAAA==.Mirael:BAABNQAECn83AAIUAAkKnBxYJwD5AgAUAAkKnBxYJwD5AgAAAA==.',
Mo='Mommanoo:BAAANQAECgUIBQAAAA==.Mordenthal:BAAANQAECgEIAQAAAA==.',
Mu='Mumshun:BAAANQAECggICAAAAA==.',
My='Mykester:BAAANQABCgIIAgAAAA==.Mykesucks:BAAANQABCgUIBwAAAA==.Myrmia:BAAANQAECgIJAgAAAA==.',
Na='Nails:BAAANQADCgYIBgAAAA==.Natyri:BAAANQAECgQIBAAAAA==.Naxximarus:BAAANQAECgcIBwABNQAECgkJOAAEAHEdAA==.',
Ni='Nightowl:BAAANQABCgIIAgAAAA==.Nirazen:BAAANQABCgIIAgAAAA==.',
No='Nota:BAAANQAECgYIEAAAAA==.',
Og='Ogrusao:BAAANQAECgIIAwAAAA==.',
Ol='Olaaru:BAAANQAECgQIBAAAAA==.',
Om='Omelette:BAAANQAECgIJAgAAAA==.',
Pa='Panasaurus:BAABNQAECn8ZAAIGAAcKAhZkKwDjAQAGAAcKAhZkKwDjAQAAAA==.',
Pe='Pelli:BAAANQAECgMIAwAAAA==.Pendraig:BAAANQADCggIIgAAAA==.',
Pi='Pink:BAAANQAECgQIBwAAAA==.',
Po='Popchop:BAAANQAECgEIAQAAAA==.',
Ra='Rainedancer:BAABNQAECn8lAAIQAAgKLBiHWAAEAgAQAAgKLBiHWAAEAgAAAA==.Rat:BAAANQAECggIDQABNQAFFAUIEQAQANIbAA==.Rawriior:BAAANQABCgQIBQAAAA==.Raynez:BAAANQADCgYICAABNQAECgYIEAAHAAAAAA==.',
Rh='Rhalek:BAAANQAECgUICQABNQAECgkJMgAYACgfAA==.Rheunae:BAAANQAECgEIAQAAAA==.Rhykis:BAAANQAECgYIEAAAAA==.',
Ro='Rogztaudru:BAAANQABCgEIAQAAAA==.',
Sa='Sabba:BAAANQAECgIIAwAAAA==.Sableanne:BAAANQAECgcIDgAAAA==.Sacrament:BAAANQAECggIAwABNQAECggIEAAHAAAAAA==.Sagearian:BAAANQAECgEIAQAAAA==.Samanda:BAAANQAECgQIBAAAAA==.Samshir:BAAANQAECgEIAQABNQAECgYIEgAHAAAAAA==.Sapped:BAAANQAFFAEIAQABNQAECgEIAgAHAAAAAA==.Sarinna:BAAANQADCgMIBQAAAA==.',
Se='Seosinz:BAAANQAECgEIAQAAAA==.',
Sh='Shabbyshammy:BAAANQAECgQIBAAAAA==.Shariaan:BAAANQADCggIIQAAAA==.Shaylinn:BAAANQADCgcIHgAAAA==.Shùkkle:BAABNQAECn8lAAIZAAkKLh37GQD3AgAZAAkKLh37GQD3AgAAAA==.',
Si='Siella:BAAANQAECgIIBAAAAA==.Sinric:BAAANQAECgMIAwAAAA==.Sitrom:BAAANQADCgIIAgAAAA==.',
Sk='Skorvis:BAACNQAFFH8KAAMQAAMKOxb4FQD1AAAQAAMKOxb4FQD1AAADAAIKZQZPKACFAAA1AAQKfycAAxAACQpVH1UeAPACABAACQpVH1UeAPACAAMABgp8EKWCAJoBAAE1AAUUBQgKAAUAYREA.',
Sl='Sloshama:BAAANQAECgQIBQAAAA==.',
Sm='Smallfox:BAAANQADCgUIBQABNQAECgEIAQAHAAAAAA==.',
Sn='Snayderino:BAAANQADCgcIDAAAAA==.',
So='Solar:BAACNQAFFH8HAAIZAAMK9guHGQDUAAAZAAMK9guHGQDUAAA1AAQKfyAAAhkACQqiHQQqAIUCABkACQqiHQQqAIUCAAAA.Somenai:BAAANQADCgYICgAAAA==.Sora:BAAANQADCgYIBgAAAA==.Soulbaine:BAAANQADCgYIBgAAAA==.',
Sp='Spheria:BAAANQAECgcIDgAAAA==.',
Su='Surelyhots:BAAANQAECgYIDAAAAA==.',
Ta='Tankdezoe:BAAANQADCgYJCAABNQAECgMIAwAHAAAAAA==.Tansonite:BAAANQAECgcIEgAAAA==.',
Te='Tequ:BAAANQADCgcIGwAAAA==.',
Ti='Timeshade:BAAANQAECgEIAQAAAA==.Tine:BAABNQAECn8nAAIPAAgKZhMyqAAwAgAPAAgKZhMyqAAwAgAAAA==.',
To='Toray:BAAANQAECgQIAwAAAA==.',
Tr='Triplesix:BAAANQAECgcIEwAAAA==.Trittia:BAAANQAECgEIAgAAAA==.Trixzia:BAAANQADCgUIBQABNQAECgIIAwAHAAAAAA==.Troky:BAAANQAECgYICgAAAA==.',
Ty='Tynk:BAAANQADCggIFgAAAA==.',
Ug='Ugh:BAEBNQAFFH8KAAICAAUKJhouCwCeAQACAAUKJhouCwCeAQAAAA==.',
Ur='Urza:BAAANQADCgMIAwAAAA==.',
Va='Vaewind:BAAANQADCgQIBAAAAA==.Valethus:BAABNQAECn8mAAIUAAgK/hcRWgBjAgAUAAgK/hcRWgBjAgAAAA==.Valhuntar:BAAANQAECgUICwAAAA==.',
Ve='Verlis:BAAANQADCgcIFQAAAA==.Vesp:BAAANQADCggIDwAAAA==.Veylla:BAAANQAECgIIAwAAAA==.',
Wa='Walkz:BAAANQAECgYIEAAAAA==.Warkkagg:BAABNQAECn8XAAIKAAkKChcrTABsAgAKAAkKChcrTABsAgABNQAECgcIGQAXAOIXAA==.Waterworks:BAAANQAECgEIAQAAAA==.',
We='Weékly:BAAANQAECgQIBgAAAA==.',
Wi='Wickedlight:BAAANQAECgcIEwAAAA==.Wickedlock:BAAANQADCgQIBAAAAA==.Willscarlet:BAAANQAECgQIAwAAAA==.',
Xu='Xunn:BAAANQADCgIIAgAAAA==.',
Yl='Ylkhalas:BAAANQADCgcIFQAAAA==.',
Yo='Yolks:BAAANQAECgYIDgAAAA==.',
Za='Zamual:BAAANQADCgMIAwAAAA==.Zaritym:BAAANQAECgYIEQAAAA==.',
Zi='Zibetha:BAABNQAECn8yAAIJAAkKDxuHAwAJAwAJAAkKDxuHAwAJAwAAAA==.',
Zo='Zoeheals:BAAANQAECgMIAwAAAA==.',
Zu='Zuggtmoy:BAAANQADCgIIBQAAAA==.',
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
