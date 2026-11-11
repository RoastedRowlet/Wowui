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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Mage-Fire','Mage-Arcane','Mage-Frost','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Paladin-Protection','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Restoration','Unknown-Unknown','Warrior-Arms','Evoker-Preservation','Hunter-BeastMastery','Rogue-Assassination','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Druid-Guardian','DemonHunter-Havoc','Monk-Mistweaver',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Adabisi:BAAANQADCgEIBAAAAA==.Addu:BAAANQAECgEIAQAAAA==.Adiforis:BAABNQAECn8sAAMBAAoK2BRpNgD/AQABAAoK2BRpNgD/AQACAAMKcQUwpgCHAAAAAA==.Adobo:BAACNQAFFH8FAAIDAAIK6wiEHwBuAAADAAIK6wiEHwBuAAA1AAQKfz4AAgMACgr+ErlHAFgCAAMACgr+ErlHAFgCAAAA.Adolhay:BAAANQADCgMIAwAAAA==.',
Al='Aljeron:BAAANQADCgIJAgAAAA==.Allysson:BAABNQAECn8mAAIBAAgK/grHUgAyAQABAAgK/grHUgAyAQAAAA==.Alrekur:BAAANQAECgQICgAAAA==.Alyestra:BAAANQAECgMIAwAAAA==.',
An='Animyst:BAAANQAECgYIEAABNQAECgoKLwAEAP8fAA==.Anipaltu:BAABNQAECn8cAAIFAAkKKx0ZHwD0AgAFAAkKKx0ZHwD0AgABNQAECgoKLwAEAP8fAA==.Aniron:BAAANQAECgYIDwABNQAECgoKLwAEAP8fAA==.Anirot:BAABNQAECn8vAAIEAAoK/x+5FgAeAwAEAAoK/x+5FgAeAwAAAA==.Anithwip:BAAANQADCggICAABNQAECgoKLwAEAP8fAA==.Annalissa:BAAANQADCgYIBgAAAA==.',
Ar='Aranta:BAABNQAECn8YAAMGAAcKVgcqRQDWAAAGAAcKVgcqRQDWAAAHAAMKVQJknQBnAAAAAA==.Argon:BAAANQADCgMIAQAAAA==.Arieldhas:BAAANQADCggIGAAAAA==.',
As='Astren:BAAANQAECgUIDwAAAA==.Asynsia:BAABNQAECn8zAAIIAAoKviBEDQAQAwAIAAoKviBEDQAQAwAAAA==.',
['Aõ']='Aõnar:BAAANQADCgEIAQAAAA==.',
Ba='Bartholomew:BAAANQAECgMIBAABNQAECgoKRQAEAOUfAA==.',
Be='Beertje:BAAANQAECgEIAgAAAA==.Bellemore:BAAANQAECgYICAAAAA==.',
Bh='Bhattle:BAAANQAECgQICAAAAA==.',
Bi='Bienfaiseur:BAABNQAECn8vAAIEAAgKwiWiDwBPAwAEAAgKwiWiDwBPAwAAAA==.Bigdamhero:BAAANQADCgIIAgAAAA==.Bisonnaire:BAAANQAECgEIAQABNQAECgoKRQAEAOUfAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Blackcode:BAABNQAECn8bAAQJAAoKTg23BwC4AAAKAAgKkwygxwAHAQAJAAQKjQ+3BwC4AAALAAIKgQy2NQBkAAAAAA==.',
Br='Breadbringer:BAAANQADCggIEwAAAA==.Breezybb:BAAANQADCgQIBAAAAA==.',
Bu='Buckshotapie:BAAANQADCgIIAgAAAA==.Bulgrim:BAAANQADCgYIDQAAAA==.Bunrÿl:BAAANQAECgIIAgAAAA==.Busterheiman:BAAANQAECgEIAQAAAA==.Butterrz:BAAANQADCgMIAwABNQAECgkJHgAMABgaAA==.',
Ca='Caseopiea:BAAANQADCgYIBgAAAA==.',
Ce='Cearylin:BAABNQAECn8bAAIEAAgKdAQmkAARAQAEAAgKdAQmkAARAQAAAA==.Cerealkillah:BAAANQADCgMIAwAAAA==.',
Ch='Chasy:BAAANQADCgIIAgABNQAECgkJIgANAAkOAA==.Cheerwine:BAAANQADCggICAAAAA==.Cherypoptart:BAABNQAECn84AAIOAAoKOiEtBgAEAwAOAAoKOiEtBgAEAwAAAA==.Chrismeister:BAAANQAECgQIBwAAAA==.',
Ci='Citrate:BAAANQADCggIDAAAAA==.',
Co='Contradict:BAAANQADCggIBgABNQAECgoKNgANABYWAA==.Coomaka:BAAANQADCgUIBQAAAA==.Coraggioso:BAAANQAECgQIDwAAAA==.Corbenik:BAABNQAECn8oAAIPAAcKBhPLKgCHAQAPAAcKBhPLKgCHAQAAAA==.',
Cr='Crethasmus:BAAANQAECgQIBAAAAA==.Crodock:BAAANQABCgQIBgAAAA==.',
Cy='Cypress:BAAANQADCgYIBgAAAA==.',
['Cä']='Cähira:BAAANQAECgEIAQAAAA==.',
Da='Dainaira:BAABNQAECn8fAAIOAAkK8AdIKAArAQAOAAkK8AdIKAArAQAAAA==.Daisia:BAAANQABCgIIAgAAAA==.Darowen:BAAANQAECggIDQAAAA==.Daul:BAABNQAECn8fAAIPAAoKqw3hJwAdAQAPAAoKqw3hJwAdAQAAAA==.',
De='Delti:BAAANQADCgUIBQABNQAECggILQAQAJIaAA==.Demonsmind:BAABNQAECn8dAAQRAAoKLg3/HQB+AQARAAcK9Qr/HQB+AQASAAkKcwocswDZAAATAAEKFQt5LQA7AAAAAA==.Derien:BAABNQAECn8zAAIMAAoKxRgoDQDSAQAMAAoKxRgoDQDSAQAAAA==.Devlyn:BAAANQADCggIIAAAAA==.',
Do='Donkeyteeth:BAAANQAECgcIDwAAAA==.Donkeyteeths:BAAANQAECgcIEgAAAA==.',
Dr='Dromak:BAAANQAECggIDQAAAA==.Drusila:BAAANQAECgUIDgAAAA==.Drynn:BAAANQADCgYIBgAAAA==.Drywater:BAABNQAECn8wAAILAAkKzguZFQBTAQALAAkKzguZFQBTAQAAAA==.',
El='Elfblood:BAABNQAECn80AAIRAAgKbghpDADnAAARAAgKbghpDADnAAAAAA==.Elvion:BAAANQADCgQIBAAAAA==.',
Em='Emitsabah:BAAANQADCgUIBQAAAA==.Emongar:BAAANQADCgcIBwAAAA==.',
Fa='Fabulosa:BAAANQAECgcIDgAAAA==.Faith:BAAANQAECgUIBgAAAA==.',
Fe='Felesta:BAAANQAECgEIAQAAAA==.',
Fi='Finite:BAAANQAECgUIBAABNQAECgoKNgANABYWAA==.Firebug:BAABNQAECn8UAAIMAAcKRAYCKQCgAAAMAAcKRAYCKQCgAAAAAA==.',
Fl='Flyke:BAABNQAECn8jAAIKAAoKfAklegClAQAKAAoKfAklegClAQAAAA==.Flyscrossmap:BAAANQAECgYICQAAAA==.',
Fn='Fndruid:BAAANQAECgIIAgAAAA==.Fnwarlock:BAAANQAECgQICQAAAA==.',
Fu='Furnok:BAABNQAECn8vAAMUAAgKjxM+SwDOAQAUAAgKjxM+SwDOAQADAAcKKxEJhQCYAQAAAA==.',
Ga='Galethia:BAAANQADCgUIBgAAAA==.Garmjackyl:BAAANQADCgMIAQAAAA==.',
Gh='Ghandaloren:BAAANQADCgUIBQAAAA==.Ghia:BAAANQADCgUIBQABNQAECgEIAgAVAAAAAA==.Ghortash:BAAANQABCgYICwAAAA==.Ghrim:BAAANQAECgYICQAAAA==.Ghutz:BAABNQAECn9SAAMWAAoK0ROjTwD9AQAWAAoK0ROjTwD9AQAMAAUKlgmZJwCqAAAAAA==.',
Go='Gonja:BAAANQADCgUICAAAAA==.',
Gr='Grave:BAABNQAECn9LAAMCAAoKoyLEBQAkAwACAAoKoyLEBQAkAwABAAQKpRiScwC+AAAAAA==.',
Gu='Gumbercules:BAABNQAECn8yAAIXAAgKWQxGFwBnAQAXAAgKWQxGFwBnAQAAAA==.',
Ha='Harina:BAAANQABCgMIAgAAAA==.',
He='Hearthglen:BAABNQAECn8iAAINAAkKCQ4ZqwBjAQANAAkKCQ4ZqwBjAQAAAA==.',
Ho='Hollet:BAABNQAECn8WAAIYAAYKgQWN5QDLAAAYAAYKgQWN5QDLAAAAAA==.Holykill:BAABNQAECn8mAAIPAAgK/QqNNABAAQAPAAgK/QqNNABAAQAAAA==.',
Hu='Hunttard:BAAANQAECgUIDAAAAA==.',
Hy='Hydrack:BAAANQADCgYIBAAAAA==.Hylen:BAABNQAECn8yAAMTAAoKyhIXCQD1AQATAAkKYBMXCQD1AQASAAUKLAxpsADfAAAAAA==.',
['Hë']='Hëllboy:BAAANQABCgMIAwAAAA==.',
Ib='Ibrandul:BAABNQAECn8qAAINAAoKXRIsaQDsAQANAAoKXRIsaQDsAQAAAA==.',
Ic='Iceepop:BAAANQAECgUIBQAAAA==.',
Ir='Iroha:BAAANQADCgMIAwAAAA==.Ironhuntress:BAAANQAECgUIBQAAAA==.',
It='Ithro:BAABNQAECn8mAAIZAAoK4xIWDgDaAQAZAAoK4xIWDgDaAQAAAA==.',
Iy='Iyachtu:BAAANQADCgEIAQAAAA==.',
Ja='Jarlo:BAABNQAECn8eAAIZAAcKWxFjIAAfAQAZAAcKWxFjIAAfAQAAAA==.Jaydeki:BAAANQADCgQIBAAAAA==.',
Je='Jeffarg:BAAANQAECgEIAQABNQAECgoKSgAYALYdAA==.Jefficiently:BAABNQAECn9KAAQYAAoKth2/QwCgAgAYAAoK2By/QwCgAgAaAAkKqhRHFwDDAQAbAAQKjx2MDAANAQAAAA==.Jefriel:BAAANQAECgEIAQABNQAECgoKSgAYALYdAA==.Jestus:BAAANQADCgQIAwAAAA==.',
Ji='Jinsoftpaw:BAAANQAECgQIBAAAAA==.',
Jo='Joolianm:BAACNQAFFH8cAAMLAAgKCxY0BADTAAAKAAYKBxnrGwCdAQALAAMKERA0BADTAAA1AAQKfz0ABAoACgosI6kkAKECAAoACgosI6kkAKECAAsAAwqMG04YAAUBAAkAAwpVIPMGAKIAAAAA.Jormungandr:BAABNQAECn8rAAMWAAoK1xmBNgBXAgAWAAoK1xmBNgBXAgAMAAEKAAClQAA9AAAAAA==.',
Ju='Juandolf:BAAANQAECgYIDwAAAA==.Juanhunglow:BAAANQADCgUIFAAAAA==.Jularity:BAAANQAECgEJAQAAAA==.',
Ka='Kadryan:BAAANQADCgcIEwAAAA==.Kaeldric:BAAANQAECgQIDwAAAA==.Kairilynn:BAAANQAECgEIAQAAAA==.Kalemshai:BAAANQAECgUIDAAAAA==.Kalinea:BAABNQAECn8oAAIYAAoKqBEDaABEAgAYAAoKqBEDaABEAgAAAA==.',
Ke='Kellice:BAAANQAECgEIAQAAAA==.Keruptadin:BAAANQAECgYICAAAAA==.',
Kh='Khedriss:BAABNQAECn8dAAIKAAoKxQQaywAAAQAKAAoKxQQaywAAAQAAAA==.',
Ki='Kintha:BAAANQAECgIIAgAAAA==.',
Ko='Konerik:BAAANQABCgQIDgAAAA==.Kope:BAABNQAECn8zAAIXAAoK+x5gBQAVAwAXAAoK+x5gBQAVAwAAAA==.',
Kr='Krugor:BAAANQAECgQICAAAAA==.Kruptis:BAAANQADCgQIBAAAAA==.Kryptikz:BAAANQADCgEIAQABNQAECgkJHgAMABgaAA==.Krystoferson:BAABNQAECn8WAAIcAAUK1gNqPwC9AAAcAAUK1gNqPwC9AAAAAA==.',
Ku='Kurdis:BAAANQABCgUIBwAAAA==.',
['Kà']='Kàw:BAAANQADCggIIAAAAA==.',
La='Labiy:BAAANQADCgYIDAAAAA==.Lalatína:BAAANQADCgYIBgAAAA==.',
Le='Leelu:BAAANQADCgQIBAABNQAECgEIAQAVAAAAAA==.Leianii:BAAANQAECgUIDAAAAA==.',
Lh='Lhondar:BAAANQAECgYIDgAAAA==.',
Li='Lifehammer:BAAANQADCggIDAABNQAECgoKSQAIANseAA==.Likkaru:BAAANQADCgMIBAAAAA==.Liljess:BAAANQADCgYJBgABNQAECggICwAVAAAAAA==.Lillat:BAAANQAECgYICgAAAA==.Lin:BAAANQADCggIDwAAAA==.Littlepop:BAAANQADCgcIDQAAAA==.',
Lu='Luciamar:BAAANQADCggICAABNQAFFAUIEgAXAFUUAA==.Lumi:BAAANQADCgYIEgAAAA==.Luuggork:BAAANQADCgIIAgAAAA==.Luxfire:BAAANQADCgQIBAAAAA==.',
Ly='Lyarith:BAAANQADCgUIBwAAAA==.',
['Lì']='Lìesson:BAEBNQAECn8lAAINAAoK9R3SNwB3AgANAAoK9R3SNwB3AgAAAA==.',
Ma='Mackaroni:BAAANQADCgEIAQABNQAECgEIAgAVAAAAAA==.Macnurmom:BAAANQAECgEIAgAAAA==.Magesca:BAABNQAECn8yAAILAAkKjBWlDADvAQALAAkKjBWlDADvAQAAAA==.Makkagg:BAABNQAECn8lAAIdAAkKaRkvDQDlAQAdAAkKaRkvDQDlAQABNQAFFAMIBgASAIwSAA==.',
Me='Megastorm:BAAANQABCgUIBwAAAA==.Merillion:BAAANQABCgIIAgAAAA==.',
Mg='Mghtymage:BAAANQADCggIEwAAAA==.',
Mi='Miereynna:BAAANQADCgUICQAAAA==.Milagrosa:BAABNQAECn8hAAIeAAoKFw0wCACYAQAeAAoKFw0wCACYAQAAAA==.Mirael:BAACNQAFFH8MAAIYAAUKLwwUFQDaAAAYAAUKLwwUFQDaAAA1AAQKf00AAhgACgrvH4EhAKwCABgACgrvH4EhAKwCAAAA.',
Mo='Mommanoo:BAAANQAECgYICgAAAA==.Mordenthal:BAAANQAECgEIAQABNQAECgYIBgAVAAAAAA==.',
Mu='Mumshun:BAAANQAECggICAAAAA==.Mumsnielf:BAAANQAECggICAAAAA==.',
My='Mykester:BAAANQABCgIIAgAAAA==.Myrmia:BAAANQAECgIJAgAAAA==.',
Na='Nails:BAAANQADCgYIBwAAAA==.Nanumar:BAAANQAECgYIBgABNQAECgoKLgAfACYVAA==.Nargul:BAAANQAECggICAAAAA==.Natyri:BAABNQAECn8ZAAIIAAoKHg8QGgDKAQAIAAoKHg8QGgDKAQAAAA==.Naxximarus:BAAANQAECgcIDwABNQAECgoKRQAEAOUfAA==.',
Ni='Nightowl:BAAANQABCgIIAgAAAA==.Nirazen:BAAANQAECgUICAAAAA==.',
No='Nota:BAABNQAECn8dAAINAAkKJgRoDAEKAQANAAkKJgRoDAEKAQAAAA==.',
Og='Ogrusao:BAAANQAECgMICAAAAA==.',
Ol='Olaaru:BAAANQAECgUIBQAAAA==.',
Om='Omelette:BAAANQAECgIJAgAAAA==.',
Pa='Panasaurus:BAABNQAECn8xAAMIAAgKURbXKwDjAQAIAAgKURbXKwDjAQAQAAcK/AdVGQC5AAAAAA==.',
Pe='Pelli:BAAANQAECgQIDgAAAA==.Percephony:BAAANQADCgUIBQAAAA==.',
Pi='Pink:BAAANQAECgQIBwAAAA==.',
Pl='Plaza:BAAANQAECggIAQAAAA==.',
Po='Popchop:BAAANQAECgUIBAABNQAECggIEwAVAAAAAA==.',
Pu='Purgatorium:BAAANQAECggICgAAAA==.',
Ra='Rainedancer:BAACNQAFFH8GAAIUAAMKdwsAGgC7AAAUAAMKdwsAGgC7AAA1AAQKfzQAAhQACgoDGqozADgCABQACgoDGqozADgCAAAA.Rat:BAAANQAECggIEQABNQAFFAYIFgAUAM4bAA==.Ratatosk:BAAANQAECgcICAAAAA==.Rawriior:BAAANQABCgQIBQAAAA==.Raynez:BAAANQADCgYICAABNQAECgkJHgAMABgaAA==.',
Rh='Rhalek:BAABNQAECn8hAAIGAAkKRiIjCABFAwAGAAkKRiIjCABFAwABNQAECgoKUwAGAEEhAA==.Rheunae:BAAANQAECgUIEQAAAA==.Rhykis:BAABNQAECn8eAAIWAAkKTB8lTAAJAgAWAAkKTB8lTAAJAgAAAA==.',
Ro='Rogztaudru:BAAANQABCgEIAQAAAA==.Rogzundlock:BAAANQABCgIIAgAAAA==.',
Ry='Ryleigh:BAAANQADCgYIBgAAAA==.',
Sa='Sabba:BAAANQAECgQIDgAAAA==.Sableanne:BAAANQAECgcIDwAAAA==.Sacrament:BAAANQAECggICAABNQAECgoKHwAPAKsNAA==.Sagearian:BAAANQAECgQICAAAAA==.Samanda:BAABNQAECn8YAAIgAAcKVhCkFgBJAQAgAAcKVhCkFgBJAQAAAA==.Samshir:BAAANQAECgYICwABNQAECgoKHQAKAMUEAA==.Sapped:BAABNQAECn8VAAMZAAkKUg8UMgAWAgAZAAkKUg8UMgAWAgAcAAIKDBQySgBoAAABNQAECgEIAgAVAAAAAA==.Sarinna:BAAANQADCgMIBQAAAA==.',
Se='Seosinz:BAAANQAECggIAQAAAA==.',
Sh='Shabbyshammy:BAAANQAECggICgAAAA==.Shariaan:BAAANQAECgEIAQAAAA==.Shaylinn:BAAANQADCggIIQAAAA==.Shùkkle:BAABNQAECn8lAAIHAAkKLh1BGgD2AgAHAAkKLh1BGgD2AgAAAA==.',
Si='Siella:BAAANQAECgQIDwAAAA==.Sinric:BAAANQAECgYICQAAAA==.Sitrom:BAAANQAECgIIAgAAAA==.',
Sk='Skorvis:BAACNQAFFH8QAAMUAAMKOxaAFgD1AAAUAAMKOxaAFgD1AAADAAMKlQueHACFAAA1AAQKfy8AAxQACgoGHtgeAO8CABQACgoGHtgeAO8CAAMABwrtE3eEAJkBAAE1AAUUBwgMAAUAxhAA.',
Sl='Sloshama:BAAANQAECgQIBQAAAA==.',
Sm='Smallfox:BAAANQADCgUIBQABNQAECgQIBAAVAAAAAA==.',
Sn='Snayderino:BAAANQADCgcIDAAAAA==.',
So='Solar:BAACNQAFFH8HAAIHAAMK9gv5GQDUAAAHAAMK9gv5GQDUAAA1AAQKfyoABAcACgofHnsqAIUCAAcACgoUHXsqAIUCACAAAwojDhomALQAACEAAQqUGEpgAEYAAAAA.Somenai:BAAANQADCgYICgAAAA==.Sonofmums:BAAANQAECggIAgAAAA==.Sora:BAAANQADCgYIBgAAAA==.Soulbaine:BAAANQADCgYIBgAAAA==.',
Sp='Spheria:BAABNQAECn8nAAISAAgKJwfWnAAKAQASAAgKJwfWnAAKAQAAAA==.',
Su='Surelyhots:BAAANQAECgYIEgAAAA==.',
Ta='Tankdezoe:BAAANQAECggICwAAAA==.Tansonite:BAABNQAECn8rAAMPAAoK2w3SHQBrAQAPAAoK2w3SHQBrAQANAAkKAAKDVAGZAAAAAA==.',
Te='Tequ:BAAANQADCggIHgAAAA==.',
Th='Thiberius:BAAANQADCgQIBAAAAA==.Thrazul:BAAANQAECgEIAQAAAA==.',
Ti='Timeshade:BAAANQAECgEIAQAAAA==.Tine:BAABNQAECn8zAAIKAAoKyhKtWwDzAQAKAAoKyhKtWwDzAQAAAA==.',
To='Toray:BAAANQAECggICwAAAA==.',
Tr='Trinn:BAAANQADCgQIBAAAAA==.Triplesix:BAABNQAECn8gAAIiAAgKthLOOABIAQAiAAgKthLOOABIAQAAAA==.Trittia:BAAANQAECgEIAgAAAA==.Trixzia:BAAANQADCgUIBQABNQAECgIIAwAVAAAAAA==.Troky:BAAANQAECggIEAAAAA==.',
Ty='Tynk:BAAANQAECgEIAQAAAA==.',
Ug='Ugh:BAEBNQAFFH8ZAAICAAcKyCAlBQDTAQACAAcKyCAlBQDTAQAAAA==.',
Ur='Urza:BAAANQADCgMIAwAAAA==.',
Va='Vaewind:BAAANQADCgUIBQAAAA==.Valethus:BAABNQAECn9CAAMYAAoKDRlRLgB6AgAYAAoKDRlRLgB6AgAaAAEKAAAkfAAAAAAAAA==.Valhuntar:BAABNQAECn8tAAIYAAoK1BYvMQBwAgAYAAoK1BYvMQBwAgAAAA==.',
Ve='Velleria:BAAANQAECgUICAAAAA==.Verlis:BAAANQADCggIFgAAAA==.Vesp:BAAANQADCggIDwAAAA==.Veylla:BAAANQAECgIIAwAAAA==.',
Wa='Walkz:BAABNQAECn8eAAIMAAkKGBopDwCrAQAMAAkKGBopDwCrAQAAAA==.Warkkagg:BAACNQAFFH8GAAISAAMKjBKLFQDnAAASAAMKjBKLFQDnAAA1AAQKfygAAhIACgpaHO44AB0CABIACgpaHO44AB0CAAAA.Waterworks:BAAANQAECgEIAwABNQAECgQIBAAVAAAAAA==.',
We='Weékly:BAAANQAECgQIBgAAAA==.',
Wi='Wickedlight:BAABNQAECn8wAAIOAAkKNhmkFAD+AQAOAAkKNhmkFAD+AQAAAA==.Wickedlock:BAAANQADCgQIBAAAAA==.Willscarlet:BAAANQAECgYICQAAAA==.',
Xu='Xunn:BAAANQADCgIIAgAAAA==.',
Yl='Ylkhalas:BAAANQAECgQIBQAAAA==.',
Yo='Yolks:BAABNQAECn8YAAIUAAgKeRGpcgBEAQAUAAgKeRGpcgBEAQAAAA==.',
Za='Zaareth:BAAANQAECgUICQAAAA==.Zamual:BAAANQADCgMIAwAAAA==.Zaritym:BAABNQAECn8fAAIjAAkKZBq9FQAgAgAjAAkKZBq9FQAgAgAAAA==.',
Ze='Zelsada:BAAANQADCgcIBwAAAA==.',
Zi='Zibetha:BAABNQAECn89AAIRAAoKUxyKAwAJAwARAAoKUxyKAwAJAwAAAA==.',
Zo='Zoeheals:BAAANQAECgUIBAABNQAECggICwAVAAAAAA==.',
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
