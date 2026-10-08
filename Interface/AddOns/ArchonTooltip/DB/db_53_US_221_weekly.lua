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

local lookup = {'Druid-Restoration','Warrior-Protection','Unknown-Unknown','Druid-Guardian','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Rogue-Assassination','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Evoker-Preservation','Warlock-Affliction','Priest-Shadow','DeathKnight-Blood','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Devastation','Mage-Frost','Warrior-Fury','Druid-Balance','Shaman-Enhancement','Monk-Mistweaver','Rogue-Outlaw','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Priest-Discipline',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaliyah:BAABNQAECoEqAAIBAAkKqhuPDQDaAgABAAkKqhuPDQDaAgAAAA==.',
Ab='Aboxofchips:BAAANQAECggIBwAAAA==.Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQAECgUICwAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQAECgUICQABNQAECggIJgACAIEeAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgQIDQADAAAAAA==.Aeliniani:BAAANQAECgEIAQAAAA==.',
Ag='Aggressor:BAAANQADCgMIAwAAAA==.Aggrocrack:BAABNQAECoEeAAMEAAcKNB9sCwB5AgAEAAcKNB9sCwB5AgAFAAEKgwOiPAAlAAAAAA==.Agliam:BAAANQAECgEJAgAAAA==.',
Ah='Ahngus:BAABNQAECoEaAAICAAcKZxzgDAA6AgACAAcKZxzgDAA6AgAAAA==.',
Ai='Air:BAAANQAECgYIEgAAAA==.',
Al='Alakander:BAAANQAECgMIBgAAAA==.Alexcrowley:BAAANQADCgYICwAAAA==.Alexdh:BAAANQAECgEIAQABNQAFFAcIDwAGABEhAA==.Alexdk:BAAANQADCgMIAwABNQAFFAcIDwAGABEhAA==.Alexdruids:BAAANQAECgUIBQABNQAFFAcIDwAGABEhAA==.Alexhunt:BAACNQAFFIEPAAQGAAcKESGWAwAGAgAGAAUKdiSWAwAGAgAHAAMKYw6YEgDdAAAIAAEKLCDFAQBgAAA1AAQKgSMABAYACQpTI2YuAMACAAYACAooI2YuAMACAAcABwrSHvUfADICAAgAAQr8IHAPAFkAAAAA.Alexpaladin:BAAANQAECgUIBQABNQAFFAcIDwAGABEhAA==.Alplarn:BAAANQAECgQIBgAAAA==.Althsar:BAAANQADCgEIAQAAAA==.Alucardias:BAAANQADCgYIBgAAAA==.',
Am='Amanarra:BAAANQADCgQIBAAAAA==.Amorlorisy:BAAANQADCggICAABNQAECgQIBwADAAAAAA==.',
An='Anitwa:BAABNQAECoEgAAMJAAgKmB86IQCkAgAJAAgKmB86IQCkAgAKAAEKFRTHjgA8AAAAAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgMIBgAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAABNQAECoEnAAIGAAkK6xXfRgBxAgAGAAkK6xXfRgBxAgAAAA==.Aranina:BAAANQAECgUIDQAAAA==.Arcami:BAAANQADCgIIAgAAAA==.Arcanedria:BAAANQABCgYIBgAAAA==.Arcanz:BAAANQAECgEIAQAAAA==.Arcturrus:BAAANQAECgQIBAAAAA==.Arel:BAABNQAECoEcAAMLAAgKJSE/HADuAgALAAgKJSE/HADuAgAMAAEK7CDhTQFhAAAAAA==.Arkanis:BAAANQADCgcIFgAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arowid:BAAANQADCgYIGgAAAA==.Arrwyn:BAAANQAECgYICgABNQAECggIFwACABAmAA==.Arter:BAAANQAECgEIAQABNQAECggIJQANAG0VAA==.Aryhm:BAAANQAECgYICgAAAA==.',
As='Asatralth:BAAANQAECgYIDAAAAA==.Asguard:BAAANQAECgEIAQAAAA==.Asheryo:BAAANQADCgUIBQAAAA==.Assphyxiate:BAAANQAECgQICAAAAA==.Aszshara:BAAANQAECgMIBQAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAABNQAECoEaAAIEAAgKcBnsDQBHAgAEAAgKcBnsDQBHAgAAAA==.',
Ba='Babihotdog:BAAANQAECgMIBQAAAA==.Babylego:BAAANQAECgYIBgABNQAFFAcIFgANAMIfAA==.Badspec:BAAANQAECggIAQAAAA==.Badwolff:BAAANQAECgUIEQAAAA==.Baerog:BAAANQAECgUICwAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAACNQAFFIEFAAIOAAMKAAhuLwDdAAAOAAMKAAhuLwDdAAA1AAQKgSsAAg4ACQrAG7tKAN0CAA4ACQrAG7tKAN0CAAAA.Baodrubao:BAAANQAECgQIBAAAAA==.Barlake:BAAANQADCgUIBQAAAA==.Basicblends:BAAANQAECgQIBQAAAA==.',
Bb='Bblglizzy:BAAANQADCgEIAQAAAA==.',
Be='Beefglizzy:BAABNQAECoEXAAIJAAcKSyBGJQCKAgAJAAcKSyBGJQCKAgAAAA==.Beeftàllow:BAAANQADCgUJBQAAAA==.Beelzaboot:BAABNQAECoEiAAMPAAgKJhXQbQDtAQAPAAcKyBTQbQDtAQAQAAIKYQ+9VAB2AAAAAA==.Belanor:BAABNQAECoEmAAICAAgKgR7DBwC2AgACAAgKgR7DBwC2AgAAAA==.Benjangles:BAABNQAECoEXAAIOAAcKuAO6HgEzAQAOAAcKuAO6HgEzAQAAAA==.Berry:BAABNQAECoErAAIEAAkKLiTlAQCoAwAEAAkKLiTlAQCoAwAAAA==.Betrayer:BAAANQAECgMIBAABNQAECggIHQARAKweAA==.',
Bh='Bhogrenoc:BAAANQAECgQIBAAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECggIIAAJAJgfAA==.Bigdamfury:BAAANQAECgQIBQABNQAECgUIBwADAAAAAA==.Bignipsmcgee:BAAANQAECgQIBQAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgcICwAAAA==.Bitss:BAAANQADCgEIAQABNQAECggIHgAEADQfAA==.',
Bl='Blacksam:BAAANQAECgQIBgAAAA==.Blacktastic:BAAANQAECgMJAwAAAA==.Bladebane:BAAANQADCgQIBAAAAA==.Blastee:BAABNQAECoEjAAIGAAgKQCJuIgDwAgAGAAgKQCJuIgDwAgAAAA==.Blath:BAAANQADCggIGAAAAA==.Blazius:BAAANQAECgQIBQAAAA==.Bleebles:BAAANQAECgQIBAABNQAECgYICAADAAAAAA==.Blinkinpark:BAAANQADCgEIAQAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.Bloodlego:BAABNQAECoEVAAIKAAcKRSPpEwDMAgAKAAcKRSPpEwDMAgABNQAFFAcIFgANAMIfAA==.',
Bo='Bobertl:BAAANQAECgUICAAAAA==.Bolter:BAAANQAECgEIAgAAAA==.Boomnecrotic:BAABNQAECoEaAAIJAAcK0hhaPwD7AQAJAAcK0hhaPwD7AQAAAA==.Boonney:BAAANQADCgYIBgAAAA==.Bopgun:BAAANQADCgMIBAAAAA==.Bottlewater:BAAANQADCgEIAQAAAA==.',
Br='Braine:BAAANQADCgMIBAAAAA==.Breathboy:BAAANQAECgQICgAAAA==.Bronder:BAAANQADCgYIEAAAAA==.Bronzehoofs:BAAANQADCggIEQAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Buffchadwell:BAAANQADCgUIBQAAAA==.Bulletbill:BAAANQADCgUIBQAAAA==.Bullwinklee:BAAANQADCgUIBQAAAA==.Burghmaul:BAAANQAECgUIEgAAAA==.',
Ca='Cadwallader:BAAANQABCgIIAgAAAA==.Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgIIAwAAAA==.Candykate:BAAANQADCgIIAgAAAA==.Canon:BAAANQAECgYIEAAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Ceevee:BAAANQAECgIIAgAAAA==.Celasong:BAAANQAECgEIAQAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Celtïc:BAAANQADCgQICwAAAA==.Celydrea:BAAANQAECgUIEAAAAA==.Ceree:BAABNQAECoElAAIMAAgKag13mgC3AQAMAAgKag13mgC3AQAAAA==.',
Ch='Cherryfox:BAAANQADCgYIBgAAAA==.Chimeranzomb:BAAANQADCgQJBAAAAA==.Chippedbeef:BAAANQAECgQIDAAAAA==.Chiwi:BAAANQADCggICAAAAA==.Chocogeta:BAABNQAECoEZAAISAAgKOg/PLAD/AQASAAgKOg/PLAD/AQAAAA==.Chubbsmcgee:BAAANQAECgEIAQAAAA==.Chucknourysh:BAAANQADCgIIAgAAAA==.Chì:BAAANQAECgQIBQAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQAECgEIAQAAAA==.Cladow:BAABNQAECoEfAAMTAAkKayKYDQBvAwATAAkKayKYDQBvAwAUAAIK3hp15AByAAAAAA==.Clag:BAAANQAECgUIBgAAAA==.',
Co='Cogblock:BAABNQAECoEjAAINAAcK1hi2cQAeAgANAAcK1hi2cQAeAgAAAA==.Coldsteak:BAAANQADCggIDgAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cp='Cpwolf:BAAANQADCgYJBwAAAA==.',
Cr='Crappen:BAAANQADCgMIAwAAAA==.Crimsonbull:BAAANQADCggICAABNQAECgkJKgAPAJwhAA==.Cronosphere:BAAANQADCgcIEAAAAA==.Cruelerr:BAAANQADCgQIBAABNQAECgYIEQADAAAAAA==.Crushaturty:BAAANQAECgMIAgAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQADCgEIAQAAAA==.Cyndrin:BAABNQAECoEcAAMGAAkKLxxaMgCzAgAGAAgKqB1aMgCzAgAHAAIK+QtkZAByAAAAAA==.',
Da='Daddyfatsaks:BAAANQADCgEIAgAAAA==.Daddyglock:BAAANQAECgUIBwAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAADAAAAAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAACNQAFFIEWAAINAAcKwh8VAgC4AgANAAcKwh8VAgC4AgA1AAQKgSoAAg0ACQo3JlkFAMYDAA0ACQo3JlkFAMYDAAAA.Darknite:BAAANQAECgYICQABNQAECggIFwACABAmAA==.Darksign:BAAANQADCgIIAgAAAA==.Dathundir:BAAANQAECggIDgABNQAECgkJJgAMAKYcAA==.Davemage:BAAANQAECgUIDwAAAA==.Davidpaine:BAAANQAECgUICgABNQAECgcIDAADAAAAAA==.Dawnhorn:BAAANQADCgQIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBwAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Deepd:BAAANQAECggICwAAAA==.Deepyram:BAAANQADCgEIAQAAAA==.Delillama:BAABNQAECoEkAAMMAAgKjhe+cgAaAgAMAAgKjhe+cgAaAgAVAAIKDxWVTwB5AAAAAA==.Demolior:BAAANQABCgEIAQAAAA==.Denken:BAAANQADCgUIBQABNQAECgMIBgADAAAAAA==.Destnny:BAAANQAECgYIEAAAAA==.Destrohunter:BAAANQADCggIDgAAAA==.Destroker:BAABNQAECoEbAAIWAAcKkg4gIwCNAQAWAAcKkg4gIwCNAQAAAA==.Dewax:BAAANQAECgMIAwAAAA==.Deylight:BAAANQADCgYIDAAAAA==.',
Dh='Dhalla:BAAANQADCggICAABNQAECgYICQADAAAAAA==.Dhspudd:BAAANQADCgYIBgABNQAECgYIFAANAOIQAA==.',
Di='Dillpo:BAAANQABCgUIBwAAAA==.Dioress:BAAANQAECgQIBgAAAA==.Dis:BAABNQAECoEiAAIXAAgKMSKSAQAcAwAXAAgKMSKSAQAcAwABNQAFFAcIEgATALEcAA==.Distear:BAAANQAECgIIAwAAAA==.Disyx:BAAANQAECgcIEQAAAA==.Diyanå:BAABNQAECoEpAAIGAAgKoBdnTwBZAgAGAAgKoBdnTwBZAgAAAA==.',
Do='Domainz:BAAANQAECgYIDAAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donalan:BAAANQAECgEIAQAAAA==.Donzm:BAAANQADCgYIBgABNQAFFAQICQAXALMKAA==.Donzw:BAACNQAFFIEJAAQXAAQKswqOCwBIAAAPAAIKcwoXLACOAAAXAAEKkxGOCwBIAAAQAAEKUASgHgBHAAA1AAQKgSIABBcACQpVFo8MAG4BAA8ACQrXFHtYACwCABcABwpNEo8MAG4BABAABAo9BrBAALYAAAAA.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQAECgcIEgAAAA==.Dragonbender:BAEANQAECgIIAgAAAA==.Dragun:BAAANQADCgIIAgAAAA==.Draxxor:BAAANQAECgEJAQAAAA==.Dreamender:BAAANQAECggJBQABNQAECggICgADAAAAAA==.Drfrash:BAAANQADCgYIBgAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAAANQAECgcIEwAAAA==.Drumin:BAABNQAECoEXAAMTAAcKvh3WOwBeAgATAAcKvh3WOwBeAgAUAAIK3xUA4gB4AAAAAA==.',
Du='Dudewithpets:BAAANQADCgUIBQAAAA==.Durahar:BAAANQAECgcIEgAAAA==.',
Dw='Dwarvanhand:BAACNQAFFIEXAAMYAAcKYRY/BADeAQAYAAUKrxo/BADeAQARAAQKBxFWEgBDAQA1AAQKgSoAAxgACQohI58HAFADABgACQohI58HAFADABEAAgoyEtPHAIkAAAAA.',
['Dá']='Dáin:BAAANQAECgMIBQABNQAECgcIEQADAAAAAA==.',
['Dâ']='Dâwn:BAABNQAECoEXAAMMAAgKyBmHYQBJAgAMAAgKyBmHYQBJAgAVAAYKHweNPQDdAAAAAA==.',
['Dã']='Dãwn:BAAANQAECggIBgAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQAECgcIDwABNQAECgkJIQAZACUfAA==.Earthrender:BAAANQADCgUIBgAAAA==.Eatmacookie:BAAANQADCgYIEQAAAA==.',
El='Elazar:BAAANQAECgYICAAAAA==.Elderian:BAABNQAECoErAAIaAAkKNiZRAQDjAwAaAAkKNiZRAQDjAwAAAA==.Elemenope:BAAANQAECgYICQAAAA==.Elementhol:BAAANQADCgYIBgAAAA==.Elemitchard:BAAANQAECgUICgAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAABNQAFFIEHAAMbAAQKpRU/CgABAQAbAAMKKhI/CgABAQASAAEKFyAeFQBgAAAAAA==.Elitegamerx:BAAANQAECgYIBgABNQAECgcIEQADAAAAAA==.Elpadrino:BAAANQADCgcICgAAAA==.Elunaryn:BAAANQAECggJAQAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emerys:BAAANQAECgIIAgAAAA==.Emitlyght:BAAANQADCggIFQAAAA==.Emmabeth:BAAANQADCgMJAwAAAA==.',
En='Eniri:BAAANQAECgMIBgAAAA==.Enyeto:BAABNQAECoElAAMNAAgKbRVPfAACAgANAAgK8xRPfAACAgACAAEKUg2LOwAxAAAAAA==.',
Er='Ermaghaku:BAAANQAECgIIAgAAAA==.Erodras:BAAANQADCgIIAgAAAA==.Erojin:BAAANQADCgYIBgAAAA==.Eroviaevia:BAAANQAECgUICQAAAA==.',
Es='Esterossa:BAAANQADCgYICwAAAA==.',
Et='Etard:BAAANQADCgMIAwAAAA==.',
Eu='Eunomia:BAABNQAECoEcAAIHAAcK/xT4LgCtAQAHAAcK/xT4LgCtAQAAAA==.',
Ev='Evilest:BAAANQAECgEIAQAAAA==.',
Ex='Excuse:BAAANQAFFAEIAQABNQAECgkJJQAOAJkdAA==.Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAAANQAECgcIDgAAAA==.Ezoghoul:BAABNQAECoEbAAINAAgKgxTfegAFAgANAAgKgxTfegAFAgAAAA==.',
Fa='Faeare:BAAANQADCgYJDAAAAA==.Faene:BAAANQADCgQIBAAAAA==.Faerion:BAAANQAECgEIAQABNQAECggIJgAUAOojAA==.Fakedemon:BAEANQADCgIIAgABNQAECgYIDAADAAAAAA==.Fakelock:BAEANQADCgMIAwABNQAECgYIDAADAAAAAA==.Fakendruid:BAEANQAECgYIDAAAAA==.Fakewar:BAEANQADCgYIDAABNQAECgYIDAADAAAAAA==.Fauxx:BAAANQAECgYIBgAAAA==.Fayanor:BAAANQADCggICAAAAA==.',
Fd='Fdup:BAAANQAECgMJBAAAAA==.',
Fe='Felfae:BAAANQAECgIIAwAAAA==.Feverish:BAABNQAECoEfAAISAAkK0wwJKQAYAgASAAkK0wwJKQAYAgAAAA==.',
Fi='Filip:BAAANQAECgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCggJFAAAAA==.Florellia:BAAANQADCgQIBAAAAA==.Flumpy:BAABNQAECoExAAIGAAkKpSM3CwByAwAGAAkKpSM3CwByAwAAAA==.Flurpymcdoof:BAAANQAECgcIBwAAAA==.',
Fo='Folken:BAABNQAECoEbAAIFAAgKsQxBEQC4AQAFAAgKsQxBEQC4AQAAAA==.Foodtruck:BAAANQAECgMIAwABNQAECgcIGAAcAIwWAA==.Forbiddyn:BAAANQAECgcIEAAAAA==.Fornacater:BAAANQADCgcIBwAAAA==.Foxiefoxy:BAAANQAECgQIBwAAAA==.',
Fr='Fraiser:BAAANQADCgYICgABNQAECggIJQANAG0VAA==.Frankzappah:BAAANQABCgIIAgAAAA==.Freylyn:BAAANQADCgUIBQAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funkweave:BAEANQAECgcIEwAAAA==.Fupacabras:BAABNQAECoEUAAITAAgKowdolABBAQATAAgKowdolABBAQAAAA==.Furidas:BAAANQAECgYIDgAAAA==.Fuse:BAAANQABCgIIAgAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Gaius:BAAANQABCgIIAgAAAA==.Gangreenanus:BAAANQADCgYICgAAAA==.Garogg:BAABNQAECoEhAAICAAgK0BLOFACtAQACAAgK0BLOFACtAQAAAA==.Garotomoreno:BAABNQAECoEnAAIMAAkK1xxqPwCyAgAMAAkK1xxqPwCyAgAAAA==.Garrut:BAABNQAECoEgAAMEAAgKryDyBgDsAgAEAAgKryDyBgDsAgAFAAQKPgvxIQDRAAAAAA==.Gaymr:BAAANQADCgIIAgAAAA==.',
Ge='Geraldine:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.',
Gi='Gigagrog:BAAANQAECgQIBQAAAA==.Giirthquakee:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.Gimick:BAAANQADCggIDQABNQAECgcIHAAOAAgZAA==.Gimmage:BAABNQAECoEcAAMOAAcKCBncyQDNAQAOAAYKexncyQDNAQAdAAIKqxWAKgB9AAAAAA==.Gingebsham:BAAANQADCgcIBwABNQAECggIGgARANoJAA==.Girlyouthicc:BAAANQAECgYICgABNQAFFAcIFwAYAGEWAA==.Girthbrøøks:BAAANQADCgYIBgABNQAFFAMIAwADAAAAAA==.',
Gl='Gloiven:BAAANQAECgIIAgABNQAECgYICAADAAAAAA==.',
Go='Gojosatóru:BAAANQAECgQJCwAAAA==.Goldenchef:BAAANQAECgQIBAAAAA==.Gordatamara:BAAANQADCgEIAQAAAA==.Gordray:BAAANQAECgEIAQAAAA==.Gotcowbell:BAAANQAECgEIAQAAAA==.',
Gr='Grahnis:BAAANQAECgIIAgAAAA==.Grasswhistle:BAAANQAECgYIDAABNQAFFAMIBgAFAE4VAA==.Grayzor:BAAANQAECgUICQAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAABNQAECoEgAAIOAAcKmxAGxwDTAQAOAAcKmxAGxwDTAQAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAABNQAECoEaAAMNAAgKCBo2aQA1AgANAAgKCBo2aQA1AgAeAAEKYREnKwA9AAAAAA==.Grigdor:BAABNQAECoErAAMQAAkKuR2UFADBAQAPAAgKDB2DPACCAgAQAAYKVhuUFADBAQAAAA==.Grimnativex:BAAANQADCgIIAgAAAA==.Gràcias:BAAANQADCgYIBgAAAA==.',
Gu='Guass:BAABNQAECoEqAAMfAAkKcR/+EwASAwAfAAkKcR/+EwASAwABAAEKaQODbAAmAAAAAA==.Gumbyofgad:BAAANQAECgYIBgAAAA==.Gunbolt:BAAANQAECgMIBQAAAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgUIEQAAAA==.',
Ha='Habrosh:BAAANQAECgUIDwAAAA==.Hailrazor:BAAANQADCgIIAgAAAA==.Hairlock:BAAANQAECgUICgABNQAECggIHQARAKweAA==.Hakiry:BAABNQAECoEbAAIZAAcKUB2BLQBEAgAZAAcKUB2BLQBEAgAAAA==.Haliburton:BAAANQADCgMIAwAAAA==.Haramhabibi:BAAANQADCgYIBgAAAA==.Harike:BAAANQAECgEIAgAAAA==.Hatrix:BAAANQADCgYICQAAAA==.Haunt:BAAANQAECgYIDgAAAA==.Havokhuntr:BAAANQADCgQIBAAAAA==.Hawkkaye:BAAANQAECgQIBgAAAA==.Hawkwardfall:BAAANQADCgYICAAAAA==.Haze:BAAANQAECgEIAgAAAA==.Hazesamaa:BAABNQAECoE3AAIbAAkKphBuEgBKAgAbAAkKphBuEgBKAgAAAA==.',
He='Healsforfree:BAAANQADCgIJAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIJAgAAAA==.Hernog:BAABNQAECoEcAAITAAkKrBuXJQDOAgATAAkKrBuXJQDOAgAAAA==.Hexmenixy:BAAANQAECgYIEgAAAA==.',
Hi='Hianu:BAABNQAECoEYAAMXAAgKshZ/EAAbAQAPAAgKABFWbADyAQAXAAQK6xl/EAAbAQAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.Hildalock:BAAANQADCggICAABNQADCggIEAADAAAAAA==.',
Ho='Holabenjy:BAAANQAECgQIEQAAAA==.Holybenjy:BAAANQAECgMIBAAAAA==.Holybibble:BAAANQADCgIIBAAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQAECgUIBwAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQAECgMJAwAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holysponge:BAAANQAECgEIAQABNQAFFAUICAAOAEwQAA==.Holyzyn:BAAANQAECgEIAQAAAA==.Hoonding:BAAANQADCgcIFQABNQAECgkJNwAbAKYQAA==.Hordak:BAAANQAECgEIAQAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQAECgUIBwAAAA==.Hottodot:BAABNQAECoEaAAIRAAgK2gmJcQCQAQARAAgK2gmJcQCQAQAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAAANQAECgUIDwAAAA==.',
Hr='Hroptatyr:BAAANQADCgMIAwAAAA==.',
Hu='Hudini:BAABNQAECoE0AAIOAAkKWB0fQgDyAgAOAAkKWB0fQgDyAgAAAA==.Hugs:BAAANQAECgMJAwAAAA==.Huntsmang:BAAANQADCgEJAQAAAA==.Hushweaver:BAAANQADCgQICgAAAA==.',
Hy='Hybridkaidou:BAAANQADCgMIAwAAAA==.Hypal:BAAANQAECgcIEwABNQAECgcIDAADAAAAAA==.Hypd:BAAANQAECgcIDAAAAA==.Hypev:BAAANQAECggIEAABNQAECgcIDAADAAAAAA==.Hypm:BAAANQAECgQIBgABNQAECgcIDAADAAAAAA==.Hyps:BAABNQAECoEtAAMUAAkKHyFnHQDaAgAUAAkKHyFnHQDaAgATAAUKjg6yrAALAQABNQAECgcIDAADAAAAAA==.Hypt:BAABNQAECoEWAAMRAAkKQBHKTgAOAgARAAgKmxLKTgAOAgAYAAIKvwfHYQBRAAABNQAECgcIDAADAAAAAA==.',
Ia='Iakned:BAAANQAECgUICQABNQAECgcIDwADAAAAAA==.',
Ib='Ibichi:BAAANQADCgcIEQAAAA==.',
Ic='Icet:BAABNQAECoEnAAMbAAgKGBU6EwBAAgAbAAgKGBU6EwBAAgASAAQKsA7FXADzAAABNQADCggIDgADAAAAAA==.',
Il='Illshankya:BAAANQAECgIIAgAAAA==.',
Im='Imihn:BAAANQAECgUIBgAAAA==.',
In='Indàcouch:BAAANQABCgIIBAAAAA==.Invìctús:BAABNQAECoEZAAMdAAgKkBYLCQAXAgAdAAgKkBYLCQAXAgAOAAEKHAWBqgEyAAAAAA==.',
Io='Ionalafe:BAAANQADCgcIBwAAAA==.',
It='Ithir:BAAANQADCgcJDAAAAA==.Itsemma:BAAANQAECgYIEQAAAA==.',
Iu='Iustitia:BAAANQABCgYICwAAAA==.',
Iv='Ivieruem:BAAANQADCgUIDAAAAA==.',
Iy='Iylara:BAAANQAECgEIAQAAAA==.',
Iz='Izhira:BAAANQABCgMIAgAAAA==.',
Ja='Jaanus:BAAANQAECggICAAAAA==.Jackdalilguy:BAAANQADCgUIBQAAAA==.Jackodes:BAAANQAECgcIDQABNQAFFAMIBAAdAIITAA==.Jackodm:BAACNQAFFIEEAAMdAAMKghP3BQCeAAAdAAIK2xH3BQCeAAAOAAEKzxYJSwBXAAA1AAQKgSQAAw4ACQqoI4IhAEwDAA4ACQqoI4IhAEwDAB0AAwpJGUUcAOMAAAAA.Jad:BAABNQAECoEjAAIUAAgKbhnwNABmAgAUAAgKbhnwNABmAgAAAA==.Jamiepapo:BAAANQADCgIIAgAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCggIEwAAAA==.Jarlam:BAAANQABCgcIDwABNQAECggIHgAgALMXAA==.Jawa:BAAANQAECgEIAQABNQAECggIHgAeAKoNAA==.Jawo:BAABNQAECoEeAAIeAAgKqg2pDADKAQAeAAgKqg2pDADKAQAAAA==.',
Jb='Jboom:BAAANQAECgYICwABNQAECggIIAAJAJgfAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jersey:BAAANQADCgUIBQAAAA==.Jetts:BAABNQAECoEZAAIOAAgKVhYjmgAuAgAOAAgKVhYjmgAuAgAAAA==.',
Jf='Jfôrbj:BAAANQADCgQIBAABNQAECggIIAAJAJgfAA==.',
Jo='Johnnysinz:BAABNQAECoEjAAIMAAgKghvKSQCRAgAMAAgKghvKSQCRAgAAAA==.Johnnyzyns:BAABNQAECoEYAAITAAkKRRR/QwA8AgATAAkKRRR/QwA8AgABNQAFFAMIAwADAAAAAA==.Johnret:BAAANQAECgcIDAAAAA==.',
Jp='Jp:BAACNQAFFIEVAAIhAAYKcCZvAACdAgAhAAYKcCZvAACdAgA1AAQKgSAAAiEACQpyJtYAAMkDACEACQpyJtYAAMkDAAAA.',
Ju='Juhla:BAAANQADCgYICQAAAA==.Juno:BAAANQADCggIFwAAAA==.',
['Já']='Jáke:BAAANQAECgQIBAAAAA==.',
Ka='Kadester:BAAANQAECgEIAQAAAA==.Kaelwyn:BAAANQABCgIIAgAAAA==.Kaimen:BAAANQAECgYIDQAAAA==.Kainssoul:BAAANQADCgIIAgAAAA==.Kalipriest:BAAANQAECggIDgAAAA==.Kalipso:BAAANQAECgYIDgAAAA==.Kallea:BAAANQADCggICAAAAA==.Kalliz:BAAANQADCgYIDAAAAA==.Kamehameha:BAAANQAECgUICQAAAA==.Kamwar:BAACNQAFFIEJAAMeAAUKvxfdAABcAQAeAAQKZBndAABcAQANAAIKjgyeJwCPAAA1AAQKgSIAAx4ACQr3JXUAANEDAB4ACQrxJXUAANEDAA0AAwo/IC/nAOEAAAE1AAUUBwgaACIANyUA.Karideer:BAAANQAECgUIDgAAAA==.Karnaughm:BAAANQADCgUIAQAAAA==.Kataraxtis:BAAANQAECgQIBAAAAA==.Kaylax:BAAANQAECgUIDAAAAA==.Kaylost:BAAANQADCgMIBAAAAA==.Kaylub:BAABNQAECoEZAAIPAAgKdBI6YwAMAgAPAAgKdBI6YwAMAgAAAA==.Kazaland:BAAANQADCgEIAQAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQAECgcICwAAAA==.Kenott:BAAANQAECgIIAwAAAA==.Kenparcell:BAAANQAECgIIAwAAAA==.Kerash:BAAANQADCggIKwAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevindrd:BAAANQAECgUIBQABNQAECggIGQAVAKkWAA==.Kevintt:BAABNQAECoEZAAMVAAgKqRZFHQDUAQAVAAgKqRZFHQDUAQALAAQKugnxxwDDAAAAAA==.Keys:BAAANQAECgQICwAAAA==.',
Kh='Kho:BAAANQAECgUIDAAAAA==.Khodad:BAAANQAECgIIAgABNQAECgUIDAADAAAAAA==.Khreegz:BAAANQAECgEIAQAAAA==.Khundalar:BAAANQAECgUIBQAAAA==.',
Ki='Kiarraa:BAAANQAECgQIAwAAAA==.Killachefcjr:BAAANQADCgcIFQAAAA==.Kimi:BAAANQADCgYIBgAAAA==.Kimori:BAAANQADCgUIBQAAAA==.Kinzee:BAAANQAECgUIDAAAAA==.Kitana:BAAANQAECgQIBAAAAA==.Kittyvalk:BAAANQADCgQIBwAAAA==.',
Kn='Knugget:BAAANQAECgYICwAAAA==.',
Ko='Kodiakhunter:BAAANQAECgUICAAAAA==.Kodlighting:BAAANQAECgEIAQAAAA==.Kokurai:BAAANQAECgEIAQAAAA==.Komatsu:BAAANQADCgEIAQAAAA==.Koniqeo:BAAANQAECgMIAwAAAA==.Koressme:BAAANQADCggIEwAAAA==.Korlat:BAAANQAECgUICAAAAA==.Kozdiniar:BAABNQAECoEnAAMfAAkKcySRCwBgAwAfAAkKcySRCwBgAwABAAYKVyEsHAAoAgAAAA==.Kozurai:BAAANQAECgUIBQABNQAECgkJJwAfAHMkAA==.',
Kr='Kranlem:BAAANQAECgQIBAAAAA==.Krimzin:BAAANQAECgEIAQABNQAFFAUIDAAGADQVAA==.Kringles:BAAANQAECgYICAAAAA==.Kristree:BAAANQADCgUICgAAAA==.Krëegz:BAABNQAECoEdAAIGAAkKrhAIYgAoAgAGAAkKrhAIYgAoAgAAAA==.Krëëgz:BAAANQADCgEIAQABNQAECgkJHQAGAK4QAA==.',
Kt='Ktala:BAAANQAECgIIAwAAAA==.',
Ku='Kugot:BAAANQAECggICgAAAA==.Kurupted:BAAANQAECgYIEAAAAA==.',
Ky='Kydrea:BAAANQAECgQIBwAAAA==.Kyne:BAAANQAECgYICQAAAA==.Kynyselda:BAAANQAECgQJBAAAAA==.Kyrabear:BAAANQAECgQIBwAAAA==.',
['Kâ']='Kânê:BAABNQAECoEXAAIMAAcKLyAKZQA/AgAMAAcKLyAKZQA/AgAAAA==.',
La='Ladrón:BAAANQADCgYIDAAAAA==.Larayviana:BAAANQAECgEIAQAAAA==.Larc:BAAANQAECgQICgAAAA==.Larkos:BAAANQADCgcICgAAAA==.Lassamyna:BAAANQAECgEJAQAAAA==.Latías:BAABNQAECoEdAAIOAAkKFh38YACpAgAOAAkKFh38YACpAgAAAA==.',
Le='Leechygos:BAAANQADCggIFQAAAA==.Legenddairy:BAAANQAECgMIBwAAAA==.Legirlas:BAAANQADCgQIBAABNQAECgUICQADAAAAAA==.Leha:BAAANQAECgUIBQAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAABNQAECoEhAAIUAAgK2hhUOwBJAgAUAAgK2hhUOwBJAgAAAA==.Lenorand:BAAANQAECgQIBAABNQAECgQICQADAAAAAA==.Leushi:BAAANQADCgcIBwAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyarrows:BAAANQAECgcIDAABNQAECggIJwAaAGYaAA==.Lickmyhorns:BAABNQAECoEnAAMaAAgKZhptIgBhAgAaAAgKZhptIgBhAgAjAAYKkhDWOwA+AQAAAA==.Liendrah:BAECNQAFFIEKAAIkAAUK+RzQAACuAQAkAAUK+RzQAACuAQA1AAQKgSMAAiQACQr9IIcCADoDACQACQr9IIcCADoDAAAA.Lightbeer:BAAANQABCgMIBQAAAA==.Lightmf:BAAANQAECgcIEgAAAA==.Lightninglip:BAAANQADCgcIFQAAAA==.Lightnleaf:BAAANQAECgEIAQAAAA==.Lightorange:BAAANQAECgEIAgAAAA==.Lightwaves:BAAANQAECgUICwAAAA==.Lilet:BAABNQAECoEYAAMCAAgKqxOhEgDOAQACAAgKqxOhEgDOAQANAAEKCwNURgEfAAAAAA==.Lilfister:BAAANQADCgIIAgAAAA==.Lilitsune:BAAANQAECgUICQAAAA==.Linareyna:BAAANQADCgIIAgAAAA==.Lionhart:BAAANQAECgQIBAABNQAECgcIEQADAAAAAA==.Liotrix:BAAANQADCgYIBgABNQAECgkJHAAGAC8cAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgYIEwAAAA==.Lizolio:BAAANQAECgYICwAAAA==.',
Ll='Llomel:BAAANQAECgEIAQAAAA==.',
Lo='Lochlan:BAAANQADCggIDwAAAA==.Lohhano:BAAANQABCggIDgAAAA==.Londo:BAAANQADCgYIDAAAAA==.Louanna:BAAANQADCgYIBwAAAA==.',
Lu='Lucianagi:BAAANQAECgYIDAAAAA==.Lucilla:BAAANQADCgcICAAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcIDgAAAA==.',
Ly='Lynavas:BAAANQADCgcIEwAAAA==.',
['Là']='Làgs:BAAANQAECgYIDgABNQAFFAIIBgAOAKYfAA==.',
Ma='Machiné:BAAANQAECgEIAgAAAA==.Macnaulty:BAAANQADCggIBgAAAA==.Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAABNQAECoEkAAIRAAkKryKwBwB2AwARAAkKryKwBwB2AwAAAA==.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Maibutzfel:BAAANQADCggICQAAAA==.Majamojopowa:BAAANQABCgcIBwAAAA==.Majicman:BAAANQAECgQIBwAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manimal:BAAANQAECgQIBAABNQAECgcIEAADAAAAAA==.Mankrikswife:BAAANQADCggIEAABNQAECgUIEgADAAAAAA==.Manutters:BAAANQAECgUICwAAAA==.Marrylanders:BAACNQAFFIEGAAIOAAIKph+DNAC6AAAOAAIKph+DNAC6AAA1AAQKgUwAAw4ACQo9JX0MAJ4DAA4ACQrJJH0MAJ4DAB0ABApOIhAPAI0BAAAA.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAABNQAECoE0AAMHAAkKgRyrDwDcAgAHAAkKgRyrDwDcAgAGAAIKNhGFGAF4AAABNQAECggIIAAJAJgfAA==.Mastayoda:BAAANQABCgMIAwAAAA==.Mayven:BAAANQADCgUICgAAAA==.',
Mc='Mcboomii:BAAANQADCggICAAAAA==.',
Me='Megapally:BAAANQADCgQJBAAAAA==.Mellie:BAAANQAECgIIAgAAAA==.Melmei:BAAANQAECgUIDQAAAA==.Mephixto:BAAANQAECgQIDgAAAA==.Meriweather:BAAANQAECgUICQAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Mertlek:BAAANQAECgUIDQABNQAECggIIAAJAJgfAA==.Meszyra:BAACNQAFFIEIAAIcAAUKrRIUBACGAQAcAAUKrRIUBACGAQA1AAQKgSoAAhwACQr2HKcHAPACABwACQr2HKcHAPACAAAA.Meudäil:BAAANQAECgMIAwAAAA==.',
Mg='Mgreenleaf:BAAANQABCgUIDgAAAA==.',
Mi='Michaelcera:BAABNQAECoEcAAITAAgKqyAzIQDoAgATAAgKqyAzIQDoAgAAAA==.Mijuku:BAABNQAECoEtAAIJAAkKTx7PHADCAgAJAAkKTx7PHADCAgAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Minusgreen:BAAANQAECgIIAgAAAA==.Misoeternal:BAAANQAECgUIDQAAAA==.Mistafista:BAAANQAECgIIAgAAAA==.Mistralis:BAAANQAECgQIBwABNQAFFAUICAAOAEwQAA==.Mitchard:BAABNQAECoEjAAIKAAkKiw+qKwAJAgAKAAkKiw+qKwAJAgAAAA==.Mittenza:BAAANQADCggIFgAAAA==.Mixelplix:BAAANQAECgMJAwAAAA==.Mizstriss:BAAANQAECgUIBwAAAA==.',
Mo='Molari:BAAANQAECgMIBAAAAA==.Moloyagi:BAAANQABCgIIAgAAAA==.Monksymeg:BAAANQADCgIIBAAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Monterce:BAAANQADCgIIAgAAAA==.Moonfur:BAAANQAECgUICgAAAA==.Mooseknuck:BAAANQADCgMIAwAAAA==.Mordath:BAAANQAECgIIBAAAAA==.Mordetkai:BAAANQADCgYIBgAAAA==.Mordoom:BAAANQAECgQIDQAAAA==.Morikai:BAAANQAECgUIBgAAAA==.Morinn:BAAANQAECgIIAwAAAA==.Mosag:BAABNQAECoEdAAMRAAgKrB5wSwAaAgARAAcKUB5wSwAaAgAYAAYKRB8zIgD9AQAAAA==.Moushou:BAABNQAECoEYAAIEAAcKmg4mIABUAQAEAAcKmg4mIABUAQAAAA==.',
Ms='Mspacman:BAAANQAECgMIAwAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAABNQAECoElAAITAAkKAh6gHQD+AgATAAkKAh6gHQD+AgAAAA==.Muppie:BAAANQADCgQIBQAAAA==.Mutovenator:BAAANQAECgQIBQAAAA==.',
My='Mychef:BAAANQAECgQIBAAAAA==.Myrrha:BAABNQAECoEjAAMcAAkKsSIxBABKAwAcAAkKsSIxBABKAwAWAAYKwRPbIQCdAQAAAA==.',
['Mî']='Mîchael:BAAANQADCgIIAgAAAA==.',
['Mï']='Mïsterfox:BAAANQAECgIIAgAAAA==.',
['Mô']='Mônah:BAAANQADCgYICgABNQADCggIEAADAAAAAA==.',
Na='Nahota:BAAANQABCgIIAgAAAA==.Nakiro:BAAANQAECgQIBAAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICwAAAA==.',
Ne='Necroussy:BAAANQAECggIAgAAAA==.Nedilap:BAAANQAECgcIDwAAAA==.Nef:BAAANQAECgUIDQAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdchillpal:BAAANQADCgYIBgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQAECgUIDQAAAA==.Nerovash:BAAANQAECggIBQAAAA==.Nerve:BAAANQAECgYIDwAAAA==.',
Ni='Nightx:BAABNQAECoEVAAMJAAYKaht7TwCtAQAJAAYKaht7TwCtAQAKAAEKHg70kQA2AAAAAA==.Ninn:BAAANQADCgYIBgAAAA==.Nishkavel:BAAANQADCgcICwAAAA==.Nitewang:BAABNQAECoEXAAICAAcKECYIBQANAwACAAcKECYIBQANAwAAAA==.Nitewing:BAACNQAFFIEZAAIVAAcKAiGxAACSAgAVAAcKAiGxAACSAgA1AAQKgSoAAhUACQpZJqABALkDABUACQpZJqABALkDAAE1AAQKCAgXAAIAECYA.Niza:BAAANQABCgYIDAAAAA==.',
No='Noccs:BAAANQAECgEIAQAAAA==.Noctaro:BAEBNQAECoElAAIWAAkKpBWSEgBuAgAWAAkKpBWSEgBuAgAAAA==.Nokona:BAAANQADCggIEAAAAA==.Notpizza:BAAANQAECgMIAwABNQAFFAUICAAOAMkLAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAECgkJJQATAAIeAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
['Nø']='Nødiddy:BAAANQAFFAMIAwAAAA==.',
Ob='Obnixa:BAABNQAECoEhAAIGAAkK+CBQFAA2AwAGAAkK+CBQFAA2AwAAAA==.Obnixlis:BAAANQADCgYIBgAAAA==.',
Od='Ody:BAAANQAECgEIAQAAAA==.',
Og='Ogakal:BAAANQABCggIGQAAAA==.',
Oh='Ohsora:BAAANQADCgcIBwAAAA==.',
Ol='Oldstorm:BAAANQADCgEIAQABNQAECggIIQAUANoYAA==.',
On='Onfiree:BAAANQAECggJCwAAAA==.',
Op='Opithel:BAABNQAECoElAAIjAAkKyCTlAQDDAwAjAAkKyCTlAQDDAwAAAA==.Opiurza:BAAANQAECggIEgABNQAECgkJJQAjAMgkAA==.Opizerka:BAAANQAECgcJEgABNQAECgkJJQAjAMgkAA==.',
Or='Ordroin:BAAANQADCggICAAAAA==.Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAABNQAECoEZAAIgAAgKdwpUFQDpAQAgAAgKdwpUFQDpAQAAAA==.Oríllas:BAAANQAECgQICAAAAA==.',
Oy='Oyogo:BAACNQAFFIEPAAIWAAcKDxquAgBPAgAWAAcKDxquAgBPAgA1AAQKgR8AAhYACQoQIm8GADUDABYACQoQIm8GADUDAAAA.Oyogu:BAAANQADCgUIBQABNQAFFAcIDwAWAA8aAA==.Oyumi:BAAANQAFFAIIBAABNQAFFAcIDwAWAA8aAA==.',
Pa='Paech:BAAANQAECgQIBAAAAA==.Pairädice:BAAANQADCgYIDAAAAA==.Paladane:BAAANQAECgMIBQAAAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQAECgIIBQAAAA==.Pamalinaa:BAAANQAECgQIDAAAAA==.Pamplemousse:BAAANQAECggIBgAAAA==.Pandadave:BAAANQADCgUIEgAAAA==.Papanezz:BAAANQAECgQIBgAAAA==.Papasin:BAAANQAECggICAAAAA==.Patapouf:BAAANQAECgIIBgAAAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQAECgMIBAAAAA==.Pedestal:BAAANQADCggICAAAAA==.Pegully:BAABNQAECoEXAAIaAAcKrQvAQQB7AQAaAAcKrQvAQQB7AQAAAA==.Pewxtwo:BAAANQADCgYIBwAAAA==.',
Ph='Phephraan:BAABNQAECoEeAAIgAAgKsxcuDQCBAgAgAAgKsxcuDQCBAgAAAA==.Phinehas:BAAANQAECgQIBgAAAA==.Phwaz:BAAANQAECgUIDQAAAA==.Phyxyzin:BAAANQADCgUIDQAAAA==.',
Pi='Piccoloo:BAAANQAECgIIAgAAAA==.Piddles:BAAANQADCgYJBgAAAA==.Pikeysham:BAAANQADCgMJAwAAAA==.Pinchebean:BAAANQAECgUIDwAAAA==.Pinktress:BAABNQAECoEbAAIGAAcKcxKDfwDfAQAGAAcKcxKDfwDfAQAAAA==.Pizzadough:BAACNQAFFIEIAAIOAAUKyQsCGwB1AQAOAAUKyQsCGwB1AQA1AAQKgSAAAg4ACQo6GVJwAIcCAA4ACQo6GVJwAIcCAAAA.Pizzapurse:BAAANQADCgQIBAAAAA==.',
Pk='Pkcontrol:BAAANQADCgUIBQAAAA==.',
Pl='Plavalagoona:BAAANQADCgMIBAABNQAECggIGwANAIMUAA==.Plskillmie:BAABNQAECoEbAAMJAAcKdgVIgwDpAAAJAAYKkQVIgwDpAAAKAAcKAgP/XQDeAAAAAA==.',
Po='Pocahontis:BAAANQABCgIIAgAAAA==.Politics:BAAANQAECggIBgAAAA==.Polygonnacry:BAAANQAECgIJAgAAAA==.Polyhaladin:BAAANQAECgQIBAABNQAECgkJJQATAAIeAA==.Popatop:BAAANQADCgcICwAAAA==.Possecutor:BAACNQAFFIEPAAIYAAQKnxb6CAA/AQAYAAQKnxb6CAA/AQA1AAQKgScAAhgACQo9IGYMAA0DABgACQo9IGYMAA0DAAAA.Pownadin:BAAANQADCgUICgAAAA==.',
Pr='Prabis:BAAANQAECgUICQAAAA==.Praesidius:BAAANQADCgcIDgAAAA==.Priestalama:BAAANQAECgUIBQAAAA==.Priestsita:BAAANQAECgcICQAAAA==.Priscillà:BAAANQADCgQIBAABNQAECgkJIwAcALEiAA==.Pristakos:BAAANQADCgQIBAAAAA==.Promise:BAAANQAECgQIBAAAAA==.Pryîto:BAAANQAECgUIBwAAAA==.',
Pu='Pumachaka:BAAANQAECgQIBwAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Pv='Pvp:BAAANQADCggICAAAAA==.',
Py='Pyresia:BAAANQAECgQICQAAAA==.Pyrocity:BAAANQADCgYIBgAAAA==.',
Qu='Quackshot:BAABNQAECoEmAAQGAAgKniSTEABNAwAGAAgKniSTEABNAwAIAAQK8xsqCgBAAQAHAAEKTRe8fAAzAAAAAA==.',
Qw='Qwertysquid:BAAANQAECgQIBAAAAA==.',
Ra='Rads:BAAANQABCgEIAQAAAA==.Raegen:BAEANQAECggIAQABNQAECgkJJQAWAKQVAA==.Raezer:BAEANQADCggICAABNQAECgkJJQAWAKQVAA==.Raiin:BAAANQAECgYIBwABNQAFFAcIFwAYAGEWAA==.Raikomori:BAAANQAECgYIBgAAAA==.Ralroc:BAAANQADCgcIEAAAAA==.Ranare:BAAANQAECgcIDgAAAA==.Randomfatguy:BAAANQAECgEIAQAAAA==.Rathrus:BAAANQAECgQICwAAAA==.Ratonfusse:BAAANQABCgQIBAAAAA==.Ravenhart:BAAANQAECgcIEQAAAA==.Ravienn:BAAANQAECgIIAgABNQAECggIIAAJAJgfAA==.Raxmanus:BAAANQAECgEJAQAAAA==.Rayru:BAAANQAECgIIAgAAAA==.Rayvienne:BAAANQADCgUICAAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQAECgUICwAAAA==.Reilini:BAABNQAECoEmAAIMAAkKphwwPgC2AgAMAAkKphwwPgC2AgAAAA==.Remedium:BAAANQABCgYICwAAAA==.Renascor:BAAANQAECgQICgABNQAFFAUIDQAcAEASAA==.Reàp:BAAANQAECgIIAgAAAA==.',
Rh='Rhojin:BAAANQADCggIFgAAAA==.',
Ri='Rikimaruu:BAABNQAECoEZAAISAAkKHRtwEQDSAgASAAkKHRtwEQDSAgAAAA==.Rinaari:BAAANQADCgUIBQAAAA==.Rinsecycle:BAAANQADCggIEAAAAA==.Rivelia:BAAANQAECgIIAwABNQAECgkJIwAcALEiAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQAECgMIBgAAAA==.Ronek:BAAANQABCgUIBwAAAA==.Rosabella:BAAANQADCgQJBAAAAA==.Roshisain:BAAANQADCgcICgAAAA==.Rossbob:BAAANQADCgYIBQAAAA==.Rouñders:BAAANQAECgEIAwABNQAFFAcIFwAYAGEWAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAABNQAECoEkAAIOAAgKzBndhQBZAgAOAAgKzBndhQBZAgAAAA==.Rueldalf:BAAANQAECgQIBAAAAA==.Ruïn:BAAANQADCggIIQAAAA==.',
['Ré']='Réka:BAAANQADCgUICAABNQAECggIFwAJAJwLAA==.',
['Rô']='Rôôst:BAAANQADCgIIAgAAAA==.Rôôstêr:BAAANQADCgQIBAAAAA==.',
Sa='Saatara:BAAANQADCgQIBQAAAA==.Sagittarius:BAAANQADCgQIBAAAAA==.Saino:BAAANQAECgEIAQAAAA==.Salidan:BAAANQADCgMIAwAAAA==.Salt:BAAANQAECgYIBwABNQAECgkJJQAOAJkdAA==.Samlock:BAABNQAECoExAAIQAAkKCCDLAQBUAwAQAAkKCCDLAQBUAwAAAA==.Sap:BAACNQAFFIEOAAQSAAUK6xM8CwD2AAAbAAMKgxMZCgAFAQASAAMK0Q88CwD2AAAiAAEKnREvAwBPAAA1AAQKgSEABBIACQqZIAwMAAwDABIACQqMIAwMAAwDACIABgovF+cMAGYBABsAAwp3ExE6AMIAAAE1AAQKCAgWAA0AVCUA.Satyrlord:BAAANQAECgMJAwAAAA==.Savella:BAABNQAECoEZAAMhAAgKhBVSEwAbAgAhAAgKhBVSEwAbAgAlAAEKLgzNYQAsAAAAAA==.',
Sc='Scaleshot:BAAANQADCgYJBgAAAA==.Scarletblade:BAABNQAECoErAAMMAAkKsx6VLgDwAgAMAAkKex6VLgDwAgAVAAQKrBeWNwACAQAAAA==.Schamwoww:BAAANQAECgMIAwAAAA==.Schlam:BAAANQADCggICAAAAA==.Sclas:BAAANQAECgEIAQAAAA==.Scubar:BAAANQAECgUIDQAAAA==.',
Se='Seafox:BAAANQAECgIIAwAAAA==.Sear:BAABNQAECoEjAAIjAAkKJBmtFQCeAgAjAAkKJBmtFQCeAgAAAA==.Seasoning:BAAANQADCgIIAgAAAA==.Selest:BAAANQADCgEIAQAAAA==.Selindris:BAAANQAECgUIBQAAAA==.Selkets:BAAANQADCgUIBQAAAA==.Selkola:BAAANQABCggIDwAAAA==.Sephimus:BAAANQADCgYIBgABNQAECggIGwAZANkgAA==.Seraphiina:BAABNQAECoEeAAIMAAcKwgY90QA+AQAMAAcKwgY90QA+AQAAAA==.Seraphimn:BAAANQADCgEIAQAAAA==.Serbixalot:BAABNQAECoEWAAIMAAcKKgoxwABjAQAMAAcKKgoxwABjAQAAAA==.',
Sh='Shadowbinder:BAAANQADCggICAAAAA==.Shadowyclaws:BAAANQADCgEIAQAAAA==.Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgUIBgAAAA==.Shararena:BAAANQADCggICAAAAA==.Shataree:BAAANQADCgcICwAAAA==.Shazno:BAAANQAECgIIAgAAAA==.Shineup:BAAANQADCggIEAAAAA==.Shintetsu:BAAANQADCggIDQAAAA==.Shockkor:BAAANQADCgcIDgAAAA==.Shockujin:BAAANQAECgIIAgABNQAECgkJIgALAMsUAA==.Shox:BAAANQADCgMIAwAAAA==.Shredder:BAAANQAECgEIAgABNQAECgcIGAAcAIwWAA==.Shý:BAAANQADCgIIAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sinvalk:BAAANQADCgIIAgAAAA==.Sitaana:BAAANQAECgUIDAAAAA==.',
Sk='Skellek:BAAANQADCggICAAAAA==.Skillr:BAABNQAECoEaAAMjAAcKmhYFKgDSAQAjAAcKmhYFKgDSAQAaAAEKagrZhAAxAAAAAA==.Skyekníght:BAAANQAECgMIBAAAAA==.Skysong:BAAANQAECgQIBwABNQAFFAMIBgAFAE4VAA==.',
Sl='Slaa:BAAANQADCgMIAwAAAA==.Sleezyaf:BAABNQAECoEcAAQPAAcK5hVXhACuAQAPAAYKLhZXhACuAQAQAAMKLAvpRQCkAAAXAAEKfxQvLAA0AAAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAABNQAECoEXAAMeAAgKMh6jCQATAgAeAAcKQBujCQATAgANAAcKKBetoQCdAQAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQAECgQICQAAAA==.',
So='Soapyy:BAAANQADCgUIBQAAAA==.Socketss:BAAANQAECgEIAQAAAA==.Sohjinra:BAAANQAECgQICQAAAA==.Sollaria:BAAANQADCgYICQAAAA==.Sololvlin:BAAANQADCgYIDgAAAA==.Sololvling:BAABNQAECoEfAAITAAcKvRg3UQAGAgATAAcKvRg3UQAGAgAAAA==.Sovereign:BAACNQAFFIEVAAIMAAYKMhanAwARAgAMAAYKMhanAwARAgA1AAQKgSoAAgwACQoXIjciACMDAAwACQoXIjciACMDAAAA.',
Sp='Sp:BAAANQAECggIBwAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spicy:BAAANQAECgEIAQAAAA==.Splashaxuss:BAAANQADCgUICAAAAA==.Spookyloops:BAAANQAECggIDQAAAA==.Sproggles:BAAANQAECgYIBQABNQAECgYICAADAAAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQABNQAECgYIEQADAAAAAA==.',
St='Stealthfire:BAACNQAFFIEGAAIFAAMKThW4AQAHAQAFAAMKThW4AQAHAQA1AAQKgSUAAgUACQpqJEkBALcDAAUACQpqJEkBALcDAAAA.Sterny:BAAANQAECgYIDwAAAA==.Stidetroll:BAAANQAECgUIBgAAAA==.Stnnisbrthon:BAAANQADCgQIBAAAAA==.Stormstrikes:BAAANQAECgQIBgAAAA==.Strongw:BAAANQAECggIEAAAAA==.Stul:BAABNQAECoEWAAIjAAcKmgouMgCMAQAjAAcKmgouMgCMAQAAAA==.',
Su='Substandard:BAAANQAECgYICQAAAA==.Sugaboomboom:BAAANQAECgEIAQAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sumwon:BAAANQAECgYIEQAAAA==.Sumwun:BAAANQADCggICQABNQAECgYIEQADAAAAAA==.Sunarr:BAABNQAECoEhAAIMAAkKExzEOQDGAgAMAAkKExzEOQDGAgAAAA==.Sunkenlily:BAAANQADCgcIDAAAAA==.Superace:BAACNQAFFIEJAAITAAQK7AgSEQAgAQATAAQK7AgSEQAgAQA1AAQKgSEAAhMACQr2F+svAJcCABMACQr2F+svAJcCAAAA.Surlee:BAAANQAECgEIAQAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQAECgUIDQAAAA==.',
Sw='Swaggernaut:BAAANQAECgMIBQAAAA==.Swiffys:BAABNQAECoEdAAIKAAgKrxWmLwDvAQAKAAgKrxWmLwDvAQAAAA==.Swissy:BAAANQADCgQIBwAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Syix:BAAANQADCgYIBwAAAA==.Synkadevour:BAAANQAECgUICgABNQAECgUIDwADAAAAAA==.Synkapriest:BAAANQAECgUIDwAAAA==.Synkareaper:BAAANQADCgQIBgABNQAECgUIDwADAAAAAA==.Synxzc:BAAANQADCgUIBQAAAA==.Syraelyssa:BAAANQABCgEIAQAAAA==.',
Ta='Taappy:BAAANQAECgQICgAAAA==.Tacostuffing:BAAANQADCgYICQAAAA==.Taggs:BAABNQAECoEgAAMYAAgKgRjyGQBbAgAYAAgKgRjyGQBbAgARAAQKcRCargDRAAAAAA==.Taggsy:BAAANQAECgcIBwAAAA==.Tail:BAAANQAECgYIEgAAAA==.Tails:BAAANQADCgYIEQAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQAECgQIDgAAAA==.Tanthora:BAAANQAECgEIAQAAAA==.Tao:BAAANQADCgMIAwAAAA==.Tastyfísh:BAAANQADCggICAAAAA==.',
Te='Teddymouse:BAAANQAECggICgAAAA==.Tenebris:BAAANQADCgUIBgAAAA==.',
Th='Thanatóz:BAABNQAECoEnAAMJAAkKUiDhHQC7AgAJAAkKUiDhHQC7AgAKAAEKbRJXkAA5AAAAAA==.Thasper:BAAANQABCgMIAwAAAA==.Thebigkodiak:BAAANQADCggIDgAAAA==.Thebutler:BAABNQAECoEVAAIPAAgKHyAfHgD2AgAPAAgKHyAfHgD2AgABNQAFFAcIFwAYAGEWAA==.Thegrimus:BAABNQAECoEmAAIgAAkK9yKNAgB+AwAgAAkK9yKNAgB+AwAAAA==.Thekeres:BAAANQAECgQIBAAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Thorsten:BAAANQAECgMIBgABNQAECgcIEQADAAAAAA==.Thrashley:BAAANQADCggICAAAAA==.Throh:BAAANQADCgUIBwAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Timøthy:BAABNQAECoEXAAIJAAgKnAsYVgCRAQAJAAgKnAsYVgCRAQAAAA==.Tismtouched:BAAANQAECgMIAwAAAA==.',
Tk='Tkaniaa:BAAANQADCgQIDwAAAA==.Tkaniy:BAAANQADCgIIAgAAAA==.',
To='Tokeyes:BAAANQAECgcIEAAAAA==.Toost:BAAANQAECgYIDwAAAA==.Torwa:BAAANQAECgIIBQAAAA==.Tossdirt:BAACNQAFFIESAAMTAAcKsRw1AQCuAgATAAcKsRw1AQCuAgAUAAEKHggWJgBIAAA1AAQKgSUAAxMACQqlJXsGAKsDABMACQqlJXsGAKsDABQAAQoKCG4OASUAAAAA.Toxle:BAAANQAECgEJAwAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trakshot:BAECNQAFFIETAAMGAAYK9BNCBAD1AQAGAAYKoBJCBAD1AQAIAAEKmg4CAgBTAAA1AAQKgR4ABAYACQoDIUUcAA0DAAYACQoDIUUcAA0DAAgAAwoFGtQLAPcAAAcAAQp6D+dxAEIAAAE1AAQKCQkfAAYAbxcA.Trippdaddy:BAAANQAECgIIAgAAAA==.Troubling:BAAANQADCgIIAgAAAA==.Truefaith:BAAANQAECgQIBAAAAA==.Trufflepig:BAAANQADCgcIBwAAAA==.',
Ts='Tserendolgor:BAAANQABCgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgYIBwAAAA==.Tullegol:BAAANQAECgIIAgAAAA==.Tunaset:BAAANQADCgQIBAAAAA==.Tunasut:BAAANQADCgcIBwAAAA==.',
Tw='Twinswords:BAAANQAECgEJAQAAAA==.Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgQIBAAAAA==.',
Ty='Typhal:BAABNQAECoEfAAIMAAgK1yJtLwDtAgAMAAgK1yJtLwDtAgAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
['Té']='Téllah:BAAANQADCgYIBgAAAA==.',
Uh='Uhtain:BAAANQAECgUICgABNQAECgMIAwADAAAAAA==.Uhtan:BAAANQAECgUIDQABNQAECgMIAwADAAAAAA==.',
Ul='Uleo:BAAANQADCgMIAwAAAA==.',
Un='Uncleklaus:BAABNQAECoEmAAIMAAkK2R9aLQD1AgAMAAkK2R9aLQD1AgAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unicornfartz:BAAANQADCggICAAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQAECgYIEgAAAA==.',
Us='Ushiamdi:BAABNQAECoEiAAIEAAgKGx/gCAC2AgAEAAgKGx/gCAC2AgAAAA==.',
Ut='Utaan:BAAANQAECgMIAwAAAA==.',
Va='Vaduh:BAAANQADCgQIBAAAAA==.Vaerenaris:BAAANQADCgEIAQAAAA==.Vaiel:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Valanthé:BAAANQADCgYIEAAAAA==.Vandrey:BAAANQAECgIIAwAAAA==.Vazen:BAAANQADCggIGAAAAA==.',
Ve='Velarasta:BAAANQADCgYIDQAAAA==.Veluna:BAAANQABCgMIAwABNQAECggIHAALACUhAA==.Veravvang:BAAANQAECgQIBwABNQAECggICgADAAAAAA==.Verdereina:BAAANQADCgcIBwAAAA==.Veroshia:BAAANQADCggIGwAAAA==.Versadeus:BAAANQADCgYIBgAAAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vh='Vhail:BAAANQAECgYIAgAAAA==.',
Vi='Vinee:BAAANQADCgcJBwABNQAECggIIwAGAEAiAA==.Vinladen:BAAANQADCgMIAwABNQAECggIFwASAB0eAA==.Violettcloud:BAAANQAECgMIBAABNQAECggIMAAfANQjAA==.Virali:BAABNQAECoEeAAIVAAgKFBTFIQCoAQAVAAgKFBTFIQCoAQAAAA==.Virussuckss:BAAANQADCgYIBgAAAA==.Vispper:BAAANQAECgUIEgAAAA==.Viviean:BAAANQAECgIIAgAAAA==.Vixenvalk:BAAANQADCgQIBwAAAA==.Viyinx:BAAANQAECgYIBwABNQAECgkJJwAJAFIgAA==.Vizuel:BAAANQADCgUIDwABNQAECgIIAgADAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Vorel:BAAANQAECgQIBAAAAA==.',
Vp='Vpung:BAAANQAECgQIEQAAAA==.',
Vy='Vyllin:BAABNQAECoEkAAIVAAkKXR4HCwDKAgAVAAkKXR4HCwDKAgAAAA==.Vynarran:BAAANQAECgYIDwAAAA==.Vynlann:BAAANQADCgQIBAAAAA==.',
Wa='Warob:BAAANQAECggIDAAAAA==.Warringmyer:BAAANQAECgYIEwAAAA==.Warriorlol:BAABNQAECoEWAAINAAgKVCUOJQAVAwANAAgKVCUOJQAVAwAAAA==.Watchdodo:BAAANQAECgQICwAAAA==.Wax:BAAANQAECgMJAgAAAA==.',
We='Weebscum:BAABNQAECoEnAAMMAAkKehQFbwAkAgAMAAkKehQFbwAkAgAVAAMKjQTvUABwAAAAAA==.',
Wi='Wiket:BAAANQABCgQIBAAAAA==.Wildestspice:BAABNQAECoEeAAMfAAkKnhXIJgB8AgAfAAkKnhXIJgB8AgABAAcK/RbwHwAAAgABNQAFFAUIDQALAAAYAA==.Willowblessu:BAABNQAECoEyAAImAAkKlxyyAQAUAwAmAAkKlxyyAQAUAwAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQAECgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQADCgYIDQAAAA==.Woodglue:BAAANQADCggICAAAAA==.Worgarg:BAAANQAECgMIBAAAAA==.Wovenxlight:BAAANQAECgQIBAAAAA==.',
Wr='Wranglep:BAAANQADCggIEQAAAA==.Wrathin:BAAANQAECgQIBAAAAA==.Wrayvin:BAAANQABCgEIAQAAAA==.',
Wu='Wufel:BAAANQAECgYJCQAAAA==.',
Xa='Xaeora:BAABNQAECoEYAAILAAgKdw+dXgDZAQALAAgKdw+dXgDZAQAAAA==.Xawne:BAAANQAECgUIBgAAAA==.',
Xe='Xeona:BAAANQADCgYJFAAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Ya='Yadhnak:BAAANQADCgQIBAAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yemii:BAAANQAECgMIAgAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yi='Yikes:BAAANQADCgEIAQAAAA==.',
Yo='Yorichef:BAAANQAECgQIBAAAAA==.Yoshikawa:BAEBNQAECoEvAAMTAAkKqiBJEwBDAwATAAkKqiBJEwBDAwAUAAYKlxL7eQBvAQABNQAECgkJKAAfABUXAA==.',
Yr='Yrac:BAAANQAECgEIAQABNQAECgQIBQADAAAAAA==.',
Ys='Ysora:BAAANQADCgMIAwAAAA==.',
Za='Zaivama:BAAANQAECgMIAwAAAA==.Zandren:BAAANQAECgQIBAAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAACNQAFFIEIAAIOAAUKTBAXGACQAQAOAAUKTBAXGACQAQA1AAQKgRcAAw4ACQoSIXFIAOMCAA4ACQoSIXFIAOMCAB0AAgoiF1kpAIUAAAAA.',
Ze='Zeenaheals:BAAANQAECgcIDAABNQAECgcIGAAcAIwWAA==.Zeenalizard:BAABNQAECoEYAAMcAAcKjBZIEwD6AQAcAAcKjBZIEwD6AQAWAAQKJAeBOwCdAAAAAA==.Zegoo:BAABNQAECoEWAAIMAAgKnBL7pgCaAQAMAAgKnBL7pgCaAQAAAA==.Zendezit:BAAANQAECgQIBgAAAA==.Zenet:BAAANQAECgUIBQAAAA==.Zenthura:BAAANQADCgIIAgABNQAFFAUICAAOAEwQAA==.Zenïca:BAAANQAECgMIAwAAAA==.Zewz:BAAANQAECggIAQAAAA==.',
Zi='Zilis:BAAANQAECgEIAQAAAA==.Zimbadah:BAAANQAECgEJAQAAAA==.',
Zn='Znny:BAABNQAECoEmAAIeAAkK5xptBADRAgAeAAkK5xptBADRAgAAAA==.',
Zy='Zynling:BAAANQABCgUIBQAAAA==.Zynpouch:BAABNQAECoEqAAMPAAkKnCHFJQDVAgAPAAgKpiHFJQDVAgAQAAQKBx6/JgA1AQAAAA==.Zyrb:BAAANQADCggICwAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Ár']='Árthas:BAAANQAECgQIBgAAAA==.',
['Âr']='Ârthas:BAAANQAECgUIBwAAAA==.',
['Çl']='Çlutch:BAAANQAECgEIAQAAAA==.',
['Çr']='Çrimes:BAABNQAECoEYAAIGAAkKTQ7VXgAwAgAGAAkKTQ7VXgAwAgAAAA==.',
['Çu']='Çutty:BAAANQAECggIEAAAAA==.',
['Ðo']='Ðom:BAAANQABCgQIBAAAAA==.',
['ßâ']='ßâßygirl:BAAANQAECgQIBAAAAA==.',
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
