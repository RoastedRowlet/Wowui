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

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Enhancement','Mage-Arcane','Hunter-BeastMastery','Paladin-Protection','Paladin-Holy','Druid-Guardian','Monk-Windwalker','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Mage-Fire','Druid-Feral','DeathKnight-Blood','Evoker-Preservation','Priest-Holy','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Warrior-Arms','Hunter-Survival','Shaman-Elemental','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaphrodite:BAAANQADCgMIAwAAAA==.',
Ab='Abyssalblink:BAACNQAFFH8fAAMBAAgKnBYJAwBfAgABAAgKnBYJAwBfAgACAAMKARB0DgC7AAA1AAQKfy4AAwEACgqWIjcUAG0CAAEACArIIzcUAG0CAAIACQr1G7AdAGQCAAAA.',
Ae='Aesthetic:BAAANQAECgEIAQAAAA==.',
Ah='Ahruud:BAAANQADCgMIAwAAAA==.',
Ak='Akeno:BAAANQADCgIIAgABNQAECgoKKAADALQcAA==.',
Al='Albie:BAABNQAECn8qAAIEAAoK0hPokgBaAgAEAAoK0hPokgBaAgAAAA==.Albtraum:BAAANQADCgMIAwAAAA==.Aleight:BAABNQAECn8lAAIFAAoKqA0RhwD9AQAFAAoKqA0RhwD9AQAAAA==.Alice:BAAANQADCgIIAgAAAA==.Alius:BAABNQAECn8ZAAIGAAkKwQtTLwDsAAAGAAkKwQtTLwDsAAAAAA==.',
Am='Ambellina:BAABNQAECn88AAIHAAoK9B1BIwDfAgAHAAoK9B1BIwDfAgAAAA==.',
An='Anveendra:BAAANQAECgcIEAAAAA==.',
Ba='Bambiietta:BAAANQAECgQIBgAAAA==.',
Be='Belanwolf:BAAANQADCgIIAgAAAA==.',
Bl='Blastoiz:BAAANQADCgYIBgAAAA==.',
Br='Branyo:BAAANQAECgUIBQAAAA==.',
Bu='Bulvar:BAAANQAECggIDgAAAA==.',
Ca='Caligos:BAAANQADCgQIBAAAAA==.Camilacream:BAAANQAECgEIAQAAAA==.Capriestson:BAAANQAECgEIAQAAAA==.Cardrin:BAABNQAECn8kAAIIAAoKNRYOEABfAgAIAAoKNRYOEABfAgAAAA==.',
Ce='Cerbulum:BAAANQADCgMIAwAAAA==.',
Ch='Chalupa:BAAANQAECggIBAAAAA==.Chat:BAAANQADCgMIAwAAAA==.Choplo:BAACNQAFFH8oAAIJAAkK6xdjAQBZAgAJAAkK6xdjAQBZAgA1AAQKfx0AAgkACgrrIMUZAHQCAAkACgrrIMUZAHQCAAAA.Chudmuffin:BAABNQAECn8gAAIEAAkKIQ54DQF2AQAEAAkKIQ54DQF2AQAAAA==.',
Ci='Cinema:BAABNQAECn8ZAAMEAAkK1yH0gwB2AgAEAAkKzyH0gwB2AgAKAAEK2CRyOwBSAAAAAA==.',
Cl='Clarence:BAAANQADCgIIAgAAAA==.Closetotoast:BAAANQADCgMIAwAAAA==.',
Co='Cobalt:BAAANQAECgMJAwABNQAFFAYICgALAHsRAA==.',
Cr='Creativename:BAAANQAECgEIAQAAAA==.Crona:BAAANQADCgIIAgAAAA==.',
Da='Daemon:BAABNQAECn8aAAQMAAkKBh+WCABzAgAMAAkKkhmWCABzAgALAAUKYSA+swBpAQANAAEKVx8KKwBBAAAAAA==.Dalast:BAAANQAECgEIAQAAAA==.',
De='Debockulus:BAABNQAECn9iAAMLAAoKVx7qGQCmAgALAAoKVx7qGQCmAgAMAAUKfQWePgDIAAAAAA==.Decentychi:BAABNQAECn8cAAIJAAgKdh7+EQAtAgAJAAgKdh7+EQAtAgAAAA==.Dedia:BAAANQAECgEIAgAAAA==.Derangedxo:BAACNQAFFH8lAAQLAAkKCCMoAwAGAgALAAgKbiMoAwAGAgANAAEKoiDFBwBkAAAMAAEKhBhtGwBPAAA1AAQKfyoAAwsACgpwJtwBAHcDAAsACgppJtwBAHcDAAwABwrvICwJAGcCAAAA.Desirabelle:BAAANQADCggICAAAAA==.',
Do='Doggie:BAAANQADCgMIAwAAAA==.',
Dr='Dreambreath:BAAANQAECgMIBQAAAA==.Droppi:BAAANQADCggICAAAAA==.Drunkenhoe:BAABNQAECn8eAAIOAAkKDwgdzwAjAQAOAAkKDwgdzwAjAQAAAA==.',
Du='Dumazz:BAAANQADCgQIBAAAAA==.',
Ea='Earthwalkin:BAAANQAECgEIAQAAAA==.',
Ed='Edger:BAAANQADCgMIAwAAAA==.',
El='Elcomer:BAAANQADCgIIAgAAAA==.',
En='Enana:BAABNQAECn8WAAIPAAgKMQl0jQBnAQAPAAgKMQl0jQBnAQAAAA==.Enkor:BAAANQAECggIEAAAAA==.',
Er='Era:BAABNQAECn8ZAAINAAcKwhM8CgDWAQANAAcKwhM8CgDWAQABNQADCgMIAwAQAAAAAA==.',
Ev='Everblack:BAABNQAECn89AAQMAAoKPB9mAwDvAQAMAAkKPB9mAwDvAQALAAgKaRA3jwDAAQANAAMKSiGgGADFAAAAAA==.Evilcretin:BAACNQAFFH8GAAIEAAIKGCGjKQC/AAAEAAIKGCGjKQC/AAA1AAQKf64ABAQACgrLJr0AAIwDAAQACgrLJr0AAIwDAAoAAgqwI0MjANIAABEAAgpYIBEKAGIAAAAA.',
Fa='Faraah:BAABNQAECn9IAAMSAAoKiiTuAADYAwASAAoKiiTuAADYAwAIAAEKMRk6WgBTAAAAAA==.',
Ga='Ganondorf:BAABNQAECn8rAAITAAoKZhWZRwDaAQATAAoKZhWZRwDaAQAAAA==.Gatecrashr:BAAANQAECgIIAgAAAA==.',
Gi='Gimlï:BAAANQADCgYICgAAAA==.',
Gl='Gluttony:BAAANQAECgcICgABNQAECgoKLwADAOIVAA==.',
Gn='Gnosis:BAAANQAECgEIAQAAAA==.',
Go='Goch:BAABNQAECn8WAAMGAAcKCRCDNgA0AQAOAAcKuw9S1ABzAQAGAAcKzwyDNgA0AQAAAA==.Gochalufagus:BAAANQADCgIIAgAAAA==.Goldenwind:BAAANQAECggIBQAAAA==.Goodluck:BAAANQADCgMIAwABNQAFFAYIFQAUAOIXAA==.',
Gp='Gp:BAAANQAECgEIAQAAAA==.',
Gr='Grimdark:BAABNQAECn8xAAIPAAoK/RLrbwC7AQAPAAoK/RLrbwC7AQAAAA==.Grunge:BAACNQAFFH8HAAILAAUKMgo6EAARAQALAAUKMgo6EAARAQA1AAQKfxgAAgsACgoHHYQjAHUCAAsACgoHHYQjAHUCAAAA.Gruv:BAAANQAECggIAwAAAA==.',
Ha='Haven:BAAANQAECgEIAgAAAA==.',
He='Heathermarie:BAABNQAECn87AAIRAAoK3SPTAAAnAwARAAoK3SPTAAAnAwAAAA==.',
Hi='Hinata:BAAANQAECgUIBgAAAA==.Hippojaxx:BAAANQAECggICAAAAA==.',
Ho='Holdmyhammer:BAAANQADCgMIAwAAAA==.Holypride:BAAANQADCgUIBQABNQAECgoKLwADAOIVAA==.Hotbut:BAABNQAECn82AAIVAAoKFiEqDAByAwAVAAoKFiEqDAByAwAAAA==.',
['Hø']='Hørus:BAAANQADCgcIBwAAAA==.',
Ia='Iaptopz:BAAANQADCgcIDQAAAA==.',
Il='Illuminaxus:BAAANQAECgIIAgAAAA==.',
Ir='Irishbaby:BAAANQAECgEJAgAAAA==.',
Iz='Iza:BAABNQAECn8vAAIPAAoK7A7MdQCqAQAPAAoK7A7MdQCqAQAAAA==.Izis:BAAANQAECgIIAQAAAA==.',
Ja='Jake:BAEANQAECgcIDwABNQAFFAkJJgAEAAQdAA==.',
Je='Jeisansan:BAABNQAECn8YAAMWAAoKXg3uJwCUAQAWAAoKXg3uJwCUAQAXAAYKYgm8YQCMAAAAAA==.',
Ju='Juri:BAAANQAFFAEIAQAAAA==.',
Ka='Kads:BAAANQAECgQIAgABNQAFFAgIBgAXAEUmAA==.Kallivor:BAABNQAECn8VAAIBAAkKhBY+NwBRAQABAAkKhBY+NwBRAQAAAA==.Kanbu:BAAANQADCgEIAQAAAA==.Kardd:BAABNQAECn8sAAQTAAoKqx6kDQC2AgATAAkKqx6kDQC2AgAYAAgKSRalWwChAQAZAAIKZwbbnQBVAAAAAA==.',
Ke='Keeburn:BAAANQABCgEIAQAAAA==.Keltic:BAABNQAECn8fAAMVAAkKuxLYUADgAQAVAAkKuxLYUADgAQAaAAIK5wACmAAHAAAAAA==.',
Kh='Khantyer:BAAANQADCgYIAwAAAA==.',
Ki='Kigafan:BAAANQAECggIBwAAAA==.Kiing:BAAANQADCgUIBQAAAA==.',
Kr='Krow:BAAANQADCgIIAgAAAA==.Krowlhy:BAAANQAECgIIAwAAAA==.',
La='Laezel:BAABNQAECn8yAAIbAAoKaB54UQD4AQAbAAoKaB54UQD4AQAAAA==.Lamppost:BAACNQAFFH8JAAIcAAMKxyOWAAAbAQAcAAMKxyOWAAAbAQA1AAQKfywAAhwACgpeJkkAANsDABwACgpeJkkAANsDAAAA.Landliebe:BAAANQADCggILwAAAA==.Lannister:BAAANQADCgUIBQABNQAECgoKMAAUACwVAA==.',
Le='Lereios:BAAANQAECgYIDgABNQAECgkJFAALAFoOAA==.Lessons:BAAANQADCgEIAQAAAA==.',
Li='Lightsmith:BAAANQAECgQIBgAAAA==.Lilpump:BAAANQAECgYICgABNQAECggIEAAQAAAAAA==.Lith:BAACNQAFFH8PAAIBAAYKCRw2BwBlAQABAAYKCRw2BwBlAQA1AAQKfzsAAwEACgqtI7gEAD0DAAEACgqtI7gEAD0DAAIAAQoAAMd0ACUAAAAA.Liyun:BAAANQAECgIIAwAAAA==.',
['Lø']='Løry:BAAANQAFFAIIAwABNQAFFAcIDAAHAMYQAA==.',
Ma='Mahyor:BAABNQAECn8dAAMPAAgKTxQ8XwDxAQAPAAgKTxQ8XwDxAQAdAAYK1xpXgwCcAQAAAA==.Maroonfive:BAAANQAECgYICwABNQAFFAUIBwAdAFMJAA==.Maybringer:BAAANQADCgQIBAAAAA==.Mazzmerize:BAACNQAFFH8XAAMeAAcK1yFIBgDyAQAeAAcKox9IBgDyAQAFAAMKHCX1JgBkAAA1AAQKfx8AAx4ACQrIH50bAHcCAB4ACQpEGp0bAHcCAAUABgqXDpbvACIBAAE1AAUUCgpBAAQA2iIA.',
Mi='Minimage:BAAANQAECgMIAwAAAA==.Miramitotem:BAAANQAECggICgAAAA==.',
Mu='Murmurr:BAAANQAECgEIAgAAAA==.',
Na='Naric:BAABNQAECn8UAAQLAAkKWg7sbQAVAgALAAkKWg7sbQAVAgANAAIK6hRNHgCJAAAMAAEKAACydwA2AAAAAA==.Narium:BAAANQAECgEIAgAAAA==.Nasa:BAAANQAECgMIAwAAAA==.',
No='Nobru:BAAANQAECgQIDAAAAA==.Now:BAABNQAECn87AAMdAAoKbxvfJgA3AgAdAAoKbxvfJgA3AgAPAAIK1AXi9gAuAAAAAA==.',
Nt='Nt:BAAANQAECgQIBAABNQAECggIBgAQAAAAAA==.',
Nu='Nukenin:BAABNQAECn8zAAICAAoKgSV9BACNAwACAAoKgSV9BACNAwAAAA==.Nunquam:BAAANQAECgMIAwAAAA==.',
Ny='Nyrasha:BAACNQAFFH8LAAIFAAYKSA7rBQCAAQAFAAYKSA7rBQCAAQA1AAQKfzQAAgUACgrOIT4cACcDAAUACgrOIT4cACcDAAAA.',
Pa='Paredes:BAAANQAECgQIAwAAAA==.',
Pe='Peonu:BAABNQAECn8dAAMfAAoKxgolTwCCAQAfAAoKxgolTwCCAQAgAAQKJwdmPQDNAAAAAA==.',
Po='Police:BAABNQAECn8rAAMPAAoKwR/hFQAhAwAPAAoKwR/hFQAhAwAdAAUK6hfZhgCTAQAAAA==.',
Pr='Pride:BAABNQAECn8vAAIDAAoK4hUTDgCLAgADAAoK4hUTDgCLAgAAAA==.Prophesy:BAAANQAECgIIAgAAAA==.Proteus:BAABNQAECn8lAAMZAAkKAAxzQgB6AQAZAAkKAAxzQgB6AQAYAAMKxgbchAAzAAAAAA==.Prounion:BAAANQAECgEIAQABNQAECgYICAAQAAAAAA==.',
Pu='Puff:BAABNQAECn8YAAIEAAcKiRAX8QCoAQAEAAcKiRAX8QCoAQAAAA==.',
Ra='Rana:BAABNQAECn8aAAIFAAgKiROKXwDwAQAFAAgKiROKXwDwAQAAAA==.Ratko:BAAANQADCggIDwAAAA==.',
Re='Rekk:BAAANQAECggICQAAAA==.Reventön:BAAANQADCgcIBgAAAA==.Rey:BAAANQAECgUIDwABNQAFFAQIBQAFAA0RAA==.',
Rh='Rhaevness:BAAANQAECgYIBgAAAA==.',
Ro='Rockandstone:BAABNQAECn8cAAMPAAoK9BqtNwCAAgAPAAoK9BqtNwCAAgAdAAEKAAA1TgEnAAAAAA==.',
Ru='Rubyredyoshi:BAAANQAECgYIBwAAAA==.Runtzsr:BAAANQABCgQIBQAAAA==.',
['Rá']='Ráîstlin:BAABNQAECn8zAAMKAAoKLRZvEQCPAQAKAAkKLRZvEQCPAQAEAAkKpQoQpQBIAQAAAA==.',
['Rü']='Rüntzz:BAAANQABCggIDwAAAA==.',
Sa='Sanguinary:BAAANQABCgQIAgAAAA==.Savagecow:BAAANQAECgMIAwAAAA==.',
Se='Selro:BAAANQAECgUIBwAAAA==.',
Sh='Shadøw:BAAANQAECgQIBQAAAA==.Shinoa:BAAANQAECgIIAQAAAA==.Shlongtofoot:BAAANQAECgMIAwAAAA==.Shockzzer:BAAANQADCgMIAwAAAA==.',
Sk='Skyvoh:BAAANQAECgMIBAAAAA==.',
So='Soulszaura:BAAANQAECgQIBAAAAA==.',
St='Starchucker:BAACNQAFFH8RAAICAAYK+hWgBwCOAQACAAYK+hWgBwCOAQA1AAQKf0cAAgIACgq3IrYGAGcDAAIACgq3IrYGAGcDAAAA.',
Sw='Swade:BAAANQADCgQIBAABNQADCgYIBgAQAAAAAA==.Sweetnwicked:BAABNQAECn8YAAMMAAgKcAlkQADBAAALAAcKVwgC1QAgAQAMAAQKcgpkQADBAAAAAA==.',
Sy='Synarri:BAABNQAECn8YAAMOAAkK8hMwkAAEAgAOAAgK8hQwkAAEAgAHAAcKdRZ1XQAAAgABNQAFFAkJIQAHAEkYAA==.Syneria:BAACNQAFFH8hAAMHAAkKSRhSAQC3AgAHAAkKSRhSAQC3AgAOAAMKBQ7ILQBHAAA1AAQKf+4AAwcACgp5JW8AAPUDAAcACgp5JW8AAPUDAA4ACgrTJKQUAAwDAAAA.Syneriah:BAAANQAECgEIAgABNQAFFAkJIQAHAEkYAA==.Synn:BAAANQADCggICAABNQAFFAkJIQAHAEkYAA==.Synnamon:BAACNQAFFH8KAAMHAAYKrg7cDABhAQAHAAUKgArcDABhAQAOAAIKCCE1HQC9AAA1AAQKf2IAAw4ACgpAJlcCAO0DAA4ACgpAJlcCAO0DAAcABgr9CKmyABkBAAE1AAUUCQkhAAcASRgA.Synpai:BAACNQAFFH8UAAMHAAYKDg9zCQDJAQAHAAYKDg9zCQDJAQAOAAQK5RLFFgDIAAA1AAQKf3AAAw4ACgrTJeQMADgDAA4ACgrTJeQMADgDAAcABwoHHbdcAAICAAE1AAUUCQkhAAcASRgA.',
Ta='Taciitus:BAABNQAECn8pAAIJAAkKWx3zFQChAgAJAAkKWx3zFQChAgAAAA==.Tailzz:BAABNQAECn8fAAIeAAcKvwZRKQALAQAeAAcKvwZRKQALAQAAAA==.',
Th='Thebaptiser:BAAANQADCgUIBQAAAA==.Thermafrost:BAAANQAECgEIAQAAAA==.Thuggjr:BAAANQAECgMIAwABNQAFFAkJKAAJAOsXAA==.Thunderwar:BAAANQADCggIEgAAAA==.Thunderwings:BAAANQADCgIIAgAAAA==.',
Ti='Tiazy:BAAANQADCgYICAAAAA==.',
To='Toomato:BAAANQAECgUIDAAAAA==.Totemterror:BAABNQAECn8cAAIPAAoKDCWWAwCwAwAPAAoKDCWWAwCwAwAAAA==.Tough:BAAANQADCgQIBAAAAA==.',
Ty='Tydraduel:BAACNQAFFH8KAAILAAMKbg6tGADSAAALAAMKbg6tGADSAAA1AAQKfz4AAgsACgoEHwceAJACAAsACgoEHwceAJACAAAA.',
Tz='Tzuruchanise:BAAANQADCgMIBAAAAA==.',
Va='Vala:BAAANQAECgEIAQABNQAECgoKMAAUACwVAA==.Valy:BAAANQAECgYIEwAAAA==.Vannathyfall:BAAANQAECgEIAQAAAA==.Vany:BAAANQAECgEIAQAAAA==.',
Vo='Vora:BAAANQAECgYIEAAAAA==.',
Vw='Vw:BAAANQAECgIIAgAAAA==.',
Wa='Warglaive:BAABNQAECn8VAAMCAAYKwiHrJgBMAQACAAUKuCXrJgBMAQABAAMK7xjJXgCVAAAAAA==.',
Wh='Whalethen:BAAANQAECgcICAABNQAECgoKHAAPAAwlAA==.Wheresdebeef:BAAANQADCggIBAABNQAECgYICAAQAAAAAA==.',
Wi='Wikkid:BAAANQADCgUJBwAAAA==.Wikkidsin:BAAANQADCgUICAABNQADCgUJBwAQAAAAAA==.',
['Wù']='Wùlph:BAAANQAECgQIBAAAAA==.',
Xx='Xxz:BAAANQADCgUIBwAAAA==.',
Yi='Yiesus:BAAANQAECggIEAABNQAFFAgIHAACALEmAA==.',
Yo='Yomato:BAABNQAECn9AAAIWAAoKqB6nDQD1AgAWAAoKqB6nDQD1AgAAAA==.',
Yu='Yuanti:BAAANQADCgIIAgAAAA==.',
Za='Zabble:BAAANQAECgQIBAAAAA==.',
Ze='Zenocline:BAABNQAECn8vAAIJAAoKGBfEGwCwAQAJAAoKGBfEGwCwAQAAAA==.',
Zi='Zi:BAAANQAECggIDwAAAA==.',
['Ån']='Åntisocial:BAAANQAECgYICAAAAA==.',
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
