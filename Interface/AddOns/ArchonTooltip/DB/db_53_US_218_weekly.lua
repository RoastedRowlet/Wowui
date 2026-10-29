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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Paladin-Protection','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Mage-Arcane','Shaman-Restoration','Unknown-Unknown','Warrior-Arms','Evoker-Preservation','Rogue-Assassination','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Mage-Fire','Rogue-Subtlety','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','DemonHunter-Havoc','Monk-Mistweaver',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Absolver:BAAANQAECgEIAQAAAA==.',
Ad='Adabisi:BAAANQADCgEIBAAAAA==.Addu:BAAANQAECgEIAQAAAA==.Adiforis:BAABNQAECn8oAAMBAAoKmBRpNgD/AQABAAoKmBRpNgD/AQACAAMKcQUwpgCHAAAAAA==.Adobo:BAACNQAFFH8FAAIDAAIK6wjUFgBwAAADAAIK6wjUFgBwAAA1AAQKfz4AAgMACgr+ErlHAFgCAAMACgr+ErlHAFgCAAAA.Adolhay:BAAANQADCgMIAwAAAA==.',
Al='Aljeron:BAAANQADCgIJAgAAAA==.Allysson:BAABNQAECn8jAAIBAAcKWgv/RQD+AAABAAcKWgv/RQD+AAAAAA==.Alrekur:BAAANQAECgUIBAAAAA==.Alyestra:BAAANQAECgMIAwAAAA==.',
An='Animyst:BAAANQAECgcIEAABNQAECgoKLAAEAOIfAA==.Anipaltu:BAABNQAECn8cAAIFAAkKKx0ZHwD0AgAFAAkKKx0ZHwD0AgABNQAECgoKLAAEAOIfAA==.Aniron:BAAANQAECgUICQABNQAECgoKLAAEAOIfAA==.Anirot:BAABNQAECn8sAAIEAAoK4h+5FgAeAwAEAAoK4h+5FgAeAwAAAA==.Anithwip:BAAANQADCggICAABNQAECgoKLAAEAOIfAA==.Annalissa:BAAANQADCgYIBgAAAA==.',
Ar='Aranta:BAABNQAECn8YAAMGAAcKVgc5MgDbAAAGAAcKVgc5MgDbAAAHAAMKVQJknQBnAAAAAA==.Arieldhas:BAAANQADCggIGAAAAA==.',
As='Astren:BAAANQAECgUIDgAAAA==.Asynsia:BAABNQAECn8pAAIIAAgKZyFEDQAQAwAIAAgKZyFEDQAQAwAAAA==.',
Av='Avamani:BAAANQADCgcIHQAAAA==.',
['Aõ']='Aõnar:BAAANQADCgEIAQAAAA==.',
Ba='Bartholomew:BAAANQAECgMIBAABNQAECgoKQgAEAOUfAA==.',
Be='Beertje:BAAANQAECgEIAgAAAA==.Bellemore:BAAANQAECgMIAgAAAA==.',
Bh='Bhattle:BAAANQAECgQIBAAAAA==.',
Bi='Bienfaiseur:BAABNQAECn8lAAIEAAcKOSZ4EwDLAgAEAAcKOSZ4EwDLAgAAAA==.Bigdamhero:BAAANQADCgIIAgAAAA==.Bisonnaire:BAAANQAECgEIAQABNQAECgoKQgAEAOUfAA==.',
Bl='Blackbird:BAAANQADCgQIBAAAAA==.Blackcode:BAAANQAECgcIDgAAAA==.',
Br='Breadbringer:BAAANQADCggICwAAAA==.Breezybb:BAAANQADCgQIBAAAAA==.',
Bu='Buckshotapie:BAAANQADCgIIAgAAAA==.Bulgrim:BAAANQADCgYIDQAAAA==.Bunrÿl:BAAANQAECgIIAgAAAA==.Busterheiman:BAAANQAECgEIAQAAAA==.Butterrz:BAAANQADCgMIAwABNQAECggIGwAJANoaAA==.',
Ca='Caseopiea:BAAANQADCgYIBgAAAA==.',
Ce='Cearylin:BAAANQAECgYIEAAAAA==.Cerealkillah:BAAANQADCgMIAwAAAA==.',
Ch='Chasy:BAAANQADCgIIAgABNQAECggIGgAKAPwMAA==.Cheerwine:BAAANQADCggICAAAAA==.Cherypoptart:BAABNQAECn8nAAILAAkK1RydFgCmAgALAAkK1RydFgCmAgAAAA==.Chrismeister:BAAANQAECgMIBAAAAA==.',
Ci='Citrate:BAAANQADCggIDAAAAA==.',
Co='Coomaka:BAAANQADCgUIBQAAAA==.Coraggioso:BAAANQAECgMICQAAAA==.Corbenik:BAABNQAECn8oAAIMAAcKBhPLKgCHAQAMAAcKBhPLKgCHAQAAAA==.',
Cr='Crodock:BAAANQABCgQIBgAAAA==.',
Cy='Cypress:BAAANQADCgYIBgAAAA==.',
['Cä']='Cähira:BAAANQADCggIFwAAAA==.',
Da='Dainaira:BAABNQAECn8bAAILAAgK/gccPgA7AQALAAgK/gccPgA7AQAAAA==.Daisia:BAAANQABCgIIAgAAAA==.Darowen:BAAANQAECggIDQAAAA==.Daul:BAABNQAECn8XAAIMAAoKogm+NgAyAQAMAAoKogm+NgAyAQAAAA==.',
De='Delti:BAAANQADCgUIBQABNQAECggIKgANAJIaAA==.Demonsmind:BAABNQAECn8ZAAQOAAkKhQ3/HQB+AQAOAAcK9Qr/HQB+AQAPAAgKZAoCoACwAAAQAAEKFQt5LQA7AAAAAA==.Derien:BAABNQAECn8pAAIJAAgKvBrHDQBUAgAJAAgKvBrHDQBUAgAAAA==.Devlyn:BAAANQADCgcIHwAAAA==.',
Do='Donkeyteeth:BAAANQAECgcIDwAAAA==.Donkeyteeths:BAAANQAECgYICgAAAA==.',
Dr='Dromak:BAAANQAECgUIBwAAAA==.Drusila:BAAANQAECgUIBQAAAA==.Drynn:BAAANQADCgYIBgAAAA==.Drywater:BAABNQAECn8nAAIRAAcKeQ2ZFQBTAQARAAcKeQ2ZFQBTAQAAAA==.',
El='Elfblood:BAABNQAECn8qAAIOAAcK3AeKCwDEAAAOAAcK3AeKCwDEAAAAAA==.Elvion:BAAANQADCgQIBAAAAA==.',
Em='Emitsabah:BAAANQADCgUIBQAAAA==.Emongar:BAAANQADCgcIBwAAAA==.',
Fa='Fabulosa:BAAANQAECgcIDgAAAA==.Faith:BAAANQAECgUIBgAAAA==.',
Fi='Finite:BAAANQAECgUIBAABNQAECgkJKgAKAIUUAA==.Firebug:BAAANQAECgYIEgAAAA==.',
Fl='Flyke:BAABNQAECn8ZAAISAAgKsAeJrADuAAASAAgKsAeJrADuAAAAAA==.Flyscrossmap:BAAANQAECgEIAQAAAA==.',
Fn='Fndruid:BAAANQAECgEIAQAAAA==.Fnwarlock:BAAANQAECgMIBAAAAA==.',
Fu='Furnok:BAABNQAECn8nAAMTAAcKbBTwNwC8AQATAAcKbBTwNwC8AQADAAcKKxG6UQAYAQAAAA==.',
Ga='Galethia:BAAANQADCgUIBgAAAA==.Garmjackyl:BAAANQADCgMIAQAAAA==.',
Gh='Ghandaloren:BAAANQADCgUIBQAAAA==.Ghia:BAAANQADCgUIBQABNQAECgEIAgAUAAAAAA==.Ghortash:BAAANQABCgYICwAAAA==.Ghrim:BAAANQAECgIIAwAAAA==.Ghutz:BAABNQAECn9GAAIVAAoKyxPfNAABAgAVAAoKyxPfNAABAgAAAA==.',
Go='Gonja:BAAANQADCgUICAAAAA==.',
Gr='Grave:BAABNQAECn84AAMCAAkKKCLFDgA5AwACAAkKKCLFDgA5AwABAAQKpRiYVADGAAAAAA==.',
Gu='Gumbercules:BAABNQAECn8oAAIWAAcKuwu5EwAuAQAWAAcKuwu5EwAuAQAAAA==.',
Ha='Harina:BAAANQABCgMIAgAAAA==.',
He='Hearthglen:BAABNQAECn8aAAIKAAgK/AxrzACDAQAKAAgK/AxrzACDAQAAAA==.',
Ho='Hollet:BAAANQAECgQICgAAAA==.Holykill:BAABNQAECn8mAAIMAAgK/QrCIQDuAAAMAAgK/QrCIQDuAAAAAA==.',
Hu='Hunttard:BAAANQAECgMIAwAAAA==.',
Hy='Hydrack:BAAANQADCgYIBAAAAA==.Hylen:BAABNQAECn8pAAMQAAkKUhMXCQD1AQAQAAcKpxcXCQD1AQAPAAQKgwuCpwCiAAAAAA==.',
['Hë']='Hëllboy:BAAANQABCgMIAwAAAA==.',
Ib='Ibrandul:BAABNQAECn8gAAIKAAoKMBFxZwCIAQAKAAoKMBFxZwCIAQAAAA==.',
Ic='Iceepop:BAAANQAECgUIBQAAAA==.',
Ir='Iroha:BAAANQADCgMIAwAAAA==.Ironhuntress:BAAANQAECgUIBQAAAA==.',
It='Ithro:BAABNQAECn8bAAIXAAoKehHeMwAMAgAXAAoKehHeMwAMAgAAAA==.',
Iy='Iyachtu:BAAANQADCgEIAQAAAA==.',
Ja='Jarlo:BAABNQAECn8eAAIXAAcKWxGeGAA3AQAXAAcKWxGeGAA3AQAAAA==.Jaydeki:BAAANQADCgQIBAAAAA==.',
Je='Jeffarg:BAAANQAECgEIAQABNQAECgoKOgAYALsZAA==.Jefficiently:BAABNQAECn86AAQYAAoKuxnHDwDLAQAZAAkKLhm/QwCgAgAYAAkK5RPHDwDLAQAaAAQKjx2MDAANAQAAAA==.Jestus:BAAANQADCgQIAwAAAA==.',
Ji='Jinsoftpaw:BAAANQAECgQIBAAAAA==.',
Jo='Joolianm:BAACNQAFFH8ZAAMRAAcKbxQ0BADTAAASAAUKWBfrGwCdAQARAAMKERA0BADTAAA1AAQKfysABBIACgqkIgQ9AAwDABIACgqkIgQ9AAwDABsAAgpVIJMDALoAABEAAQqjIoUiAGIAAAAA.Jormungandr:BAABNQAECn8iAAMVAAoKOxR7VACFAQAVAAoKOxR7VACFAQAJAAEKAAClQAA9AAAAAA==.',
Ju='Juandolf:BAAANQAECgMIBQAAAA==.Juanhunglow:BAAANQADCgUIFAAAAA==.Jularity:BAAANQAECgEJAQAAAA==.',
Ka='Kadryan:BAAANQADCgcIEwAAAA==.Kaeldric:BAAANQAECgMICQAAAA==.Kairilynn:BAAANQAECgEIAQAAAA==.Kalemshai:BAAANQAECgQIBQAAAA==.Kalinea:BAABNQAECn8lAAIZAAoKhRADaABEAgAZAAoKhRADaABEAgAAAA==.',
Ke='Kellice:BAAANQAECgEIAQAAAA==.Keruptadin:BAAANQAECgYICAAAAA==.',
Kh='Khedriss:BAABNQAECn8aAAISAAgKyATTwgDEAAASAAgKyATTwgDEAAAAAA==.',
Ko='Konerik:BAAANQABCgQIDgAAAA==.Kope:BAABNQAECn8pAAIWAAgKmB94DADdAgAWAAgKmB94DADdAgAAAA==.',
Kr='Krugor:BAAANQAECgQICAAAAA==.Kruptis:BAAANQADCgQIBAAAAA==.Kryptikz:BAAANQADCgEIAQABNQAECggIGwAJANoaAA==.Krystoferson:BAABNQAECn8WAAIcAAUK1gMcdgCQAAAcAAUK1gMcdgCQAAAAAA==.',
Ku='Kurdis:BAAANQABCgUIBwAAAA==.',
['Kà']='Kàw:BAAANQADCggJIAAAAA==.',
La='Labiy:BAAANQADCgYIDAAAAA==.Lalatína:BAAANQADCgYIBgAAAA==.',
Le='Leelu:BAAANQADCgQIBAABNQADCggIFwAUAAAAAA==.Leianii:BAAANQAECgMIAwAAAA==.',
Lh='Lhondar:BAAANQAECgMIAwAAAA==.',
Li='Lifehammer:BAAANQADCggIDAABNQAECgoKPQAIAL4dAA==.Likkaru:BAAANQADCgMIBAAAAA==.Liljess:BAAANQADCgYJBgABNQAECgMIAwAUAAAAAA==.Lillat:BAAANQAECgQIBAAAAA==.Lin:BAAANQADCgMIAwAAAA==.Littlepop:BAAANQADCgcIDQAAAA==.',
Lu='Luciamar:BAAANQADCggICAABNQAFFAUIEgAWAFUUAA==.Lumi:BAAANQADCgYIEgAAAA==.Luuggork:BAAANQADCgIIAgAAAA==.Luxfire:BAAANQADCgMIAwAAAA==.',
Ly='Lyarith:BAAANQADCgUIBwAAAA==.',
['Lì']='Lìesson:BAEBNQAECn8cAAIKAAoKNxq3dQBCAgAKAAoKNxq3dQBCAgAAAA==.',
Ma='Mackaroni:BAAANQADCgEIAQABNQAECgEIAgAUAAAAAA==.Magesca:BAABNQAECn8nAAIRAAcKvBWlDADvAQARAAcKvBWlDADvAQAAAA==.Makkagg:BAABNQAECn8fAAIdAAkKKhkvDQDlAQAdAAkKKhkvDQDlAQAAAA==.',
Me='Megastorm:BAAANQABCgUIBwAAAA==.Merillion:BAAANQABCgIIAgAAAA==.',
Mg='Mghtymage:BAAANQADCggIEwAAAA==.',
Mi='Milagrosa:BAABNQAECn8YAAIeAAoKfAv/DACBAQAeAAoKfAv/DACBAQAAAA==.Millanya:BAAANQADCgcIBwAAAA==.Mirael:BAACNQAFFH8HAAIZAAMKLgt6DgDfAAAZAAMKLgt6DgDfAAA1AAQKf0YAAhkACgo4H00oAPcCABkACgo4H00oAPcCAAAA.',
Mo='Mommanoo:BAAANQAECgYICgAAAA==.Mordenthal:BAAANQAECgEIAQABNQAECgUIBQAUAAAAAA==.',
Mu='Mumshun:BAAANQAECggICAAAAA==.',
My='Mykester:BAAANQABCgIIAgAAAA==.Myrmia:BAAANQAECgIJAgAAAA==.',
Na='Nails:BAAANQADCgYIBwAAAA==.Nanumar:BAAANQAECgYIBgABNQAECggIHQAfAEYWAA==.Natyri:BAAANQAECgUICQAAAA==.Naxximarus:BAAANQAECgcIDwABNQAECgoKQgAEAOUfAA==.',
Ni='Nightowl:BAAANQABCgIIAgAAAA==.Nirazen:BAAANQAECgQIBgAAAA==.',
No='Nota:BAABNQAECn8aAAIKAAgKPQNoDAEKAQAKAAgKPQNoDAEKAQAAAA==.',
Og='Ogrusao:BAAANQAECgMIBgAAAA==.',
Ol='Olaaru:BAAANQAECgUIBQAAAA==.',
Om='Omelette:BAAANQAECgIJAgAAAA==.',
Pa='Panasaurus:BAABNQAECn8nAAMIAAcK5RfXKwDjAQAIAAcK5RfXKwDjAQANAAMKYgpbFwB7AAAAAA==.',
Pe='Pelli:BAAANQAECgMICAAAAA==.Pendraig:BAAANQADCggIIgABNQAECgYICgAUAAAAAA==.',
Pi='Pink:BAAANQAECgQIBwAAAA==.',
Po='Popchop:BAAANQAECgEIAQABNQAECggIDwAUAAAAAA==.',
Pu='Purgatorium:BAAANQAECggIBgAAAA==.',
Ra='Rainedancer:BAABNQAECn8sAAITAAoKVxeSWQAEAgATAAoKVxeSWQAEAgAAAA==.Rat:BAAANQAECggIEQABNQAFFAYIFgATAM4bAA==.Rawriior:BAAANQABCgQIBQAAAA==.Raynez:BAAANQADCgYICAABNQAECggIGwAJANoaAA==.',
Rh='Rhalek:BAABNQAECn8bAAIGAAYKOiMODwA5AgAGAAYKOiMODwA5AgABNQAECgoKRAAGAAQfAA==.Rheunae:BAAANQAECgYICgAAAA==.Rhykis:BAABNQAECn8bAAIVAAgKZyDCZwBZAgAVAAgKZyDCZwBZAgAAAA==.',
Ro='Rogztaudru:BAAANQABCgEIAQAAAA==.',
Sa='Sabba:BAAANQAECgMICAAAAA==.Sableanne:BAAANQAECgcIDgAAAA==.Sacrament:BAAANQAECggIBgABNQAECgoKFwAMAKIJAA==.Sagearian:BAAANQAECgEIAgAAAA==.Samanda:BAAANQAECgYIDwAAAA==.Samshir:BAAANQAECgUIBQABNQAECggIGgASAMgEAA==.Sapped:BAABNQAECn8VAAMXAAkKUg8UMgAWAgAXAAkKUg8UMgAWAgAcAAIKDBQZkQBGAAABNQAECgEIAgAUAAAAAA==.Sarinna:BAAANQADCgMIBQAAAA==.',
Se='Seosinz:BAAANQAECggIAQAAAA==.',
Sh='Shabbyshammy:BAAANQAECgQIBQAAAA==.Shariaan:BAAANQAECgEIAQAAAA==.Shaylinn:BAAANQADCgcIIAAAAA==.Shùkkle:BAABNQAECn8lAAIHAAkKLh1BGgD2AgAHAAkKLh1BGgD2AgAAAA==.',
Si='Siella:BAAANQAECgMICQAAAA==.Sinric:BAAANQAECgMIAwAAAA==.Sitrom:BAAANQAECgIIAgAAAA==.',
Sk='Skorvis:BAACNQAFFH8QAAMTAAMKOxaAFgD1AAATAAMKOxaAFgD1AAADAAMKlQs0FACIAAA1AAQKfyoAAxMACgrqHdgeAO8CABMACgrqHdgeAO8CAAMABwrtE3eEAJkBAAE1AAUUBggLAAUAFxAA.',
Sl='Sloshama:BAAANQAECgQIBQAAAA==.',
Sm='Smallfox:BAAANQADCgUIBQABNQAECgQIBAAUAAAAAA==.',
Sn='Snayderino:BAAANQADCgcIDAAAAA==.',
So='Solar:BAACNQAFFH8HAAIHAAMK9gv5GQDUAAAHAAMK9gv5GQDUAAA1AAQKfygAAwcACgoUHXsqAIUCAAcACgoUHXsqAIUCACAAAwojDgsYAMQAAAAA.Somenai:BAAANQADCgYICgAAAA==.Sora:BAAANQADCgYIBgAAAA==.Soulbaine:BAAANQADCgYIBgAAAA==.',
Sp='Spheria:BAABNQAECn8dAAIPAAcKdwdRiwDaAAAPAAcKdwdRiwDaAAAAAA==.',
Su='Surelyhots:BAAANQAECggIEQAAAA==.',
Ta='Tankdezoe:BAAANQADCgYJCAABNQAECgMIAwAUAAAAAA==.Tansonite:BAABNQAECn8lAAMMAAoKGg0SFQBeAQAMAAoKGg0SFQBeAQAKAAkKAAKDVAGZAAAAAA==.',
Te='Tequ:BAAANQADCgcIHQAAAA==.',
Th='Thrazul:BAAANQADCgMIAwAAAA==.',
Ti='Timeshade:BAAANQAECgEIAQAAAA==.Tine:BAABNQAECn8pAAISAAgKaxPGqQAuAgASAAgKaxPGqQAuAgAAAA==.',
To='Toray:BAAANQAECgMIAwAAAA==.',
Tr='Trinn:BAAANQADCgMIAwAAAA==.Triplesix:BAABNQAECn8fAAIhAAgKthIjJwBeAQAhAAgKthIjJwBeAQAAAA==.Trittia:BAAANQAECgEIAgAAAA==.Trixzia:BAAANQADCgUIBQABNQAECgIIAwAUAAAAAA==.Troky:BAAANQAECggIEAAAAA==.',
Ty='Tynk:BAAANQADCggIFwAAAA==.',
Ug='Ugh:BAEBNQAFFH8RAAICAAcKNSCgAgC/AQACAAcKNSCgAgC/AQAAAA==.',
Ur='Urza:BAAANQADCgMIAwAAAA==.',
Va='Vaewind:BAAANQADCgUIBQAAAA==.Valethus:BAABNQAECn8wAAMZAAkK9RTJWwBiAgAZAAkK9RTJWwBiAgAYAAEKAACvZAAAAAAAAA==.Valhuntar:BAABNQAECn8cAAIZAAYKtA9wlgAEAQAZAAYKtA9wlgAEAQAAAA==.',
Ve='Velleria:BAAANQAECgUICAAAAA==.Verlis:BAAANQADCggIFgAAAA==.Vesp:BAAANQADCggIDwAAAA==.Veylla:BAAANQAECgIIAwAAAA==.',
Wa='Walkz:BAABNQAECn8bAAIJAAgK2hqwEAAdAgAJAAgK2hqwEAAdAgAAAA==.Warkkagg:BAABNQAECn8kAAIPAAoKWBoUKQAPAgAPAAoKWBoUKQAPAgABNQAECgkJHwAdACoZAA==.Waterworks:BAAANQAECgEIAQABNQAECgQIBAAUAAAAAA==.',
We='Weékly:BAAANQAECgQIBgAAAA==.',
Wi='Wickedlight:BAABNQAECn8lAAILAAgKjhbgHwA8AgALAAgKjhbgHwA8AgAAAA==.Wickedlock:BAAANQADCgQIBAAAAA==.Willscarlet:BAAANQAECgQIAwAAAA==.',
Xu='Xunn:BAAANQADCgIIAgAAAA==.',
Yl='Ylkhalas:BAAANQAECgQIBAAAAA==.',
Yo='Yolks:BAAANQAECgcIEwAAAA==.',
Za='Zaareth:BAAANQAECgQIBgAAAA==.Zamual:BAAANQADCgMIAwAAAA==.Zaritym:BAABNQAECn8cAAIiAAgK5Bu9FQAgAgAiAAgK5Bu9FQAgAgAAAA==.',
Ze='Zelsada:BAAANQADCgcIBwAAAA==.',
Zi='Zibetha:BAABNQAECn83AAIOAAoKUxyKAwAJAwAOAAoKUxyKAwAJAwAAAA==.',
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
