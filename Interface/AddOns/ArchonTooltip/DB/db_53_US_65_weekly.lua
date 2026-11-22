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

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Paladin-Protection','Paladin-Holy','Druid-Guardian','Monk-Windwalker','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Shaman-Restoration','Mage-Fire','Druid-Feral','DeathKnight-Blood','Shaman-Enhancement','Evoker-Preservation','Priest-Holy','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Warrior-Arms','Hunter-Survival','Shaman-Elemental','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaphrodite:BAAANQADCgMIAwAAAA==.',
Ab='Abyssalblink:BAACNQAFFH8hAAMBAAgK4xcJAwBfAgABAAgK4xcJAwBfAgACAAMKARB0DgC7AAA1AAQKfy4AAwEACgqWIhIWAGoCAAEACArIIxIWAGoCAAIACQr1G7AdAGQCAAAA.',
Ah='Ahruud:BAAANQADCgMIAwAAAA==.',
Ak='Akeno:BAAANQADCgIIAgABNQAECgUIBQADAAAAAA==.',
Al='Albie:BAABNQAECn8qAAIEAAoK0hPokgBaAgAEAAoK0hPokgBaAgAAAA==.Albtraum:BAAANQADCgMIAwAAAA==.Aleight:BAABNQAECn8lAAIFAAoKqA0RhwD9AQAFAAoKqA0RhwD9AQAAAA==.Alice:BAAANQADCgIIAgAAAA==.Alius:BAABNQAECn8oAAIGAAkKRwzyJABHAQAGAAkKRwzyJABHAQAAAA==.',
Am='Ambellina:BAABNQAECn8/AAIHAAoKdh9BIwDfAgAHAAoKdh9BIwDfAgAAAA==.',
An='Anveendra:BAAANQAECgcIEAAAAA==.',
Ba='Bambiietta:BAAANQAECgQIBgAAAA==.',
Be='Belanwolf:BAAANQADCgIIAgAAAA==.',
Bl='Blastoiz:BAAANQADCgYIBgAAAA==.',
Br='Branyo:BAAANQAECgUIBQAAAA==.',
Bu='Bulvar:BAAANQAECggIDgAAAA==.',
Ca='Caligos:BAAANQADCgQIBAAAAA==.Camilacream:BAAANQAECgEIAQAAAA==.Capriestson:BAAANQAECgEIAQAAAA==.Cardrin:BAABNQAECn8kAAIIAAoKNRYOEABfAgAIAAoKNRYOEABfAgAAAA==.',
Ce='Cerbulum:BAAANQADCgMIAwAAAA==.',
Ch='Chalupa:BAAANQAECggIAgAAAA==.Chat:BAAANQADCgMIAwAAAA==.Choplo:BAACNQAFFH8uAAIJAAkKFRt8AQB1AgAJAAkKFRt8AQB1AgA1AAQKfx0AAgkACgrrIMUZAHQCAAkACgrrIMUZAHQCAAAA.Chudmuffin:BAABNQAECn8gAAIEAAkKIQ54DQF2AQAEAAkKIQ54DQF2AQAAAA==.',
Ci='Cinema:BAABNQAECn8ZAAMEAAkK1yH0gwB2AgAEAAkKzyH0gwB2AgAKAAEK2CRyOwBSAAAAAA==.',
Cl='Clarence:BAAANQADCgIIAgAAAA==.Closetotoast:BAAANQADCgMIAwAAAA==.',
Co='Cobalt:BAAANQAECgMJAwABNQAFFAYICgALAHsRAA==.',
Cr='Creativename:BAAANQABCgUIBQAAAA==.Crona:BAAANQADCgIIAgAAAA==.',
Da='Daemon:BAABNQAECn8aAAQMAAkKBh+WCABzAgAMAAkKkhmWCABzAgALAAUKYSA+swBpAQANAAEKVx8KKwBBAAAAAA==.Dalast:BAAANQAECgEIAQAAAA==.',
De='Debockulus:BAABNQAECn9iAAMLAAoKVx7CHQCfAgALAAoKVx7CHQCfAgAMAAUKfQWePgDIAAAAAA==.Decentychi:BAABNQAECn8cAAIJAAgKdh6kEwArAgAJAAgKdh6kEwArAgAAAA==.Dedia:BAAANQAECgEIAQAAAA==.Derangedxo:BAACNQAFFH8pAAQLAAkKUyTHAwARAgALAAgK6yPHAwARAgANAAEKwyYBCAB1AAAMAAEKhBhtGwBPAAA1AAQKfyoAAwsACgpwJkkCAHMDAAsACgppJkkCAHMDAAwABwrvICwJAGcCAAAA.Desirabelle:BAAANQADCggICAAAAA==.',
Do='Doggie:BAAANQADCgMIAwAAAA==.',
Dr='Dreambreath:BAAANQAECgMIBQAAAA==.Droppi:BAAANQADCggICAAAAA==.Drunkenhoe:BAABNQAECn8eAAIOAAkKDwiq3gAfAQAOAAkKDwiq3gAfAQAAAA==.',
Du='Dumazz:BAAANQADCgQIBAAAAA==.',
Ea='Earthwalkin:BAAANQAECgEIAQAAAA==.',
Ed='Edger:BAAANQADCgMIAwAAAA==.',
El='Elcomer:BAAANQADCgIIAgAAAA==.',
En='Enana:BAABNQAECn8WAAIPAAgKMQl0jQBnAQAPAAgKMQl0jQBnAQAAAA==.Enkor:BAAANQAECggIDwAAAA==.',
Er='Era:BAABNQAECn8ZAAINAAcKwhM8CgDWAQANAAcKwhM8CgDWAQABNQADCgMIAwADAAAAAA==.',
Ev='Everblack:BAABNQAECn89AAQMAAoKPB9KBwCSAgAMAAkKPB9KBwCSAgALAAgKaRA3jwDAAQANAAMKSiGgGADFAAAAAA==.Evilcretin:BAACNQAFFH8HAAIEAAMKvCFYGgAiAQAEAAMKvCFYGgAiAQA1AAQKf7IABAQACgrLJgABAIoDAAQACgrLJgABAIoDAAoAAgqwI0MjANIAABAAAgpYIBEKAGIAAAAA.',
Fa='Faraah:BAABNQAECn9IAAMRAAoKiiTuAADYAwARAAoKiiTuAADYAwAIAAEKMRnaXwBTAAAAAA==.',
Ga='Ganondorf:BAABNQAECn8rAAISAAoKZhWZRwDaAQASAAoKZhWZRwDaAQAAAA==.Gatecrashr:BAAANQAECgIIAgAAAA==.',
Gi='Gimlï:BAAANQADCgYICgAAAA==.',
Gl='Gluttony:BAAANQAECgcICgABNQAECgoKMgATAOIVAA==.',
Gn='Gnosis:BAAANQADCggIFgAAAA==.',
Go='Goch:BAABNQAECn8WAAMGAAcKCRCDNgA0AQAOAAcKuw9S1ABzAQAGAAcKzwyDNgA0AQAAAA==.Gochalufagus:BAAANQADCgIIAgAAAA==.Goldenwind:BAAANQAECggIBAAAAA==.Goodluck:BAAANQADCgMIAwABNQAFFAYIFQAUAOIXAA==.',
Gp='Gp:BAAANQAECgEIAQAAAA==.',
Gr='Grimdark:BAABNQAECn8xAAIPAAoK/RLrbwC7AQAPAAoK/RLrbwC7AQAAAA==.Grunge:BAACNQAFFH8HAAILAAUKMgqdEwAJAQALAAUKMgqdEwAJAQA1AAQKfxgAAgsACgoHHQYoAG8CAAsACgoHHQYoAG8CAAAA.',
Ha='Haven:BAAANQAECgEIAQAAAA==.',
He='Heathermarie:BAABNQAECn9BAAIQAAoKKSTTAAAnAwAQAAoKKSTTAAAnAwAAAA==.',
Hi='Hinata:BAAANQAECgUIAwAAAA==.Hippojaxx:BAAANQAECggICAAAAA==.',
Ho='Holdmyhammer:BAAANQADCgMIAwAAAA==.Holypride:BAAANQADCgUIBQABNQAECgoKMgATAOIVAA==.Hotbut:BAABNQAECn82AAIVAAoKFiGgDgBnAwAVAAoKFiGgDgBnAwAAAA==.',
['Hø']='Hørus:BAAANQADCgcIBwAAAA==.',
Ia='Iaptopz:BAAANQADCgcIDQAAAA==.',
Il='Illuminaxus:BAAANQAECgIIAgAAAA==.',
Ir='Irishbaby:BAAANQAECgEJAgAAAA==.',
Iz='Iza:BAABNQAECn8vAAIPAAoK7A7MdQCqAQAPAAoK7A7MdQCqAQAAAA==.Izis:BAAANQAECgIIAQAAAA==.',
Ja='Jake:BAEANQAECgcIDQABNQAFFAkJLgAEAG4dAA==.',
Je='Jeisansan:BAABNQAECn8fAAMWAAoKng2xIgDiAQAWAAoKng2xIgDiAQAXAAgKPQp4SgD4AAAAAA==.',
Ju='Juri:BAAANQAFFAEIAQAAAA==.',
Ka='Kads:BAAANQAECgQIAgABNQAFFAgIBgAXAEUmAA==.Kallivor:BAABNQAECn8WAAIBAAkKBRglNgByAQABAAkKBRglNgByAQAAAA==.Kanbu:BAAANQADCgEIAQAAAA==.Kardd:BAABNQAECn8sAAQSAAoKqx6vDgCwAgASAAkKqx6vDgCwAgAYAAgKSRalWwChAQAZAAIKZwbbnQBVAAAAAA==.',
Ke='Keeburn:BAAANQABCgEIAQABNQABCgYICAADAAAAAA==.Keltic:BAABNQAECn8kAAMVAAkKgRfiNwBeAgAVAAkKgRfiNwBeAgAaAAIK5wACmAAHAAAAAA==.',
Kh='Khantyer:BAAANQADCgYIAwAAAA==.',
Ki='Kigafan:BAAANQAECggIBwAAAA==.Kiing:BAAANQADCgUIBQAAAA==.',
Kr='Krow:BAAANQADCgIIAgAAAA==.Krowlhy:BAAANQAECgIIAgAAAA==.',
La='Laezel:BAABNQAECn8yAAIbAAoKaB4LWQDzAQAbAAoKaB4LWQDzAQAAAA==.Lamppost:BAACNQAFFH8JAAIcAAMKxyOsAAAXAQAcAAMKxyOsAAAXAQA1AAQKfywAAhwACgpeJkkAANsDABwACgpeJkkAANsDAAAA.Landliebe:BAAANQADCggILwAAAA==.Lannister:BAAANQADCgUIBQABNQAECgoKMAAUACwVAA==.',
Le='Lereios:BAAANQAECgYIDgABNQAECgkJFAALAFoOAA==.Lessons:BAAANQADCgEIAQAAAA==.',
Li='Lightsmith:BAAANQAECgQIBQAAAA==.Lilpump:BAAANQAECgYIBwABNQAECggIDwADAAAAAA==.Lith:BAACNQAFFH8PAAIBAAYKCRzyCABcAQABAAYKCRzyCABcAQA1AAQKfzsAAwEACgqtI0YFADsDAAEACgqtI0YFADsDAAIAAQoAAMd0ACUAAAAA.Liyun:BAAANQAECgIIAgAAAA==.',
['Lø']='Løry:BAAANQAFFAIIAwABNQAFFAcIDAAHAMYQAA==.',
Ma='Mahyor:BAABNQAECn8dAAMPAAgKTxQ8XwDxAQAPAAgKTxQ8XwDxAQAdAAYK1xpXgwCcAQAAAA==.Maroonfive:BAAANQAECgYIDAABNQAFFAUIBwAdAFMJAA==.Maybringer:BAAANQADCgQIBAAAAA==.Mazzmerize:BAACNQAFFH8XAAMeAAcK1yFIBgDyAQAeAAcKox9IBgDyAQAFAAMKHCWNKgBkAAA1AAQKfx8AAx4ACQrIH50bAHcCAB4ACQpEGp0bAHcCAAUABgqXDpbvACIBAAE1AAUUCgpBAAQA2iIA.',
Mi='Minimage:BAAANQAECgMIAwAAAA==.Miramitotem:BAABNQAECn8UAAIdAAkKARPcOwDlAQAdAAkKARPcOwDlAQAAAA==.',
Mu='Murmurr:BAAANQAECgEIAQAAAA==.',
Na='Namí:BAAANQAECgEIAQAAAA==.Naric:BAABNQAECn8UAAQLAAkKWg7sbQAVAgALAAkKWg7sbQAVAgANAAIK6hRNHgCJAAAMAAEKAACydwA2AAAAAA==.Nasa:BAAANQAECgMIAwAAAA==.',
No='Nobru:BAAANQAECgQIDAAAAA==.Now:BAABNQAECn87AAMdAAoKbxvuKgAzAgAdAAoKbxvuKgAzAgAPAAIK1AXK/wAuAAAAAA==.',
Nt='Nt:BAAANQAECgQIBAABNQAECggIBgADAAAAAA==.',
Nu='Nukenin:BAABNQAECn80AAICAAoKgSV9BACNAwACAAoKgSV9BACNAwAAAA==.Nunquam:BAAANQAECgMIAwAAAA==.',
Ny='Nyrasha:BAACNQAFFH8LAAIFAAYKSA57BwB9AQAFAAYKSA57BwB9AQA1AAQKfzQAAgUACgrOIT4cACcDAAUACgrOIT4cACcDAAAA.',
Pa='Paredes:BAAANQAECgQIAwAAAA==.',
Pe='Peonu:BAABNQAECn8dAAMfAAoKxgolTwCCAQAfAAoKxgolTwCCAQAgAAQKJwdmPQDNAAAAAA==.',
Pi='Pillohpants:BAAANQAECgQIBQABNQAFFAEIAQADAAAAAA==.',
Po='Police:BAABNQAECn8rAAMPAAoKwR/hFQAhAwAPAAoKwR/hFQAhAwAdAAUK6hfZhgCTAQAAAA==.',
Pr='Pride:BAABNQAECn8yAAITAAoK4hUTDgCLAgATAAoK4hUTDgCLAgAAAA==.Prophesy:BAAANQAECgIIAgAAAA==.Proteus:BAABNQAECn8lAAMZAAkKAAzUSAB1AQAZAAkKAAzUSAB1AQAYAAMKxgaAigAzAAAAAA==.',
Pu='Puff:BAABNQAECn8YAAIEAAcKiRAX8QCoAQAEAAcKiRAX8QCoAQAAAA==.',
Ra='Rana:BAABNQAECn8aAAIFAAgKiRMeagDvAQAFAAgKiRMeagDvAQAAAA==.Ratko:BAAANQADCggIDwAAAA==.',
Re='Rekk:BAAANQAECggICAAAAA==.Reventön:BAAANQADCgcIBgAAAA==.Rey:BAAANQAECgUIDgABNQAFFAQIBQAFAA0RAA==.',
Rh='Rhaevness:BAAANQAECgcIBwAAAA==.',
Ro='Rockandstone:BAABNQAECn8cAAMPAAoK9BqtNwCAAgAPAAoK9BqtNwCAAgAdAAEKAAA1TgEnAAAAAA==.',
Ru='Rubyredyoshi:BAAANQAECgYIBgAAAA==.Runtzsr:BAAANQABCgQIBQAAAA==.',
['Rá']='Ráîstlin:BAABNQAECn80AAMKAAoKLRZvEQCPAQAKAAkKLRZvEQCPAQAEAAkKpQq3rgBHAQAAAA==.',
['Rü']='Rüntzz:BAAANQABCggIDwAAAA==.',
Sa='Sanguinary:BAAANQABCgQIAgAAAA==.Savagecow:BAAANQAECgMIAwAAAA==.',
Se='Selro:BAAANQAECgUIBgAAAA==.',
Sh='Shadøw:BAAANQAECgQIBQAAAA==.Shinoa:BAAANQAECgIIAQAAAA==.Shlongtofoot:BAAANQAECgMIAwAAAA==.Shockzzer:BAAANQADCgMIAwAAAA==.',
Sk='Skyvoh:BAAANQAECgMIBAAAAA==.',
So='Soulszaura:BAAANQAECgQIBAAAAA==.',
St='Starchucker:BAACNQAFFH8RAAICAAYK+hWgBwCOAQACAAYK+hWgBwCOAQA1AAQKf0gAAgIACgq3IrYGAGcDAAIACgq3IrYGAGcDAAAA.',
Sw='Swade:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.Sweetnwicked:BAABNQAECn8YAAMMAAgKcAlkQADBAAALAAcKVwgC1QAgAQAMAAQKcgpkQADBAAAAAA==.',
Sy='Synarri:BAABNQAECn8YAAMOAAkK8hMwkAAEAgAOAAgK8hQwkAAEAgAHAAcKdRZ1XQAAAgABNQAFFAkJJwAHAJ8bAA==.Syneria:BAACNQAFFH8nAAMHAAkKnxtSAQC3AgAHAAkKnxtSAQC3AgAOAAQKcxXBHACxAAA1AAQKf/MAAwcACgp5JW8AAPUDAAcACgp5JW8AAPUDAA4ACgrlJD0WAGsDAAAA.Syneriah:BAAANQAECgEIAQABNQAFFAkJJwAHAJ8bAA==.Synn:BAAANQADCggICAABNQAFFAkJJwAHAJ8bAA==.Synnamon:BAACNQAFFH8KAAMHAAYKrg65DgBcAQAHAAUKgAq5DgBcAQAOAAIKCCE1HQC9AAA1AAQKf2UAAw4ACgpGJlcCAO0DAA4ACgpGJlcCAO0DAAcABgpODamyABkBAAE1AAUUCQknAAcAnxsA.Synpai:BAACNQAFFH8VAAMHAAcKGg5zCQDJAQAHAAcKGg5zCQDJAQAOAAQK5RIjGgDCAAA1AAQKf3oAAw4ACgr2JX8KAEsDAA4ACgr2JX8KAEsDAAcABwpbH7dcAAICAAE1AAUUCQknAAcAnxsA.',
Ta='Taciitus:BAABNQAECn8pAAIJAAkKWx3zFQChAgAJAAkKWx3zFQChAgAAAA==.Tailzz:BAABNQAECn8fAAIeAAcKvwYMLAALAQAeAAcKvwYMLAALAQAAAA==.',
Th='Thebaptiser:BAAANQADCgUIBQAAAA==.Thuggjr:BAAANQAECgMIAwABNQAFFAkJLgAJABUbAA==.Thunderwar:BAAANQADCggIEgAAAA==.Thunderwings:BAAANQADCgIIAgAAAA==.',
Ti='Tiazy:BAAANQADCgYICAAAAA==.',
To='Toomato:BAAANQAECgYICgAAAA==.Totemterror:BAABNQAECn8cAAIPAAoKDCWWAwCwAwAPAAoKDCWWAwCwAwAAAA==.Tough:BAAANQADCgQIBAAAAA==.',
Ty='Tydraduel:BAACNQAFFH8KAAILAAMKbg4yHADOAAALAAMKbg4yHADOAAA1AAQKfz4AAgsACgoEH3kkAPICAAsACgoEH3kkAPICAAAA.',
Tz='Tzuruchanise:BAAANQADCgMIBAAAAA==.',
Va='Vala:BAAANQAECgEIAQABNQAECgoKMAAUACwVAA==.Valy:BAAANQAECgYIDwAAAA==.Vannathyfall:BAAANQAECgEIAQAAAA==.Vany:BAAANQAECgEIAQAAAA==.',
Vo='Vora:BAAANQAECgYIEAAAAA==.',
Vw='Vw:BAAANQAECgIIAgAAAA==.',
Wa='Warglaive:BAABNQAECn8XAAMCAAYKPiXkHQC2AQACAAYKPiXkHQC2AQABAAMK7xhTZACTAAAAAA==.',
Wh='Whalethen:BAAANQAECgcICAABNQAECgoKHAAPAAwlAA==.Wheresdebeef:BAAANQADCggIBAABNQAECgYIBwADAAAAAA==.',
Wi='Wikkid:BAAANQADCgUJBwAAAA==.Wikkidsin:BAAANQADCgUICAABNQADCgUJBwADAAAAAA==.',
['Wù']='Wùlph:BAAANQAECgYICQAAAA==.',
Xx='Xxz:BAAANQADCgUIBwAAAA==.',
Yi='Yiesus:BAAANQAECggIDwABNQAFFAgIHAACALEmAA==.',
Yo='Yomato:BAABNQAECn9AAAIWAAoKqB6nDQD1AgAWAAoKqB6nDQD1AgAAAA==.',
Yu='Yuanti:BAAANQADCgIIAgAAAA==.',
Za='Zabble:BAAANQAECgQIBAAAAA==.',
Ze='Zenocline:BAABNQAECn8zAAIJAAoKjRc8HQC6AQAJAAoKjRc8HQC6AQAAAA==.',
Zi='Zi:BAAANQAECggIDwAAAA==.',
['Ån']='Åntisocial:BAAANQAECgYIBwAAAA==.',
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
