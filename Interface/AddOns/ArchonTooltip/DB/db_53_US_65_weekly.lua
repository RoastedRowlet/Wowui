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

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','Monk-Windwalker','Shaman-Enhancement','Mage-Arcane','Hunter-BeastMastery','Paladin-Holy','Druid-Guardian','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Mage-Fire','Druid-Feral','DeathKnight-Blood','Paladin-Protection','Evoker-Preservation','Priest-Holy','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Warrior-Arms','Hunter-Survival','Shaman-Elemental','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration',}
local provider = {region='US',realm='DemonSoul',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaphrodite:BAAANQADCgMIAwAAAA==.',
Ab='Abyssalblink:BAACNQAFFH8bAAMBAAcKThYJAwBfAgABAAcKThYJAwBfAgACAAMKARB0DgC7AAA1AAQKfycAAwIACgqGILAdAGQCAAIACQr1G7AdAGQCAAEABQqPJI8dAKwBAAE1AAUUCQkrAAMA3RsA.',
Ah='Ahruud:BAAANQADCgMIAwAAAA==.',
Ak='Akeno:BAAANQADCgIIAgABNQAECgoKGAAEAOYUAA==.',
Al='Albie:BAABNQAECn8qAAIFAAoK0hPokgBaAgAFAAoK0hPokgBaAgAAAA==.Albtraum:BAAANQADCgMIAwAAAA==.Aleight:BAABNQAECn8cAAIGAAgKow0RhwD9AQAGAAgKow0RhwD9AQAAAA==.Alice:BAAANQADCgIIAgAAAA==.Alius:BAAANQAECgMICAAAAA==.',
Am='Ambellina:BAABNQAECn8yAAIHAAoKFxtBIwDfAgAHAAoKFxtBIwDfAgAAAA==.',
An='Anveendra:BAAANQAECgIIAwAAAA==.',
Ba='Bambiietta:BAAANQAECgQIBgAAAA==.',
Be='Belanwolf:BAAANQADCgIIAgAAAA==.',
Bl='Blastoiz:BAAANQADCgYIBgAAAA==.',
Br='Branyo:BAAANQAECgQIBAAAAA==.',
Bu='Bulvar:BAAANQAECggIBgAAAA==.',
Ca='Caligos:BAAANQADCgQIBAAAAA==.Camilacream:BAAANQAECgEIAQAAAA==.Capriestson:BAAANQAECgEIAQAAAA==.Cardrin:BAABNQAECn8kAAIIAAoKNRYOEABfAgAIAAoKNRYOEABfAgAAAA==.',
Ce='Cerbulum:BAAANQADCgMIAwAAAA==.',
Ch='Chalupa:BAAANQAECggIAgAAAA==.Chat:BAAANQADCgMIAwAAAA==.Choplo:BAACNQAFFH8dAAIDAAgKVRljAgBjAgADAAgKVRljAgBjAgA1AAQKfxwAAgMACgrrIMUZAHQCAAMACgrrIMUZAHQCAAAA.Chudmuffin:BAABNQAECn8cAAIFAAkKZQzCsQDjAAAFAAkKZQzCsQDjAAAAAA==.',
Ci='Cinema:BAABNQAECn8ZAAMFAAkK1yH0gwB2AgAFAAkKzyH0gwB2AgAJAAEK2CRyOwBSAAAAAA==.',
Cl='Clarence:BAAANQADCgIIAgAAAA==.Closetotoast:BAAANQADCgMIAwAAAA==.',
Co='Cobalt:BAAANQAECgMJAwABNQAFFAYICgAKAHsRAA==.',
Cr='Creativename:BAAANQABCgUIBQAAAA==.Crona:BAAANQADCgIIAgAAAA==.',
Da='Daemon:BAABNQAECn8aAAQLAAkKBh+WCABzAgALAAkKkhmWCABzAgAKAAUKYSA+swBpAQAMAAEKVx8KKwBBAAAAAA==.Dalast:BAAANQAECgEIAQAAAA==.',
De='Debockulus:BAABNQAECn9OAAMKAAoKURuJGgBgAgAKAAoKURuJGgBgAgALAAUKfQWePgDIAAAAAA==.Decentychi:BAABNQAECn8cAAIDAAgKdh6ICwBAAgADAAgKdh6ICwBAAgAAAA==.Dedia:BAAANQAECgEIAQAAAA==.Derangedxo:BAACNQAFFH8bAAQKAAkKuR5SBAB+AQAKAAgK6h9SBAB+AQAMAAEKkhfFBwBkAAALAAEKhBhtGwBPAAA1AAQKfyoAAwoACgpwJnkAAIsDAAoACgppJnkAAIsDAAsABwrvICwJAGcCAAAA.',
Do='Doggie:BAAANQADCgMIAwAAAA==.',
Dr='Dreambreath:BAAANQAECgMIBQAAAA==.Droppi:BAAANQADCggICAAAAA==.Drunkenhoe:BAABNQAECn8dAAINAAkK8QdkkwArAQANAAkK8QdkkwArAQAAAA==.',
Ea='Earthwalkin:BAAANQAECgEIAQAAAA==.',
Ed='Edger:BAAANQADCgMIAwAAAA==.',
El='Elcomer:BAAANQADCgIIAgAAAA==.',
En='Enana:BAABNQAECn8WAAIOAAgKMQl0jQBnAQAOAAgKMQl0jQBnAQAAAA==.Enkor:BAAANQAECggIDwAAAA==.',
Er='Era:BAABNQAECn8ZAAIMAAcKwhM8CgDWAQAMAAcKwhM8CgDWAQABNQADCgMIAwAPAAAAAA==.',
Ev='Everblack:BAABNQAECn8zAAQLAAoKwh1KBwCSAgALAAgK0B5KBwCSAgAKAAgKZQ83jwDAAQAMAAMKSiGgGADFAAAAAA==.Evilcretin:BAACNQAFFH8EAAIFAAIKGCENHQDGAAAFAAIKGCENHQDGAAA1AAQKf4wABAUACgqvJrAAAIMDAAUACgqvJrAAAIMDAAkAAgqwI0MjANIAABAAAgpYIBEKAGIAAAAA.',
Fa='Faraah:BAABNQAECn9HAAMRAAoKiiTuAADYAwARAAoKiiTuAADYAwAIAAEKMRngQgBYAAAAAA==.',
Ga='Ganondorf:BAABNQAECn8iAAISAAgKjxWZRwDaAQASAAgKjxWZRwDaAQAAAA==.Gatecrashr:BAAANQAECgIIAgAAAA==.',
Gi='Gimlï:BAAANQADCgYICgAAAA==.',
Gl='Gluttony:BAAANQAECgcICgABNQAECgoKJgAEACMSAA==.',
Gn='Gnosis:BAAANQADCggIFgAAAA==.',
Go='Goch:BAABNQAECn8WAAMTAAcKCRCDNgA0AQANAAcKuw9S1ABzAQATAAcKzwyDNgA0AQAAAA==.Gochalufagus:BAAANQADCgIIAgAAAA==.Goldenwind:BAAANQAECggIBAAAAA==.Goodluck:BAAANQADCgMIAwABNQAFFAYIFQAUAOIXAA==.',
Gp='Gp:BAAANQAECgEIAQAAAA==.',
Gr='Grimdark:BAABNQAECn8rAAIOAAoKxRLrbwC7AQAOAAoKxRLrbwC7AQAAAA==.Grunge:BAABNQAFFH8GAAIKAAQKlwqOEADMAAAKAAQKlwqOEADMAAAAAA==.',
Ha='Haven:BAAANQAECgEIAQAAAA==.',
He='Heathermarie:BAABNQAECn8yAAIQAAgKSiTTAAAnAwAQAAgKSiTTAAAnAwAAAA==.',
Hi='Hinata:BAAANQAECgMIAwAAAA==.Hippojaxx:BAAANQAECggICAAAAA==.',
Ho='Holdmyhammer:BAAANQADCgMIAwAAAA==.Holypride:BAAANQADCgUIBQABNQAECgoKJgAEACMSAA==.Hotbut:BAABNQAECn8tAAIVAAoKfB4fFADFAgAVAAoKfB4fFADFAgAAAA==.',
['Hø']='Hørus:BAAANQADCgcIBwAAAA==.',
Ia='Iaptopz:BAAANQADCgcIDQAAAA==.',
Ir='Irishbaby:BAAANQAECgEJAgAAAA==.',
Iz='Iza:BAABNQAECn8mAAIOAAgKkBDMdQCqAQAOAAgKkBDMdQCqAQAAAA==.Izis:BAAANQAECgIIAQAAAA==.',
Ja='Jake:BAEANQAECgMIBgABNQAFFAgIGwAFABAVAA==.',
Je='Jeisansan:BAAANQAECgcIBwAAAA==.',
Ju='Juri:BAAANQAFFAEIAQAAAA==.',
Ka='Kads:BAAANQAECgUIAgABNQAFFAgIBgAWAEUmAA==.Kallivor:BAAANQAECggIEAAAAA==.Kanbu:BAAANQADCgEIAQAAAA==.Kardd:BAABNQAECn8mAAQSAAoKqx7iBwDUAgASAAkKqx7iBwDUAgAXAAcKQxelWwChAQAYAAIKZwbbnQBVAAAAAA==.',
Ke='Keeburn:BAAANQABCgEIAQAAAA==.Keltic:BAABNQAECn8WAAMVAAkKBRBORgCYAQAVAAkKBRBORgCYAQAZAAIK5wACmAAHAAAAAA==.',
Kh='Khantyer:BAAANQADCgYIAwAAAA==.',
Ki='Kigafan:BAAANQAECggIBwAAAA==.Kiing:BAAANQADCgUIBQAAAA==.',
Kr='Krow:BAAANQADCgIIAgAAAA==.Krowlhy:BAAANQAECgIIAgAAAA==.',
La='Laezel:BAABNQAECn8qAAIaAAkKKBwVQQDLAQAaAAkKKBwVQQDLAQAAAA==.Lamppost:BAACNQAFFH8HAAIbAAMKxyNZAAAhAQAbAAMKxyNZAAAhAQA1AAQKfywAAhsACgpeJkkAANsDABsACgpeJkkAANsDAAAA.Landliebe:BAAANQADCggILwAAAA==.Lannister:BAAANQADCgUIBQABNQAECgoKLAAUACwVAA==.',
Le='Lereios:BAAANQAECgYIDgABNQAECgkJFAAKAFoOAA==.Lessons:BAAANQADCgEIAQAAAA==.',
Li='Lightsmith:BAAANQAECgQIBQAAAA==.Lilpump:BAAANQAECgYIBwABNQAECggIDwAPAAAAAA==.Lith:BAACNQAFFH8OAAIBAAUKiBvVBQAZAQABAAUKiBvVBQAZAQA1AAQKfzIAAwEACgoCI7MDAC8DAAEACgoCI7MDAC8DAAIAAQoAAMd0ACUAAAAA.Liyun:BAAANQAECgIIAgAAAA==.',
['Lø']='Løry:BAAANQAFFAIIAwABNQAFFAYICwAHABcQAA==.',
Ma='Mahyor:BAABNQAECn8dAAMOAAgKTxQ8XwDxAQAOAAgKTxQ8XwDxAQAcAAYK1xpXgwCcAQAAAA==.Maroonfive:BAAANQAECgcICQABNQAFFAUIBwAcAFMJAA==.Maybringer:BAAANQADCgQIBAAAAA==.Mazzmerize:BAACNQAFFH8XAAMdAAcK1yE6AwCEAQAdAAcKox86AwCEAQAGAAMKHCUVHABqAAA1AAQKfx8AAx0ACQrIH50bAHcCAB0ACQpEGp0bAHcCAAYABgqXDpbvACIBAAE1AAUUCgpBAAUA2iIA.',
Mi='Miramitotem:BAAANQAECgUIBQAAAA==.',
Mu='Murmurr:BAAANQAECgEIAQAAAA==.',
Na='Naric:BAABNQAECn8UAAQKAAkKWg7sbQAVAgAKAAkKWg7sbQAVAgAMAAIK6hRNHgCJAAALAAEKAACydwA2AAAAAA==.Nasa:BAAANQAECgMIAwAAAA==.',
No='Nobru:BAAANQAECgQICAAAAA==.Now:BAABNQAECn8vAAMcAAoKpxgmHwADAgAcAAoKpxgmHwADAgAOAAEKIwTfMAEfAAAAAA==.',
Nu='Nukenin:BAABNQAECn8vAAICAAoKHCV9BACNAwACAAoKHCV9BACNAwAAAA==.Nunquam:BAAANQAECgMIAwAAAA==.',
Ny='Nyrasha:BAACNQAFFH8KAAIGAAUKWxGMBQBFAQAGAAUKWxGMBQBFAQA1AAQKfzAAAgYACgqOIT4cACcDAAYACgqOIT4cACcDAAAA.',
Pa='Paredes:BAAANQAECgQIAwAAAA==.',
Pe='Peonu:BAABNQAECn8bAAMeAAkK7golTwCCAQAeAAkK7golTwCCAQAfAAQKJwdmPQDNAAAAAA==.',
Po='Police:BAABNQAECn8rAAMOAAoKwR/hFQAhAwAOAAoKwR/hFQAhAwAcAAUK6hfZhgCTAQAAAA==.',
Pr='Pride:BAABNQAECn8mAAIEAAoKIxITDgCLAgAEAAoKIxITDgCLAgAAAA==.Prophesy:BAAANQAECgIIAgAAAA==.Proteus:BAABNQAECn8dAAMYAAkKkwkzMQBgAQAYAAkKPAkzMQBgAQAXAAMKxgYQbgA0AAAAAA==.',
Pu='Puff:BAABNQAECn8YAAIFAAcKiRAX8QCoAQAFAAcKiRAX8QCoAQAAAA==.',
Ra='Rana:BAAANQAECgcIEAAAAA==.Ratko:BAAANQADCggIDwAAAA==.',
Re='Rekk:BAAANQAECggICAAAAA==.Reventön:BAAANQADCgcIBgAAAA==.Rey:BAAANQAECgUIDgABNQAECgoKJgAGAOkfAA==.',
Rh='Rhaevness:BAAANQAECgUIBQAAAA==.',
Ro='Rockandstone:BAABNQAECn8cAAMOAAoK9BqtNwCAAgAOAAoK9BqtNwCAAgAcAAEKAAA1TgEnAAAAAA==.',
Ru='Rubyredyoshi:BAAANQAECgYIBgAAAA==.Runtzsr:BAAANQABCgQIBQAAAA==.',
['Rá']='Ráîstlin:BAABNQAECn8pAAMJAAoKAxJvEQCPAQAFAAgKfglm6gC1AQAJAAcKRRVvEQCPAQAAAA==.',
Sa='Sanguinary:BAAANQABCgQIAgAAAA==.Savagecow:BAAANQAECgMIAwAAAA==.',
Se='Selro:BAAANQAECgUIBgAAAA==.',
Sh='Shadøw:BAAANQAECgQIBQAAAA==.Shinoa:BAAANQAECgIIAQAAAA==.Shockzzer:BAAANQADCgMIAwAAAA==.',
Sk='Skyvoh:BAAANQAECgMIBAAAAA==.',
So='Soulszaura:BAAANQAECgQIBAAAAA==.',
St='Starchucker:BAACNQAFFH8RAAICAAYK+hWgBwCOAQACAAYK+hWgBwCOAQA1AAQKf0QAAgIACgo9IbYGAGcDAAIACgo9IbYGAGcDAAAA.',
Sw='Swade:BAAANQADCgQIBAABNQADCgYIBgAPAAAAAA==.Sweetnwicked:BAABNQAECn8XAAMLAAcKJQpkQADBAAAKAAYK9AgC1QAgAQALAAQKcgpkQADBAAAAAA==.',
Sy='Synarri:BAABNQAECn8YAAMNAAkK8hMwkAAEAgANAAgK8hQwkAAEAgAHAAcKdRZ1XQAAAgABNQAFFAgIHQAHAEgZAA==.Syneria:BAACNQAFFH8dAAMHAAgKSBlSAQC3AgAHAAgKSBlSAQC3AgANAAIKkxWgNABCAAA1AAQKf9sAAwcACgp5JW8AAPUDAAcACgp5JW8AAPUDAA0ACgq+I6gQAPICAAAA.Syneriah:BAAANQAECgEIAQABNQAFFAgIHQAHAEgZAA==.Synn:BAAANQADCggICAABNQAFFAgIHQAHAEgZAA==.Synnamon:BAABNQAECn9YAAMNAAoKQCZXAgDtAwANAAoKQCZXAgDtAwAHAAYK/QipsgAZAQABNQAFFAgIHQAHAEgZAA==.Synpai:BAACNQAFFH8NAAMHAAYKjwxzCQDJAQAHAAYKjwxzCQDJAQANAAEKUgtRNwA9AAA1AAQKf1wAAw0ACgoDJMwRAOoCAA0ACgoDJMwRAOoCAAcABwoHHbdcAAICAAE1AAUUCAgdAAcASBkA.',
Ta='Taciitus:BAABNQAECn8pAAIDAAkKWx3zFQChAgADAAkKWx3zFQChAgAAAA==.Tailzz:BAABNQAECn8fAAIdAAcKvwbiHAAYAQAdAAcKvwbiHAAYAQAAAA==.',
Th='Thebaptiser:BAAANQADCgUIBQAAAA==.Thuggjr:BAAANQAECgMIAwABNQAFFAgIHQADAFUZAA==.Thunderwar:BAAANQADCgQICgAAAA==.Thunderwings:BAAANQADCgIIAgAAAA==.',
Ti='Tiazy:BAAANQADCgYICAAAAA==.',
To='Toomato:BAAANQAECgUICAAAAA==.Totemterror:BAEBNQAECn8cAAIOAAoKDCWWAwCwAwAOAAoKDCWWAwCwAwAAAA==.Tough:BAAANQADCgQIBAAAAA==.',
Ty='Tydraduel:BAACNQAFFH8IAAIKAAMKbg6JEADMAAAKAAMKbg6JEADMAAA1AAQKfzYAAgoACgrGHTITAI8CAAoACgrGHTITAI8CAAAA.',
Tz='Tzuruchanise:BAAANQADCgMIBAAAAA==.',
Va='Vala:BAAANQAECgEIAQABNQAECgoKLAAUACwVAA==.Valy:BAAANQAECgYIDwAAAA==.Vannathyfall:BAAANQAECgEIAQAAAA==.Vany:BAAANQAECgEIAQAAAA==.',
Vo='Vora:BAAANQAECgYIEAAAAA==.',
Vw='Vw:BAAANQAECgIIAgAAAA==.',
Wh='Whalethen:BAEANQAECgcICAABNQAECgoKHAAOAAwlAA==.Wheresdebeef:BAAANQADCggIBAABNQAECgYIBwAPAAAAAA==.',
Wi='Wikkid:BAAANQADCgUJBwAAAA==.Wikkidsin:BAAANQADCgUICAABNQADCgUJBwAPAAAAAA==.',
['Wù']='Wùlph:BAAANQAECgQIBAAAAA==.',
Xx='Xxz:BAAANQADCgUIBwAAAA==.',
Yi='Yiesus:BAAANQAECggIDwABNQAFFAcIGgACALImAA==.',
Yo='Yomato:BAABNQAECn82AAIgAAoKeh2nDQD1AgAgAAoKeh2nDQD1AgAAAA==.',
Yu='Yuanti:BAAANQADCgIIAgAAAA==.',
Za='Zabble:BAAANQAECgQIBAAAAA==.',
Ze='Zenocline:BAABNQAECn8pAAIDAAoKmxVVFACjAQADAAoKmxVVFACjAQAAAA==.',
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
