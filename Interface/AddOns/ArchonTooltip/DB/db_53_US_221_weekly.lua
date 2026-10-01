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

local lookup = {'Druid-Restoration','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Paladin-Holy','Warrior-Arms','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Druid-Guardian','Priest-Holy','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Warlock-Affliction','Priest-Shadow','DeathKnight-Blood','DemonHunter-Havoc','Rogue-Assassination','Druid-Feral','Warrior-Fury','Druid-Balance','Rogue-Subtlety','Mage-Frost','Monk-Mistweaver','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','DeathKnight-Frost','Evoker-Preservation','Rogue-Outlaw','Shaman-Enhancement','Priest-Discipline',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaliyah:BAABNQAECoEkAAIBAAkKoBiJDwCjAgABAAkKoBiJDwCjAgAAAA==.',
Ab='Aboxofchips:BAAANQAECggIBwAAAA==.Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQAECgQIBgAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQAECgQIBAABNQAECggIHwACACAbAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgQICQADAAAAAA==.',
Ag='Aggressor:BAAANQADCgMIAwAAAA==.Aggrocrack:BAAANQAECgYIEwAAAA==.Agliam:BAAANQAECgEJAgAAAA==.',
Ah='Ahngus:BAAANQAECgYIDwAAAA==.',
Ai='Air:BAAANQAECgUIDAAAAA==.',
Al='Alakander:BAAANQAECgMIBgAAAA==.Alexcrowley:BAAANQADCgYICwAAAA==.Alexdh:BAAANQAECgEIAQABNQAFFAYIDQAEAHsjAA==.Alexdk:BAAANQADCgMIAwABNQAFFAYIDQAEAHsjAA==.Alexdruids:BAAANQAECgUIBQABNQAFFAYIDQAEAHsjAA==.Alexhunt:BAACNQAFFIENAAQEAAYKeyNKAgAEAgAEAAUKJCRKAgAEAgAFAAIKGQ3MFQCKAAAGAAEKLCBdAQBiAAA1AAQKgSEABAQACQpTI5QiANQCAAQACAooI5QiANQCAAUABwrSHtcaAEcCAAYAAQr8IL0NAF0AAAAA.Alexpaladin:BAAANQAECgUIBQABNQAFFAYIDQAEAHsjAA==.Alplarn:BAAANQAECgQIBgAAAA==.Althsar:BAAANQADCgEIAQAAAA==.Alucardias:BAAANQADCgYIBgAAAA==.',
Am='Amorlorisy:BAAANQADCggICAABNQAECgMIAwADAAAAAA==.',
An='Anitwa:BAABNQAECoEcAAIHAAgKcx+6FgDMAgAHAAgKcx+6FgDMAgABNQAECgkJLgAFAKkbAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgIIBAAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAABNQAECoEfAAIEAAgKpBRXVAAjAgAEAAgKpBRXVAAjAgAAAA==.Aranina:BAAANQAECgQICAAAAA==.Arcami:BAAANQADCgIIAgAAAA==.Arcanedria:BAAANQABCgYIBgAAAA==.Arcturrus:BAAANQAECgMIAwAAAA==.Arel:BAABNQAECoEaAAIIAAcKCCIEJQCjAgAIAAcKCCIEJQCjAgAAAA==.Arkanis:BAAANQADCgYIBQAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arowid:BAAANQADCgYIFAAAAA==.Arrwyn:BAAANQAECgYIBAABNQAECggIDgADAAAAAA==.Arter:BAAANQAECgEIAQABNQAECggIIwAJAL4UAA==.Aryhm:BAAANQAECgYICgAAAA==.',
As='Asatralth:BAAANQAECgUICwAAAA==.Asguard:BAAANQAECgEIAQAAAA==.Asheryo:BAAANQADCgUIBQAAAA==.Assphyxiate:BAAANQAECgIIBAAAAA==.Aszshara:BAAANQAECgMIBAAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAAANQAECgcIEQAAAA==.',
Ba='Babihotdog:BAAANQAECgMIBQAAAA==.Badspec:BAAANQAECggIAQAAAA==.Badwolff:BAAANQAECgUIDAAAAA==.Baerog:BAAANQAECgQIBgAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAABNQAECoEnAAIKAAkKxhrBRQDWAgAKAAkKxhrBRQDWAgAAAA==.Barlake:BAAANQADCgUIBQAAAA==.Basicblends:BAAANQAECgQIBQAAAA==.',
Bb='Bblglizzy:BAAANQADCgEIAQAAAA==.',
Be='Beefglizzy:BAAANQAECgYIEAAAAA==.Beeftàllow:BAAANQADCgUJBQAAAA==.Beelzaboot:BAABNQAECoEaAAMLAAcKehOVfACRAQALAAYKqxOVfACRAQAMAAIKrgyCUQB1AAAAAA==.Belanor:BAABNQAECoEfAAICAAgKIBtaCQBlAgACAAgKIBtaCQBlAgAAAA==.Benjangles:BAAANQAECgYIEAAAAA==.Berry:BAABNQAECoEoAAINAAkKGSRSAQCxAwANAAkKGSRSAQCxAwAAAA==.Betrayer:BAAANQAECgEIAQABNQAECggIGQAOAHIdAA==.',
Bh='Bhogrenoc:BAAANQAECgQIBAAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECgkJLgAFAKkbAA==.Bigdamfury:BAAANQAECgQIBQAAAA==.Bignipsmcgee:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgYJBAAAAA==.Bitss:BAAANQADCgEIAQABNQAECgYIEwADAAAAAA==.',
Bl='Blacksam:BAAANQAECgIIAgAAAA==.Blacktastic:BAAANQAECgMJAwAAAA==.Bladebane:BAAANQADCgQIBAABNQAECgQIDQADAAAAAA==.Blastee:BAABNQAECoEiAAIEAAgKmCFlGQACAwAEAAgKmCFlGQACAwAAAA==.Blath:BAAANQADCggIGAAAAA==.Blazius:BAAANQAECgQIBQAAAA==.Bleebles:BAAANQADCgMIAwAAAA==.Blinkinpark:BAAANQADCgEIAQAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.Bloodlego:BAAANQAECgcIDgABNQAFFAYIDwAJAFUbAA==.',
Bo='Bobertl:BAAANQAECgUICAAAAA==.Bolter:BAAANQAECgEIAgAAAA==.Boomnecrotic:BAAANQAECgYIEQAAAA==.Boonney:BAAANQADCgYIBgAAAA==.Bopgun:BAAANQADCgIIAgAAAA==.Bottlewater:BAAANQADCgEIAQAAAA==.',
Br='Braine:BAAANQADCgEIAQAAAA==.Breathboy:BAAANQAECgMIBgAAAA==.Bronder:BAAANQADCgYIEAAAAA==.Bronzehoofs:BAAANQADCggIDwAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Bulletbill:BAAANQADCgUIBQAAAA==.Bullwinklee:BAAANQADCgUIBQAAAA==.Burghmaul:BAAANQAECgUIDQAAAA==.',
Ca='Cadwallader:BAAANQABCgIIAgAAAA==.Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgIIAwAAAA==.Candykate:BAAANQADCgIIAgAAAA==.Canon:BAAANQAECgYICgAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Ceevee:BAAANQAECgIIAgAAAA==.Celasong:BAAANQAECgEIAQAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Celtïc:BAAANQADCgQJBwAAAA==.Celydrea:BAAANQAECgQICwAAAA==.Ceree:BAABNQAECoEXAAIPAAYKCQ7TrABUAQAPAAYKCQ7TrABUAQAAAA==.',
Ch='Chimeranzomb:BAAANQADCgQJBAAAAA==.Chippedbeef:BAAANQAECgQIDAAAAA==.Chiwi:BAAANQADCggICAAAAA==.Chocogeta:BAAANQAECgUIDgAAAA==.Chubbsmcgee:BAAANQADCgQJBAAAAA==.Chucknourysh:BAAANQADCgIIAgAAAA==.Chì:BAAANQAECgQIBQAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQAECgEIAQAAAA==.Cladow:BAABNQAECoEcAAMQAAgKSSOcFAAqAwAQAAgKSSOcFAAqAwARAAIK3hrkzQB1AAAAAA==.Clag:BAAANQAECgIIAgAAAA==.',
Co='Cogblock:BAABNQAECoEcAAIJAAcK6xMMggDBAQAJAAcK6xMMggDBAQAAAA==.Coldsteak:BAAANQADCggIDgAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cp='Cpwolf:BAAANQADCgYJBwAAAA==.',
Cr='Crimsonbull:BAAANQADCggICAABNQAECgkJJwALAJwhAA==.Cronosphere:BAAANQADCgcIEAAAAA==.Crushaturty:BAAANQAECgMIAgAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQADCgEIAQAAAA==.Cyndrin:BAABNQAECoEWAAMEAAgKJxyNLgCiAgAEAAgKJxyNLgCiAgAFAAEKkgfWaQA5AAAAAA==.',
Da='Daddyfatsaks:BAAANQADCgEIAQAAAA==.Daddyglock:BAAANQAECgUIBwAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAADAAAAAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAACNQAFFIEPAAIJAAYKVRtjBAA2AgAJAAYKVRtjBAA2AgA1AAQKgScAAgkACQosJogDANEDAAkACQosJogDANEDAAAA.Darknite:BAAANQAECgYIBAABNQAECggIDgADAAAAAA==.Darksign:BAAANQADCgIIAgAAAA==.Dathundir:BAAANQAECggIDgABNQAECgkJJAAPAKYcAA==.Davemage:BAAANQAECgUICwAAAA==.Davidpaine:BAAANQAECgUICgAAAA==.Dawnhorn:BAAANQADCgQIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBwAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Deepd:BAAANQAECggICgAAAA==.Deepyram:BAAANQADCgEIAQAAAA==.Delillama:BAABNQAECoEcAAIPAAgK0haTYgAaAgAPAAgK0haTYgAaAgAAAA==.Demolior:BAAANQABCgEIAQAAAA==.Destnny:BAAANQAECgUICgAAAA==.Destrohunter:BAAANQADCggIDgAAAA==.Destroker:BAAANQAECgUIEQAAAA==.Dewax:BAAANQADCgUIBQAAAA==.Deylight:BAAANQADCgYIBgAAAA==.',
Dh='Dhspudd:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.',
Di='Dillpo:BAAANQABCgUIBwAAAA==.Dioress:BAAANQAECgQIBgAAAA==.Dis:BAABNQAECoEbAAISAAgKLh8UAgDbAgASAAgKLh8UAgDbAgABNQAFFAYIDAAQAKwbAA==.Distear:BAAANQAECgIIAgAAAA==.Disyx:BAAANQAECgYICwAAAA==.Diyanå:BAABNQAECoEkAAIEAAgKhRbWRABTAgAEAAgKhRbWRABTAgAAAA==.',
Do='Domainz:BAAANQAECgYIDAAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donalan:BAAANQAECgEIAQAAAA==.Donzm:BAAANQADCgYIBgABNQAFFAQIBgALAHsIAA==.Donzw:BAACNQAFFIEGAAQLAAQKewhuIwCTAAALAAIKcwpuIwCTAAAMAAEKSwTKGABOAAASAAEKugidCwBFAAA1AAQKgSAABBIACQoVFWwKAHwBAAsACQqXE91KAC4CABIABwpNEmwKAHwBAAwABAo9BsE8ALoAAAAA.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQAECgcIEgAAAA==.Dragonbender:BAEANQAECgIIAgAAAA==.Dragun:BAAANQADCgIIAgAAAA==.Draxxor:BAAANQAECgEJAQAAAA==.Dreamender:BAAANQAECggJBQABNQAECggICQADAAAAAA==.Drfrash:BAAANQADCgYIBgAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAAANQAECgcIEwAAAA==.Drumin:BAAANQAECgYIDgAAAA==.',
Du='Dudewithpets:BAAANQADCgUIBQAAAA==.Durahar:BAAANQAECgYICQAAAA==.',
Dw='Dwarvanhand:BAACNQAFFIEQAAMTAAYKsxOxBgBVAQATAAQKvxexBgBVAQAOAAQKBxH4DQBOAQA1AAQKgScAAxMACQrGIpUJACMDABMACAoSJZUJACMDAA4AAgoyEhmwAIkAAAAA.',
['Dá']='Dáin:BAAANQAECgMIAwABNQAECgcICgADAAAAAA==.',
['Dã']='Dãwn:BAAANQAECggIBgAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQAECgcIDQABNQAECggIGQAUAOocAA==.Earthrender:BAAANQADCgUIBgAAAA==.Eatmacookie:BAAANQADCgYIEQAAAA==.',
El='Elazar:BAAANQAECgYICAAAAA==.Elderian:BAABNQAECoEhAAIVAAgK2CVrBgBxAwAVAAgK2CVrBgBxAwAAAA==.Elemenope:BAAANQAECgUIBwAAAA==.Elementhol:BAAANQADCgYIBgAAAA==.Elemitchard:BAAANQAECgUIBgAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAAANQAFFAIIAgAAAA==.Elitegamerx:BAAANQADCgUIBQABNQAECgYIEAADAAAAAA==.Elpadrino:BAAANQADCgUIAwAAAA==.Elunaryn:BAAANQAECggJAQAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emerys:BAAANQADCgUIBgAAAA==.Emitlyght:BAAANQADCggIFQAAAA==.Emmabeth:BAAANQADCgMJAwAAAA==.',
En='Eniri:BAAANQAECgMIBgAAAA==.Enyeto:BAABNQAECoEjAAMJAAgKvhQobgD7AQAJAAgKCBQobgD7AQACAAEKUg2sMwAzAAAAAA==.',
Er='Ermaghaku:BAAANQADCgQJBAAAAA==.Erodras:BAAANQADCgIIAgAAAA==.Erojin:BAAANQADCgYIBgAAAA==.Eroviaevia:BAAANQAECgIIBAAAAA==.',
Es='Esterossa:BAAANQADCgYICwAAAA==.',
Eu='Eunomia:BAABNQAECoEcAAIFAAcK/xQpKAC9AQAFAAcK/xQpKAC9AQAAAA==.',
Ev='Evilest:BAAANQAECgEIAQAAAA==.',
Ex='Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAAANQAECgcIDgAAAA==.Ezoghoul:BAABNQAECoEaAAIJAAgKDRSKaQAJAgAJAAgKDRSKaQAJAgAAAA==.',
Fa='Faeare:BAAANQADCgYJDAAAAA==.Faene:BAAANQADCgQIBAAAAA==.Faerion:BAAANQAECgEIAQAAAA==.Fakedemon:BAEANQADCgIIAgABNQAECgUICwADAAAAAA==.Fakelock:BAEANQADCgMIAwABNQAECgUICwADAAAAAA==.Fakendruid:BAEANQAECgUICwAAAA==.Fakewar:BAEANQADCgYIBgABNQAECgUICwADAAAAAA==.Fauxx:BAAANQADCggIIgAAAA==.',
Fd='Fdup:BAAANQAECgMJBAAAAA==.',
Fe='Felfae:BAAANQAECgIIAwAAAA==.Feverish:BAABNQAECoEYAAIWAAkKZQy3IAAgAgAWAAkKZQy3IAAgAgAAAA==.',
Fi='Filip:BAAANQAECgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCggJFAAAAA==.Florellia:BAAANQADCgQIBAAAAA==.Flumpy:BAABNQAECoEtAAIEAAkKpSOqBwCFAwAEAAkKpSOqBwCFAwAAAA==.Flurpymcdoof:BAAANQAECgcIBwAAAA==.',
Fo='Folken:BAAANQAECgYIDwAAAA==.Foodtruck:BAAANQAECgMIAwABNQAECgcICQADAAAAAA==.Forbiddyn:BAAANQAECgcIEAAAAA==.Fornacater:BAAANQADCgcIBwAAAA==.Foxiefoxy:BAAANQAECgIIAwAAAA==.',
Fr='Fraiser:BAAANQADCgYICgABNQAECggIIwAJAL4UAA==.Freylyn:BAAANQADCgUIBQAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funkweave:BAEANQAECgcIEwAAAA==.Fupacabras:BAAANQAECgcIDAAAAA==.Furidas:BAAANQAECgUIDQAAAA==.Fuse:BAAANQABCgIIAgAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Gaius:BAAANQABCgIIAgAAAA==.Gangreenanus:BAAANQADCgYICgAAAA==.Garogg:BAABNQAECoEhAAICAAgK0BISEQC4AQACAAgK0BISEQC4AQAAAA==.Garotomoreno:BAABNQAECoEkAAIPAAkK1RyvLgDQAgAPAAkK1RyvLgDQAgAAAA==.Garrut:BAABNQAECoEYAAMNAAgKryAlBQD3AgANAAgKryAlBQD3AgAXAAQKPgtNHADVAAAAAA==.Gaymr:BAAANQADCgIJAgAAAA==.',
Gi='Gigagrog:BAAANQAECgQIBQAAAA==.Giirthquakee:BAAANQAECgEIAQAAAA==.Gimick:BAAANQADCggICAABNQAECgYIEQADAAAAAA==.Gimmage:BAAANQAECgYIEQAAAA==.Gingebsham:BAAANQADCgcIBwABNQAECggIFwAOALkIAA==.Girlyouthicc:BAAANQAECgMIBAABNQAFFAYIEAATALMTAA==.Girthbrøøks:BAAANQADCgYIBgABNQAECgkJFwAQAKYTAA==.',
Gl='Glorbruid:BAAANQADCggIEgAAAA==.',
Go='Gojosatóru:BAAANQAECgQJCwAAAA==.Goldenchef:BAAANQADCgYIBgAAAA==.Gordatamara:BAAANQADCgEIAQAAAA==.Gordray:BAAANQAECgEIAQAAAA==.Gotcowbell:BAAANQAECgEIAQAAAA==.',
Gr='Grahnis:BAAANQAECgIIAgAAAA==.Grasswhistle:BAAANQAECgUICQABNQAECgkJIgAXAKUjAA==.Grayzor:BAAANQAECgUIBwAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAABNQAECoEZAAIKAAcKdxCxsQDTAQAKAAcKdxCxsQDTAQAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAABNQAECoEZAAMJAAgKCBq2VwBAAgAJAAgKCBq2VwBAAgAYAAEKYRGrJQA9AAAAAA==.Grigdor:BAABNQAECoEnAAMMAAkKDR3sEgDNAQALAAgKShzYLgCSAgAMAAYKVhvsEgDNAQAAAA==.Grimnativex:BAAANQADCgIIAgAAAA==.Gràcias:BAAANQADCgYIBgAAAA==.',
Gu='Guass:BAABNQAECoEkAAMZAAkKGx04EwAJAwAZAAkKGx04EwAJAwABAAEKaQMJYAAoAAAAAA==.Gumbyofgad:BAAANQADCgEIAQAAAA==.Gunbolt:BAAANQAECgMIBQAAAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgUIEQAAAA==.',
Ha='Habrosh:BAAANQAECgUIDwAAAA==.Hailrazor:BAAANQADCgIIAgAAAA==.Hairlock:BAAANQAECgUIBQABNQAECggIGQAOAHIdAA==.Hakiry:BAAANQAECgYIEAAAAA==.Haliburton:BAAANQADCgMIAwAAAA==.Haramhabibi:BAAANQADCgYIBgAAAA==.Harike:BAAANQAECgEIAQAAAA==.Hatrix:BAAANQADCgMIAwAAAA==.Haunt:BAAANQAECgYICgAAAA==.Havokhuntr:BAAANQADCgQIBAAAAA==.Hawkkaye:BAAANQAECgMIAwAAAA==.Hawkwardfall:BAAANQADCgYICAAAAA==.Haze:BAAANQAECgEIAgAAAA==.Hazesamaa:BAABNQAECoEyAAIaAAkKeRC6EABRAgAaAAkKeRC6EABRAgAAAA==.',
He='Healsforfree:BAAANQADCgIJAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIJAgAAAA==.Hernog:BAABNQAECoEYAAIQAAgK1Rp9LgCCAgAQAAgK1Rp9LgCCAgAAAA==.Hexmenixy:BAAANQAECgUIDAAAAA==.',
Hi='Hianu:BAAANQAECgYIEwAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.Hildalock:BAAANQADCggICAABNQADCggIEAADAAAAAA==.',
Ho='Holabenjy:BAAANQAECgQIDgAAAA==.Holybenjy:BAAANQAECgMIBAAAAA==.Holybibble:BAAANQADCgIIBAAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQAECgMIBAAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQAECgMJAwAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holysponge:BAAANQADCggJCAABNQAECgkJFQAKABIhAA==.Holyzyn:BAAANQAECgEIAQAAAA==.Hoonding:BAAANQADCgcIFQABNQAECgkJMgAaAHkQAA==.Hordak:BAAANQAECgEIAQAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQAECgIIAgAAAA==.Hottodot:BAABNQAECoEXAAIOAAgKuQgzZACNAQAOAAgKuQgzZACNAQAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAAANQAECgQICgAAAA==.',
Hu='Hudini:BAABNQAECoEtAAIKAAkK/hoqRwDSAgAKAAkK/hoqRwDSAgAAAA==.Hugs:BAAANQAECgMJAwAAAA==.Huntsmang:BAAANQADCgEJAQAAAA==.Hushweaver:BAAANQADCgQICgAAAA==.',
Hy='Hybridkaidou:BAAANQADCgMIAwAAAA==.Hypal:BAAANQAECgcIDwABNQAECgYICQADAAAAAA==.Hypd:BAAANQAECgYICQAAAA==.Hypev:BAAANQAECgcIDQABNQAECgYICQADAAAAAA==.Hypm:BAAANQAECgEIAQABNQAECgYICQADAAAAAA==.Hyps:BAABNQAECoEoAAMRAAkK+x11FgDtAgARAAkK+x11FgDtAgAQAAUKjg56lgAVAQABNQAECgYICQADAAAAAA==.Hypt:BAAANQAECggIEwABNQAECgYICQADAAAAAA==.',
Ia='Iakned:BAAANQAECgUICQABNQAECgcIDwADAAAAAA==.',
Ib='Ibichi:BAAANQADCgYIDwAAAA==.',
Ic='Icet:BAABNQAECoEgAAIaAAgKihSxEQBFAgAaAAgKihSxEQBFAgABNQADCggIDgADAAAAAA==.',
Il='Illshankya:BAAANQAECgIIAgAAAA==.',
Im='Imihn:BAAANQAECgUIBgAAAA==.',
In='Indàcouch:BAAANQABCgIIBAAAAA==.Invìctús:BAABNQAECoEYAAMbAAcK+RffCAD6AQAbAAcK+RffCAD6AQAKAAEKHAXfiwEyAAAAAA==.',
It='Ithir:BAAANQADCgcJDAAAAA==.Itsemma:BAAANQAECgYIEAAAAA==.',
Iu='Iustitia:BAAANQABCgYICQAAAA==.',
Iv='Ivieruem:BAAANQADCgUIDAAAAA==.',
Iy='Iylara:BAAANQAECgEIAQAAAA==.',
Iz='Izhira:BAAANQABCgMIAgAAAA==.',
Ja='Jaanus:BAAANQAECggICAAAAA==.Jackdalilguy:BAAANQADCgUIBQAAAA==.Jackodes:BAAANQAECgcIDAABNQAECgkJIQAKAKgjAA==.Jackodm:BAABNQAECoEhAAMKAAkKqCPQGgBYAwAKAAkKqCPQGgBYAwAbAAMKSRlHGADuAAAAAA==.Jad:BAABNQAECoEbAAIRAAgKGhnkLQBpAgARAAgKGhnkLQBpAgAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCggIEwAAAA==.Jarlam:BAAANQABCgcIDwABNQAECgcIEgADAAAAAA==.Jawa:BAAANQAECgEIAQABNQAECgcIEwADAAAAAA==.Jawo:BAAANQAECgcIEwAAAA==.',
Jb='Jboom:BAAANQAECgQIBQABNQAECgkJLgAFAKkbAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jersey:BAAANQADCgUIBQAAAA==.Jetts:BAABNQAECoEXAAIKAAgKABYVhwAzAgAKAAgKABYVhwAzAgAAAA==.',
Jf='Jfôrbj:BAAANQADCgQIBAABNQAECgkJLgAFAKkbAA==.',
Jo='Johnnysinz:BAABNQAECoEbAAIPAAcKchoRaQAGAgAPAAcKchoRaQAGAgAAAA==.Johnnyzyns:BAABNQAECoEXAAIQAAkKphM7NwBTAgAQAAkKphM7NwBTAgAAAA==.Johnret:BAAANQAECgUIBgABNQAECgUICgADAAAAAA==.',
Jp='Jp:BAACNQAFFIEPAAIcAAUKXybcAAAyAgAcAAUKXybcAAAyAgA1AAQKgR4AAhwACQpyJokAANUDABwACQpyJokAANUDAAAA.',
Ju='Juhla:BAAANQADCgUIBgAAAA==.Juno:BAAANQADCggIFwAAAA==.',
['Já']='Jáke:BAAANQAECgQIBAAAAA==.',
Ka='Kadester:BAAANQAECgEIAQAAAA==.Kaelwyn:BAAANQABCgIIAgAAAA==.Kaimen:BAAANQAECgUJBwAAAA==.Kainssoul:BAAANQADCgIIAgAAAA==.Kalipriest:BAAANQAECggIDgAAAA==.Kalipso:BAAANQAECgYIDgAAAA==.Kallea:BAAANQADCggICAAAAA==.Kalliz:BAAANQADCgYIBgAAAA==.Kamehameha:BAAANQAECgUIBQAAAA==.Kamwar:BAACNQAFFIEJAAMYAAUKvxeQAABpAQAYAAQKZBmQAABpAQAJAAIKjgyuIACQAAA1AAQKgSAAAxgACQr3JU4AAOADABgACQrxJU4AAOADAAkAAwo/IOrNAOYAAAAA.Karideer:BAAANQAECgUICQAAAA==.Karnaughm:BAAANQADCgUIAQAAAA==.Kataraxtis:BAAANQAECgQIBAAAAA==.Kaylax:BAAANQAECgUIBwAAAA==.Kaylost:BAAANQADCgMIBAAAAA==.Kaylub:BAABNQAECoEYAAILAAcKDhJWagDIAQALAAcKDhJWagDIAQAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQAECgMIBAAAAA==.Kenott:BAAANQAECgIIAgAAAA==.Kenparcell:BAAANQAECgIIAgAAAA==.Kerash:BAAANQADCggIIwAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevindrd:BAAANQAECgUIBQABNQAECggIGQAdAKkWAA==.Kevintt:BAABNQAECoEZAAMdAAgKqRbvFgDvAQAdAAgKqRbvFgDvAQAIAAQKugnLsgDIAAAAAA==.Keys:BAAANQAECgQICQAAAA==.',
Kh='Kho:BAAANQAECgIIBAABNQAECgUICAADAAAAAA==.Khodad:BAAANQAECgIIAgABNQAECgUICAADAAAAAA==.Khundalar:BAAANQAECgUIBQAAAA==.',
Ki='Kiarraa:BAAANQAECgIIAgAAAA==.Killachefcjr:BAAANQADCgcIFQAAAA==.Kimi:BAAANQADCgYIBgAAAA==.Kimori:BAAANQADCgUIBQAAAA==.Kinzee:BAAANQAECgUIBwAAAA==.Kittyvalk:BAAANQADCgQIBAAAAA==.',
Kn='Knugget:BAAANQAECgYICgAAAA==.',
Ko='Kodiakhunter:BAAANQAECgUIBQAAAA==.Kodlighting:BAAANQAECgEIAQAAAA==.Komatsu:BAAANQADCgEIAQAAAA==.Koniqeo:BAAANQAECgEIAQAAAA==.Koressme:BAAANQADCggIEwAAAA==.Korlat:BAAANQAECgMJAwAAAA==.Kozdiniar:BAABNQAECoEnAAMZAAkKcyTaCABzAwAZAAkKcyTaCABzAwABAAYKVyHBFwAzAgAAAA==.Kozurai:BAAANQAECgUIBQABNQAECgkJJwAZAHMkAA==.',
Kr='Krimzin:BAAANQAECgEIAQABNQAFFAQICQAEALsWAA==.Kringles:BAAANQAECgIIAgAAAA==.Kristree:BAAANQADCgMIBQAAAA==.Krëegz:BAABNQAECoEXAAIEAAkKrhDrTwAxAgAEAAkKrhDrTwAxAgAAAA==.Krëëgz:BAAANQADCgEIAQABNQAECgkJFwAEAK4QAA==.',
Kt='Ktala:BAAANQAECgEIAQAAAA==.',
Ku='Kugot:BAAANQAECgQIBAAAAA==.Kurupted:BAAANQAECgQICgAAAA==.',
Ky='Kydrea:BAAANQAECgIIAwAAAA==.Kyne:BAAANQAECgUIBwAAAA==.Kynyselda:BAAANQAECgQJBAAAAA==.Kyrabear:BAAANQAECgEIAgAAAA==.',
['Kâ']='Kânê:BAABNQAECoEXAAIPAAcKLyA5TgBbAgAPAAcKLyA5TgBbAgAAAA==.',
La='Ladrón:BAAANQADCgYIDAAAAA==.Larayviana:BAAANQAECgEIAQAAAA==.Larc:BAAANQAECgEIAgAAAA==.Larkos:BAAANQADCgcJCAAAAA==.Lassamyna:BAAANQAECgEJAQAAAA==.Latías:BAABNQAECoEbAAIKAAkKFh2VTgC9AgAKAAkKFh2VTgC9AgAAAA==.',
Le='Leechygos:BAAANQADCggIFQAAAA==.Legenddairy:BAAANQAECgIIBAAAAA==.Legirlas:BAAANQADCgQIBAABNQAECgUIBQADAAAAAA==.Leha:BAAANQADCgEIAQAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAABNQAECoEaAAIRAAgKhxheMgBTAgARAAgKhxheMgBTAgAAAA==.Lenorand:BAAANQADCgcIDQABNQAECgMIBQADAAAAAA==.Leushi:BAAANQADCgcIBwAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyarrows:BAAANQAECgQIBAABNQAECggIIAAVAGYaAA==.Lickmyhorns:BAABNQAECoEgAAMVAAgKZho2HABxAgAVAAgKZho2HABxAgAeAAYKkhC7NgBDAQAAAA==.Liendrah:BAECNQAFFIEFAAIfAAMKTh12AQANAQAfAAMKTh12AQANAQA1AAQKgSAAAh8ACQpzIBgCAD0DAB8ACQpzIBgCAD0DAAAA.Lightbeer:BAAANQABCgMIBQAAAA==.Lightmf:BAAANQAECgcIEQAAAA==.Lightninglip:BAAANQADCgcIFQAAAA==.Lightnleaf:BAAANQAECgEIAQAAAA==.Lightorange:BAAANQAECgEIAgAAAA==.Lightwaves:BAAANQAECgUICwAAAA==.Lilet:BAAANQAECgYIEwAAAA==.Lilitsune:BAAANQAECgMIBAAAAA==.Linareyna:BAAANQADCgIIAgAAAA==.Liotrix:BAAANQADCgYIBgABNQAECggIFgAEACccAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgYIDgAAAA==.Lizolio:BAAANQAECgYICgAAAA==.',
Ll='Llomel:BAAANQAECgEIAQAAAA==.',
Lo='Lochlan:BAAANQADCggIDwAAAA==.Lohhano:BAAANQABCggIDgAAAA==.Londo:BAAANQADCgYIDAAAAA==.Louanna:BAAANQADCgYIBwAAAA==.',
Lu='Lucianagi:BAAANQAECgYIDAAAAA==.Lucilla:BAAANQADCgUIBQAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcIDgAAAA==.',
Ly='Lynavas:BAAANQADCgcIDAAAAA==.',
['Là']='Làgs:BAAANQAECgYIBwAAAA==.',
Ma='Machiné:BAAANQAECgEIAQAAAA==.Macnaulty:BAAANQADCggIBgAAAA==.Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAABNQAECoEhAAIOAAkKryJkBQCDAwAOAAkKryJkBQCDAwAAAA==.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Maibutzfel:BAAANQADCggICQAAAA==.Majamojopowa:BAAANQABCgcIBwAAAA==.Majicman:BAAANQAECgQIBwAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manimal:BAAANQADCgcIDQABNQAECgYIDwADAAAAAA==.Mankrikswife:BAAANQADCggICAABNQAECgUIDQADAAAAAA==.Manutters:BAAANQAECgQICgAAAA==.Marrylanders:BAABNQAECoFBAAMKAAkKySQnCACwAwAKAAkKySQnCACwAwAbAAIKlSB5HQDBAAAAAA==.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAABNQAECoEuAAMFAAkKqRthDwDLAgAFAAkKYxthDwDLAgAEAAIKNhFQ+AB9AAAAAA==.Mastayoda:BAAANQABCgMIAwAAAA==.Mayven:BAAANQADCgUICgAAAA==.',
Mc='Mcboomii:BAAANQADCggICAAAAA==.',
Me='Megapally:BAAANQADCgQJBAAAAA==.Mellie:BAAANQADCgcICgAAAA==.Melmei:BAAANQAECgQICAAAAA==.Mephixto:BAAANQAECgQICwAAAA==.Meriweather:BAAANQAECgQJBAAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Mertlek:BAAANQAECgUICQABNQAECgkJLgAFAKkbAA==.Meszyra:BAABNQAECoEoAAIgAAkKVBvJBwDZAgAgAAkKVBvJBwDZAgAAAA==.Meudäil:BAAANQAECgEIAQAAAA==.',
Mg='Mgreenleaf:BAAANQABCgUIDgAAAA==.',
Mi='Michaelcera:BAABNQAECoEcAAIQAAgKqyDFGgD7AgAQAAgKqyDFGgD7AgAAAA==.Mijuku:BAABNQAECoEmAAIHAAkK4h3QEwDlAgAHAAkK4h3QEwDlAgAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Minusgreen:BAAANQADCgYIBQAAAA==.Misoeternal:BAAANQAECgQICAAAAA==.Mistafista:BAAANQAECgIIAgAAAA==.Mistralis:BAAANQAECgQIBAABNQAECgkJFQAKABIhAA==.Mitchard:BAABNQAECoEdAAIhAAgKdgq8NQCVAQAhAAgKdgq8NQCVAQAAAA==.Mittenza:BAAANQADCggIFgAAAA==.Mixelplix:BAAANQAECgMJAwAAAA==.Mizstriss:BAAANQAECgUIBwAAAA==.',
Mo='Molari:BAAANQAECgMIBAAAAA==.Moloyagi:BAAANQABCgIIAgAAAA==.Monksymeg:BAAANQADCgIIAgAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Monterce:BAAANQADCgIIAgAAAA==.Moonfur:BAAANQAECgMIBQAAAA==.Mooseknuck:BAAANQADCgMIAwAAAA==.Mordath:BAAANQAECgIIBAAAAA==.Mordetkai:BAAANQADCgYIBgAAAA==.Mordoom:BAAANQAECgQICQAAAA==.Morikai:BAAANQAECgUIBgAAAA==.Morinn:BAAANQADCgcIDAAAAA==.Mosag:BAABNQAECoEZAAMOAAgKch3JQgAVAgAOAAcK6RzJQgAVAgATAAYK9h4yHwD1AQAAAA==.Moushou:BAAANQAECgYIEQAAAA==.',
Ms='Mspacman:BAAANQAECgMIAwAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAABNQAECoEiAAIQAAkKVB3MGQADAwAQAAkKVB3MGQADAwAAAA==.Muppie:BAAANQADCgQIBQAAAA==.Mutovenator:BAAANQAECgQIBQAAAA==.',
My='Mychef:BAAANQADCgUIBQAAAA==.Myrrha:BAABNQAECoEgAAMgAAkKjiKIAwBQAwAgAAkKjiKIAwBQAwAiAAYKwRODHgCkAQAAAA==.',
['Mî']='Mîchael:BAAANQADCgIIAgAAAA==.',
['Mï']='Mïsterfox:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônah:BAAANQADCgYICgABNQADCggIEAADAAAAAA==.',
Na='Nahota:BAAANQABCgIIAgAAAA==.Nakiro:BAAANQAECgQIBAAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICwAAAA==.',
Ne='Necroussy:BAAANQAECggIAgAAAA==.Nedilap:BAAANQAECgcIDwAAAA==.Nef:BAAANQAECgQICAAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdchillpal:BAAANQADCgYIBgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQAECgQICAAAAA==.Nerve:BAAANQAECgUICQAAAA==.',
Ni='Nightx:BAABNQAECoEVAAMHAAYKahswOgDXAQAHAAYKahswOgDXAQAhAAEKHg4GgQA5AAAAAA==.Ninn:BAAANQADCgYIBgAAAA==.Nishkavel:BAAANQADCgUICQAAAA==.Nitewang:BAAANQAECggIDgAAAA==.Nitewing:BAACNQAFFIESAAIdAAYKaR84AQAZAgAdAAYKaR84AQAZAgA1AAQKgScAAh0ACQpZJg0BAMwDAB0ACQpZJg0BAMwDAAE1AAQKCAgOAAMAAAAA.Niza:BAAANQABCgYIDAAAAA==.',
No='Noccs:BAAANQADCggIDQAAAA==.Noctaro:BAEBNQAECoEdAAIiAAkKpBU+EAB4AgAiAAkKpBU+EAB4AgAAAA==.Nokona:BAAANQADCggIEAAAAA==.Notpizza:BAAANQAECgMIAwABNQAFFAUIBwAKAEcKAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAECgkJIgAQAFQdAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
Ob='Obnixa:BAABNQAECoEdAAIEAAgK3iB1HwDjAgAEAAgK3iB1HwDjAgAAAA==.Obnixlis:BAAANQADCgYIBgAAAA==.',
Od='Ody:BAAANQAECgEIAQAAAA==.',
Og='Ogakal:BAAANQABCggIGQAAAA==.',
Oh='Ohsora:BAAANQADCgcIBwAAAA==.',
Ol='Oldstorm:BAAANQADCgEIAQABNQAECggIGgARAIcYAA==.',
On='Onfiree:BAAANQAECggJCwAAAA==.',
Op='Opithel:BAABNQAECoEhAAIeAAgKoSWFBQBrAwAeAAgKoSWFBQBrAwAAAA==.Opiurza:BAAANQAECggIDAABNQAECggIIQAeAKElAA==.Opizerka:BAAANQAECgcJEgABNQAECggIIQAeAKElAA==.',
Or='Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAAANQAECgcIEQAAAA==.Oríllas:BAAANQAECgQICAAAAA==.',
Os='Osric:BAAANQADCgIIAgABNQAECggIGQAOAHIdAA==.',
Oy='Oyogo:BAACNQAFFIENAAIiAAcKwBU4AgBSAgAiAAcKwBU4AgBSAgA1AAQKgR8AAiIACQoQIk0FAEADACIACQoQIk0FAEADAAAA.Oyogu:BAAANQADCgUIBQABNQAFFAcIDQAiAMAVAA==.Oyumi:BAAANQAFFAIIAgABNQAFFAcIDQAiAMAVAA==.',
Pa='Paech:BAAANQADCgYIDAAAAA==.Pairädice:BAAANQADCgYIDAAAAA==.Paladane:BAAANQAECgMIBQAAAA==.Palakreegz:BAAANQADCgUJAwABNQAECgkJFwAEAK4QAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQAECgIIAwAAAA==.Pamalinaa:BAAANQAECgQICAAAAA==.Pamplemousse:BAAANQAECggIBgAAAA==.Pandadave:BAAANQADCgUIDQAAAA==.Papanezz:BAAANQAECgQIBgAAAA==.Papasin:BAAANQAECggICAAAAA==.Patapouf:BAAANQAECgIIBQAAAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQAECgMIBAAAAA==.Pegully:BAAANQAECgYIEAAAAA==.Pewxtwo:BAAANQADCgYJBwAAAA==.',
Ph='Phephraan:BAAANQAECgcIEgAAAA==.Phinehas:BAAANQAECgMIAwAAAA==.Phwaz:BAAANQAECgQICAAAAA==.Phyxyzin:BAAANQADCgUIDQAAAA==.',
Pi='Piccoloo:BAAANQAECgIIAgAAAA==.Piddles:BAAANQADCgYJBgAAAA==.Pikeysham:BAAANQADCgMJAwAAAA==.Pinchebean:BAAANQAECgUICgAAAA==.Pinktress:BAAANQAECgUIEQAAAA==.Pizzadough:BAACNQAFFIEHAAIKAAUKRwpeFAB8AQAKAAUKRwpeFAB8AQA1AAQKgR0AAgoACQo6GY1kAIUCAAoACQo6GY1kAIUCAAAA.Pizzapurse:BAAANQADCgQIBAAAAA==.',
Pk='Pkcontrol:BAAANQADCgUIBQAAAA==.',
Pl='Plavalagoona:BAAANQADCgMIBAABNQAECggIGgAJAA0UAA==.Plskillmie:BAABNQAECoEZAAMhAAcKowQUUgDiAAAhAAcKAgMUUgDiAAAHAAYKkgTIcgDdAAAAAA==.',
Po='Pocahontis:BAAANQABCgIIAgAAAA==.Politics:BAAANQAECggIBgAAAA==.Polygonnacry:BAAANQAECgIJAgAAAA==.Popatop:BAAANQADCgcICwAAAA==.Possecutor:BAACNQAFFIEOAAITAAQKnxboBgBPAQATAAQKnxboBgBPAQA1AAQKgSQAAhMACQqCH2ILAAcDABMACQqCH2ILAAcDAAAA.Pownadin:BAAANQADCgUICgAAAA==.',
Pr='Prabis:BAAANQAECgQIBAAAAA==.Praesidius:BAAANQADCgcIDAAAAA==.Priestalama:BAAANQADCgUIBQAAAA==.Priestsita:BAAANQAECgIIAgAAAA==.Promise:BAAANQAECgQIBAAAAA==.Pryîto:BAAANQAECgUIBwAAAA==.',
Pu='Pumachaka:BAAANQAECgQIBwAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Py='Pyresia:BAAANQAECgQIBgAAAA==.Pyrocity:BAAANQADCgYIBgAAAA==.',
Qu='Quackshot:BAABNQAECoEeAAQEAAgKIyR8DQBQAwAEAAgKIyR8DQBQAwAGAAQK8xv2CABOAQAFAAEKTReobgAzAAAAAA==.',
Qw='Qwertysquid:BAAANQADCgMIBAAAAA==.',
Ra='Rads:BAAANQABCgEIAQAAAA==.Raegen:BAEANQAECggIAQABNQAECgkJHQAiAKQVAA==.Raezer:BAEANQADCggICAABNQAECgkJHQAiAKQVAA==.Raiin:BAAANQAECgEIAQABNQAFFAYIEAATALMTAA==.Raikomori:BAAANQAECgYIBgAAAA==.Ralroc:BAAANQADCgcIEAAAAA==.Ranare:BAAANQAECgcIDQAAAA==.Randomfatguy:BAAANQAECgEIAQAAAA==.Rathrus:BAAANQAECgQICwAAAA==.Ratonfusse:BAAANQABCgQIBAAAAA==.Ravenhart:BAAANQAECgcICgAAAA==.Ravienn:BAAANQAECgEJAQABNQAECgkJLgAFAKkbAA==.Raxmanus:BAAANQAECgEJAQAAAA==.Rayru:BAAANQAECgIIAgAAAA==.Rayvienne:BAAANQADCgUIBwAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQAECgQIBgAAAA==.Reilini:BAABNQAECoEkAAIPAAkKphz1LgDPAgAPAAkKphz1LgDPAgAAAA==.Remedium:BAAANQABCgYICwAAAA==.Renascor:BAAANQAECgQICgABNQAFFAQICAAgAOINAA==.Reàp:BAAANQADCgMIAwAAAA==.',
Rh='Rhojin:BAAANQADCggIFgAAAA==.',
Ri='Rikimaruu:BAAANQAECggIEQAAAA==.Rinaari:BAAANQADCgUIBQAAAA==.Rinsecycle:BAAANQADCggICAAAAA==.Rivelia:BAAANQAECgIIAwABNQAECgkJIAAgAI4iAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQAECgIIBAAAAA==.Ronek:BAAANQABCgUIBwAAAA==.Rosabella:BAAANQADCgQJBAAAAA==.Roshisain:BAAANQADCgcICgAAAA==.Rouñders:BAAANQAECgEIAgABNQAFFAYIEAATALMTAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAABNQAECoEeAAIKAAgKXxnWbwBqAgAKAAgKXxnWbwBqAgAAAA==.Rueldalf:BAAANQADCggIHgAAAA==.Ruïn:BAAANQADCggIGgAAAA==.',
['Ré']='Réka:BAAANQADCgUICAABNQAECgcIDwADAAAAAA==.',
['Rô']='Rôôst:BAAANQADCgIIAgAAAA==.Rôôstêr:BAAANQADCgQIBAAAAA==.',
Sa='Sagittarius:BAAANQADCgQIBAAAAA==.Saino:BAAANQAECgEIAQAAAA==.Salidan:BAAANQADCgMIAwAAAA==.Salt:BAAANQAECgYIBwABNQAECggIFAAWAGYXAA==.Samlock:BAABNQAECoEoAAIMAAkKph71AQA9AwAMAAkKph71AQA9AwAAAA==.Sap:BAACNQAFFIEJAAQaAAUKDwzHCAD+AAAaAAMKTg7HCAD+AAAWAAIK3QcwDACiAAAjAAEKxAYhAwBGAAA1AAQKgR4ABBYACQrRH0wIACMDABYACQrEH0wIACMDACMABgovF7wLAHMBABoAAwqJD485AKQAAAE1AAQKCAgWAAkAVCUA.Satyrlord:BAAANQAECgMJAwAAAA==.Savella:BAAANQAECgYIDQAAAA==.',
Sc='Scaleshot:BAAANQADCgYJBgAAAA==.Scarletblade:BAABNQAECoEiAAMPAAkKMB5FKQDoAgAPAAkKGB5FKQDoAgAdAAMKbRsjNgDcAAAAAA==.Schamwoww:BAAANQAECgMIAwAAAA==.Schlam:BAAANQADCggICAAAAA==.Sclas:BAAANQAECgEIAQAAAA==.Scubar:BAAANQAECgQICAAAAA==.',
Se='Seafox:BAAANQAECgIJAgAAAA==.Sear:BAABNQAECoEfAAIeAAgKaRrpFwBtAgAeAAgKaRrpFwBtAgAAAA==.Selest:BAAANQADCgEIAQAAAA==.Selindris:BAAANQAECgUIBQAAAA==.Selkets:BAAANQADCgUIBQAAAA==.Selkola:BAAANQABCggIDwAAAA==.Sephimus:BAAANQADCgYIBgABNQAECggIGgAUANkgAA==.Seraphiina:BAAANQAECgYIEwAAAA==.Seraphimn:BAAANQADCgEIAQAAAA==.Serbixalot:BAAANQAECgUIDgAAAA==.',
Sh='Shadowbinder:BAAANQADCggICAAAAA==.Shadowyclaws:BAAANQADCgEIAQAAAA==.Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgUIBgAAAA==.Shataree:BAAANQADCgcICwAAAA==.Shineup:BAAANQADCggIEAAAAA==.Shintetsu:BAAANQADCggIDQAAAA==.Shockkor:BAAANQADCgcIDgAAAA==.Shockujin:BAAANQAECgIIAgABNQAECgkJIgAIAMsUAA==.Shox:BAAANQADCgMIAwAAAA==.Shredder:BAAANQAECgEIAQABNQAECgcICQADAAAAAA==.Shý:BAAANQADCgIIAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sitaana:BAAANQAECgQICAAAAA==.',
Sk='Skellek:BAAANQADCggICAAAAA==.Skillr:BAAANQAECgcIDwAAAA==.Skyekníght:BAAANQAECgIIAgAAAA==.Skysong:BAAANQAECgQIBAABNQAECgkJIgAXAKUjAA==.',
Sl='Slaa:BAAANQADCgMIAwAAAA==.Sleezyaf:BAABNQAECoEbAAQLAAcKGhSJewCUAQALAAYKFRSJewCUAQAMAAMKLAuJQQCoAAASAAEKfxRbJgA4AAAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAABNQAECoEXAAMYAAgKMh6rBwAlAgAYAAcKQBurBwAlAgAJAAcKKBf2jACgAQAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQAECgMIBQAAAA==.',
So='Soapyy:BAAANQADCgUIBQAAAA==.Socketss:BAAANQAECgEIAQAAAA==.Sohjinra:BAAANQAECgMIBQAAAA==.Sollaria:BAAANQADCgYICQAAAA==.Sololvlin:BAAANQADCgYIDAAAAA==.Sololvling:BAABNQAECoEYAAIQAAYKgRk0WgDDAQAQAAYKgRk0WgDDAQAAAA==.Sovereign:BAACNQAFFIEPAAIPAAUKKhP+BQCfAQAPAAUKKhP+BQCfAQA1AAQKgSgAAg8ACQqoIboaAC8DAA8ACQqoIboaAC8DAAAA.',
Sp='Sp:BAAANQAECggIAQAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spicy:BAAANQAECgEIAQAAAA==.Splashaxuss:BAAANQADCgUICAAAAA==.Spookyloops:BAAANQAECggICQAAAA==.Sproggles:BAAANQAECgEIAQAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQABNQAECgUICwADAAAAAA==.',
St='Stealthfire:BAABNQAECoEiAAIXAAkKpSNMAQClAwAXAAkKpSNMAQClAwAAAA==.Sterny:BAAANQAECgQICQAAAA==.Stidetroll:BAAANQAECgUIBgAAAA==.Stnnisbrthon:BAAANQADCgQIBAAAAA==.Stormstrikes:BAAANQAECgQIBQAAAA==.Strongw:BAAANQAECggIEAAAAA==.Stul:BAAANQAECgcIEwAAAA==.',
Su='Substandard:BAAANQAECgYICQAAAA==.Sugaboomboom:BAAANQAECgEIAQAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sumwon:BAAANQAECgYIDgAAAA==.Sunarr:BAABNQAECoEfAAIPAAkKExwnLADcAgAPAAkKExwnLADcAgAAAA==.Sunkenlily:BAAANQADCgcIDAAAAA==.Superace:BAACNQAFFIEFAAIQAAMKjwRDEwDLAAAQAAMKjwRDEwDLAAA1AAQKgR4AAhAACQpBF6QrAJICABAACQpBF6QrAJICAAAA.Surlee:BAAANQADCggIDAAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQAECgUICAAAAA==.',
Sw='Swaggernaut:BAAANQAECgMIBQAAAA==.Swiffys:BAAANQAECgcIEwAAAA==.Swissy:BAAANQADCgQIBwAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Syix:BAAANQADCgUIBQAAAA==.Synkadevour:BAAANQAECgQIBQABNQAECgUIDgADAAAAAA==.Synkapriest:BAAANQAECgUIDgAAAA==.Synkareaper:BAAANQADCgQIBgABNQAECgUIDgADAAAAAA==.Synxzc:BAAANQADCgUIBQAAAA==.',
Ta='Taappy:BAAANQAECgQICgAAAA==.Tacostuffing:BAAANQADCgYICAAAAA==.Taggs:BAAANQAECgYIEgAAAA==.Taggsy:BAAANQAECgcIBwAAAA==.Tail:BAAANQAECgYIDAAAAA==.Tails:BAAANQADCgYIEQAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQAECgQICgAAAA==.Tanthora:BAAANQADCgYICQAAAA==.Tao:BAAANQADCgMIAwAAAA==.Tastyfísh:BAAANQADCggICAAAAA==.',
Te='Teddymouse:BAAANQAECggICQAAAA==.Tenebris:BAAANQADCgUIBgAAAA==.',
Th='Thanatóz:BAABNQAECoEkAAMHAAkK5h8RFwDJAgAHAAkK5h8RFwDJAgAhAAEK7w/KgwA0AAAAAA==.Thasper:BAAANQABCgMIAwAAAA==.Thebigkodiak:BAAANQADCggIDgAAAA==.Thebutler:BAAANQAECggIEQABNQAFFAYIEAATALMTAA==.Thegrimus:BAABNQAECoEiAAIkAAkK4iFQAgB6AwAkAAkK4iFQAgB6AwAAAA==.Thekeres:BAAANQAECgMIAwAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Thorsten:BAAANQAECgIIAgABNQAECgcICgADAAAAAA==.Thrashley:BAAANQADCggICAAAAA==.Throh:BAAANQADCgUIBwAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Timøthy:BAAANQAECgcIDwAAAA==.Tismtouched:BAAANQADCgQICAAAAA==.',
Tk='Tkaniaa:BAAANQADCgQIDwAAAA==.',
To='Tokeyes:BAAANQAECgUICQAAAA==.Toost:BAAANQAECgUICQAAAA==.Torwa:BAAANQAECgIIBQAAAA==.Tossdirt:BAACNQAFFIEMAAMQAAYKrBvAAgAoAgAQAAYKrBvAAgAoAgARAAEKqAZBIABHAAA1AAQKgSIAAxAACQqUJcoEALgDABAACQqUJcoEALgDABEAAQoKCHL2ACUAAAAA.Toxle:BAAANQAECgEJAwAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trakshot:BAECNQAFFIEQAAMEAAYK9BDiAgDtAQAEAAYKnw/iAgDtAQAGAAEKmg6OAQBVAAA1AAQKgRwAAwQACQq+IIYVABkDAAQACQq+IIYVABkDAAYAAwoFGnkKAP8AAAE1AAQKCAgdAAQAeRgA.Trippdaddy:BAAANQAECgIIAgAAAA==.Truefaith:BAAANQAECgEIAQAAAA==.',
Ts='Tserendolgor:BAAANQABCgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgYIBwAAAA==.Tullegol:BAAANQAECgIIAgAAAA==.Tunasut:BAAANQADCgcIBwAAAA==.',
Tw='Twinswords:BAAANQAECgEJAQAAAA==.Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgQIBAAAAA==.',
Ty='Typhal:BAABNQAECoEdAAIPAAgKyCK9JAD9AgAPAAgKyCK9JAD9AgAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
['Té']='Téllah:BAAANQADCgYJBgAAAA==.',
Uh='Uhtain:BAAANQAECgQIBQABNQAECgMIAwADAAAAAA==.Uhtan:BAAANQAECgUICQABNQAECgMIAwADAAAAAA==.',
Un='Uncleklaus:BAABNQAECoEiAAIPAAgKSSDANQCzAgAPAAgKSSDANQCzAgAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unicornfartz:BAAANQADCggICAAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQAECgYJDAAAAA==.',
Us='Ushiamdi:BAABNQAECoEiAAINAAgKGx+iBgDBAgANAAgKGx+iBgDBAgAAAA==.',
Ut='Utaan:BAAANQAECgMIAwAAAA==.',
Va='Vaduh:BAAANQADCgQIBAAAAA==.Vaerenaris:BAAANQADCgEIAQAAAA==.Vaiel:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Valanthé:BAAANQADCgYIEAAAAA==.Vandrey:BAAANQAECgEIAQAAAA==.Vazen:BAAANQADCggIFQAAAA==.',
Ve='Velarasta:BAAANQADCgYIDQAAAA==.Veluna:BAAANQABCgMIAwABNQAECgcIGgAIAAgiAA==.Veravvang:BAAANQAECgQIBwABNQAECgQIBAADAAAAAA==.Verdereina:BAAANQADCgcIBwAAAA==.Veroshia:BAAANQADCggIGwAAAA==.Vexea:BAAANQAECgQICgABNQAECggIFAAWAGYXAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vi='Vinee:BAAANQADCgcJBwABNQAECggIIgAEAJghAA==.Vinladen:BAAANQADCgMIAwABNQAECggIFgAWAPkdAA==.Violettcloud:BAAANQAECgMIBAABNQAECggIKgAZAD4jAA==.Virali:BAABNQAECoEcAAIdAAgKfBMjHACxAQAdAAgKfBMjHACxAQAAAA==.Virussuckss:BAAANQADCgYIBgAAAA==.Vispper:BAAANQAECgUIEgAAAA==.Vixenvalk:BAAANQADCgMIAwAAAA==.Viyinx:BAAANQAECgQIBAABNQAECgkJJAAHAOYfAA==.Vizuel:BAAANQADCgUIDwABNQAECgIIAgADAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Vorel:BAAANQAECgQIBAAAAA==.',
Vp='Vpung:BAAANQAECgQIBwAAAA==.',
Vy='Vyllin:BAABNQAECoEiAAIdAAkK/R0pCADoAgAdAAkK/R0pCADoAgAAAA==.Vynarran:BAAANQAECgYIDwAAAA==.Vynlann:BAAANQADCgQIBAAAAA==.',
Wa='Warob:BAAANQAECggICQAAAA==.Warringmyer:BAAANQAECgUIDQAAAA==.Warriorlol:BAABNQAECoEWAAIJAAgKVCUgHAAoAwAJAAgKVCUgHAAoAwAAAA==.Watchdodo:BAAANQAECgQICQAAAA==.Wax:BAAANQAECgMJAgAAAA==.',
We='Weebscum:BAABNQAECoEhAAIPAAkKehQHXgAoAgAPAAkKehQHXgAoAgAAAA==.',
Wi='Wiket:BAAANQABCgQIBAAAAA==.Wildestspice:BAABNQAECoEWAAMZAAkKQhE4MgAKAgAZAAgKqBI4MgAKAgABAAUKcw8vMAAxAQABNQAFFAUICwAIAMMXAA==.Willowblessu:BAABNQAECoEsAAIlAAkKRxxpAQAcAwAlAAkKRxxpAQAcAwAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQAECgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQADCgYIDQAAAA==.Woodglue:BAAANQADCggICAAAAA==.Worgarg:BAAANQAECgEIAQAAAA==.Wovenxlight:BAAANQAECgQIBAAAAA==.',
Wr='Wranglep:BAAANQADCggIEQAAAA==.Wrathin:BAAANQAECgQIBAAAAA==.Wrayvin:BAAANQABCgEIAQAAAA==.',
Wu='Wufel:BAAANQAECgYJCQAAAA==.',
Xa='Xaeora:BAAANQAECgcIEgAAAA==.Xawne:BAAANQADCgQIBgAAAA==.',
Xe='Xeona:BAAANQADCgYJFAAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Ya='Yadhnak:BAAANQADCgQIBAAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yemii:BAAANQAECgMIAgAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yi='Yikes:BAAANQADCgEIAQAAAA==.',
Yo='Yorichef:BAAANQADCgMIAwAAAA==.Yoshikawa:BAEBNQAECoEmAAMQAAkKYSBVEABLAwAQAAkKYSBVEABLAwARAAQK/QTBrwC3AAABNQAECgkJIAAZAM4UAA==.',
Yr='Yrac:BAAANQADCgYICQABNQAECgEIAQADAAAAAA==.',
Ys='Ysora:BAAANQADCgMIAwAAAA==.',
Za='Zaivama:BAAANQAECgMIAwAAAA==.Zandren:BAAANQADCgYICgAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAABNQAECoEVAAMKAAkKEiG+NwD8AgAKAAkKEiG+NwD8AgAbAAIKIhcwIwCSAAAAAA==.',
Ze='Zeenaheals:BAAANQAECgcICQAAAA==.Zeenalizard:BAAANQAECgYIDwABNQAECgcICQADAAAAAA==.Zegoo:BAAANQAECgcIDAAAAA==.Zendezit:BAAANQAECgQIBgAAAA==.Zenet:BAAANQAECgUIBQAAAA==.Zenthura:BAAANQADCgIIAgABNQAECgkJFQAKABIhAA==.Zenïca:BAAANQADCgYJDwAAAA==.Zewz:BAAANQAECggIAQAAAA==.',
Zi='Zimbadah:BAAANQAECgEJAQAAAA==.',
Zn='Znny:BAABNQAECoEfAAIYAAkKphdQBACmAgAYAAkKphdQBACmAgAAAA==.',
Zy='Zynling:BAAANQABCgUIBQAAAA==.Zynpouch:BAABNQAECoEnAAMLAAkKnCE+HQDfAgALAAgKpiE+HQDfAgAMAAQKBx5FJAA7AQAAAA==.Zyrb:BAAANQADCggICwAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Ár']='Árthas:BAAANQAECgMIAwAAAA==.',
['Âr']='Ârthas:BAAANQAECgUIBwAAAA==.',
['Çl']='Çlutch:BAAANQADCgUIBQAAAA==.',
['Çr']='Çrimes:BAAANQAECgcIDwAAAA==.',
['Çu']='Çutty:BAAANQAECggIDAAAAA==.',
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
