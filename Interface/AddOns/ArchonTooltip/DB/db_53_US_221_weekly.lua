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

local lookup = {'Druid-Restoration','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Unholy','Warrior-Arms','Mage-Arcane','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Druid-Feral','Druid-Balance','Rogue-Subtlety','Mage-Frost','Monk-Mistweaver','Warrior-Fury','Paladin-Protection','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Devastation','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Priest-Discipline',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaliyah:BAABNQAECoEeAAIBAAkKhhjTCwCuAgABAAkKhhjTCwCuAgAAAA==.',
Ab='Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQAECgIJAgAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQADCggJJgABNQAECggJGAACAB4WAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgQJBgADAAAAAA==.',
Ag='Aggressor:BAAANQADCgMIAwAAAA==.Aggrocrack:BAAANQAECgYIDQAAAA==.Agliam:BAAANQAECgEJAgAAAA==.',
Ah='Ahngus:BAAANQAECgUJCQAAAA==.',
Ai='Air:BAAANQAECgQIBwAAAA==.',
Al='Alakander:BAAANQAECgIIAwAAAA==.Alexcrowley:BAAANQADCgYJCQAAAA==.Alexdh:BAAANQADCgYIBwABNQAFFAUICAAEAG0eAA==.Alexdruids:BAAANQAECgUIBQABNQAFFAUICAAEAG0eAA==.Alexhunt:BAACNQAFFIEIAAQEAAUKbR4EAwCqAQAEAAQKJyQEAwCqAQAFAAEKhAdFAQBRAAAGAAEK/Qz9EwBQAAA1AAQKgRoABAQACQrFIt4YAOUCAAQACAooI94YAOUCAAYABQrjHNsrAGABAAUAAQr8INkLAF8AAAAA.Alexpaladin:BAAANQAECgUIBQABNQAFFAUICAAEAG0eAA==.Alplarn:BAAANQAECgQIBgAAAA==.Althsar:BAAANQADCgEIAQAAAA==.Alucardias:BAAANQADCgYIBgAAAA==.',
Am='Amorlorisy:BAAANQADCgYIBgABNQADCggIGQADAAAAAA==.',
An='Anitwa:BAABNQAECoEUAAIHAAcKtBqdJABAAgAHAAcKtBqdJABAAgABNQAECgkJJAAGAB0XAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgEJAgAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAABNQAECoEYAAIEAAgKhRS3PgA8AgAEAAgKhRS3PgA8AgAAAA==.Aranina:BAAANQAECgQIBAAAAA==.Arcanedria:BAAANQABCgYIBgAAAA==.Arcturrus:BAAANQAECgEJAQAAAA==.Arel:BAAANQAECgYIEgAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arowid:BAAANQADCgUIDgAAAA==.Arter:BAAANQAECgEIAQABNQAECggIGwAIAN4TAA==.Aryhm:BAAANQAECgYIBwAAAA==.',
As='Asatralth:BAAANQAECgQIBgAAAA==.Asguard:BAAANQAECgEIAQAAAA==.Asheryo:BAAANQADCgUIBQAAAA==.Assphyxiate:BAAANQAECgEIAgAAAA==.Aszshara:BAAANQAECgEIAQAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAAANQAECgYJDQAAAA==.',
Ba='Babihotdog:BAAANQAECgMIBQAAAA==.Badspec:BAAANQAECggIAQAAAA==.Badwolff:BAAANQAECgQJBwAAAA==.Baerog:BAAANQAECgIJAgAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAABNQAECoEgAAIJAAkKGBi4UgCUAgAJAAkKGBi4UgCUAgAAAA==.Barlake:BAAANQADCgUIBQAAAA==.Basicblends:BAAANQAECgQIBQAAAA==.',
Bb='Bblglizzy:BAAANQADCgEIAQAAAA==.',
Be='Beefglizzy:BAAANQAECgYICQAAAA==.Beeftàllow:BAAANQADCgUJBQAAAA==.Beelzaboot:BAAANQAECgYIDwAAAA==.Belanor:BAABNQAECoEYAAICAAgKHhalCgAKAgACAAgKHhalCgAKAgAAAA==.Benjangles:BAAANQAECgYICgAAAA==.Berry:BAABNQAECoEhAAIKAAkK/CMAAQCsAwAKAAkK/CMAAQCsAwAAAA==.Betrayer:BAAANQAECgEJAQABNQAECgcIEQADAAAAAA==.',
Bh='Bhogrenoc:BAAANQADCgMJAwAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECgkJJAAGAB0XAA==.Bigdamfury:BAAANQAECgMJAwAAAA==.Bignipsmcgee:BAAANQAECgEIAQABNQAECgEIAQADAAAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgYJBAAAAA==.Bitss:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.',
Bl='Blacktastic:BAAANQAECgMJAwAAAA==.Bladebane:BAAANQADCgQIBAABNQAECgQJCgADAAAAAA==.Blastee:BAABNQAECoEaAAIEAAcKiyLEJgCbAgAEAAcKiyLEJgCbAgAAAA==.Blath:BAAANQADCggIGAAAAA==.Blazius:BAAANQAECgQIBQAAAA==.Bleebles:BAAANQADCgMIAwAAAA==.Blinkinpark:BAAANQADCgEIAQAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.Bloodlego:BAAANQAECgcIBwABNQAFFAYJCwAIAN0WAA==.',
Bo='Bobertl:BAAANQAECgUICAAAAA==.Bolter:BAAANQAECgEIAgAAAA==.Boomnecrotic:BAAANQAECgUJCwAAAA==.Boonney:BAAANQADCgYIBgAAAA==.Bopgun:BAAANQADCgEIAQAAAA==.',
Br='Braine:BAAANQADCgEIAQAAAA==.Breathboy:BAAANQAECgEIAwAAAA==.Bronder:BAAANQADCgYIEAAAAA==.Bronzehoofs:BAAANQADCgYICQAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Bulletbill:BAAANQADCgUIBQAAAA==.Bullwinklee:BAAANQABCgUIBwAAAA==.Burghmaul:BAAANQAECgQICAAAAA==.',
Ca='Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgIIAwAAAA==.Canon:BAAANQAECgUIBQAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Ceevee:BAAANQADCggJDwAAAA==.Celasong:BAAANQADCgIIAgAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Celtïc:BAAANQADCgQJBwAAAA==.Celydrea:BAAANQAECgQJBwAAAA==.Ceree:BAAANQAECgQJCQAAAA==.',
Ch='Chimeranzomb:BAAANQADCgQJBAAAAA==.Chippedbeef:BAAANQAECgQICwAAAA==.Chiwi:BAAANQADCgYIAwAAAA==.Chocogeta:BAAANQAECgUICQAAAA==.Chubbsmcgee:BAAANQADCgQJBAAAAA==.Chucknourysh:BAAANQADCgIIAgAAAA==.Chì:BAAANQAECgEIAgAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQAECgEIAQAAAA==.Cladow:BAABNQAECoEcAAMLAAgKSSPSDgA+AwALAAgKSSPSDgA+AwAMAAIK3hr5sgB/AAAAAA==.Clag:BAAANQADCgIJAgAAAA==.',
Co='Cogblock:BAAANQAECgYJEwAAAA==.Coldsteak:BAAANQADCggIDgAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cp='Cpwolf:BAAANQADCgYJBwAAAA==.',
Cr='Crimsonbull:BAAANQADCggICAABNQAECgkJHwANAIofAA==.Cronosphere:BAAANQADCgcIEAAAAA==.Crushaturty:BAAANQAECgEIAQAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQABCggIDgAAAA==.Cyndrin:BAAANQAECgYJDgAAAA==.',
Da='Daddyglock:BAAANQAECgMJBQAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAADAAAAAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAACNQAFFIELAAIIAAYK3RaaAwAQAgAIAAYK3RaaAwAQAgA1AAQKgSQAAggACQosJksCAN4DAAgACQosJksCAN4DAAAA.Darksign:BAAANQADCgIIAgAAAA==.Dathundir:BAAANQAECgcIBgABNQAECgkJHAAOANEbAA==.Davemage:BAAANQAECgQIBgAAAA==.Davidpaine:BAAANQAECgUIBQAAAA==.Dawnhorn:BAAANQADCgQIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBwAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Deepd:BAAANQAECggIAQAAAA==.Deepyram:BAAANQADCgEIAQAAAA==.Delillama:BAAANQAECgYJEQAAAA==.Demolior:BAAANQABCgEIAQAAAA==.Destnny:BAAANQAECgMIBQAAAA==.Destrohunter:BAAANQADCggIDgAAAA==.Destroker:BAAANQAECgUJDAAAAA==.',
Dh='Dhspudd:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.',
Di='Dillpo:BAAANQABCgUIBwAAAA==.Dioress:BAAANQAECgQIBgAAAA==.Dis:BAAANQAECgcJEQABNQAFFAUIBwALAOUYAA==.Disyx:BAAANQAECgQIBQAAAA==.Diyanå:BAABNQAECoEdAAIEAAgKQRTkOQBOAgAEAAgKQRTkOQBOAgAAAA==.',
Do='Domainz:BAAANQAECgYIDAAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donalan:BAAANQAECgEIAQAAAA==.Donzm:BAAANQADCgYIBgABNQAECgkJHgAPAMMUAA==.Donzw:BAABNQAECoEeAAQPAAkKwxQtCACHAQANAAkKRRNxNgBEAgAPAAcKTRItCACHAQAQAAQKPQaNNwDAAAAAAA==.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQAECgcIDgAAAA==.Dragonbender:BAEANQADCgYIEAAAAA==.Dragun:BAAANQADCgIIAgAAAA==.Draxxor:BAAANQAECgEJAQAAAA==.Dreamender:BAAANQAECggJBQABNQAECggJCAADAAAAAA==.Drfrash:BAAANQADCgYIBgAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAAANQAECgcIEwAAAA==.Drumin:BAAANQAECgYJDgAAAA==.',
Du='Dudewithpets:BAAANQADCgUIBQAAAA==.Durahar:BAAANQADCgUJBwAAAA==.',
Dw='Dwarvanhand:BAACNQAFFIELAAMRAAYKTg6LCQBPAQARAAQKthCLCQBPAQASAAQKFQ3CBQAwAQA1AAQKgSQAAxIACQriIWQIACcDABIACAoSJGQIACcDABEAAgoyEqOUAIsAAAAA.',
['Dã']='Dãwn:BAAANQAECggIBgAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQAECgYIBgABNQAECgcIDwADAAAAAA==.Earthrender:BAAANQADCgEIAQAAAA==.Eatmacookie:BAAANQADCgYIEQAAAA==.',
El='Elazar:BAAANQAECgUJBgAAAA==.Elderian:BAABNQAECoEWAAITAAcK0CVtCwANAwATAAcK0CVtCwANAwAAAA==.Elemenope:BAAANQAECgQIBgAAAA==.Elemitchard:BAAANQAECgEIAQAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAAANQAECgYIBwAAAA==.Elunaryn:BAAANQAECggJAQAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emerys:BAAANQADCgIIAgAAAA==.Emitlyght:BAAANQADCggIFQAAAA==.Emmabeth:BAAANQADCgMJAwAAAA==.',
En='Eniri:BAAANQAECgMIBgAAAA==.Enyeto:BAABNQAECoEbAAMIAAgK3hMCbgDCAQAIAAcKzRQCbgDCAQACAAEKUg1aKwA0AAAAAA==.',
Er='Ermaghaku:BAAANQADCgQJBAAAAA==.Erodras:BAAANQADCgIIAgAAAA==.Erojin:BAAANQADCgYIBgAAAA==.Eroviaevia:BAAANQAECgIJAgAAAA==.',
Es='Esterossa:BAAANQADCgYIBgAAAA==.',
Eu='Eunomia:BAABNQAECoEcAAIGAAcK/xQ4IQDVAQAGAAcK/xQ4IQDVAQAAAA==.',
Ex='Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAAANQAECgcIDgAAAA==.Ezoghoul:BAAANQAECgUJDgAAAA==.',
Fa='Faeare:BAAANQADCgYJDAAAAA==.Faene:BAAANQADCgQIBAAAAA==.Fakedemon:BAEANQADCgIIAgABNQAECgUIBgADAAAAAA==.Fakelock:BAEANQADCgMIAwABNQAECgUIBgADAAAAAA==.Fakendruid:BAEANQAECgUIBgAAAA==.Fauxx:BAAANQADCggIGgAAAA==.',
Fd='Fdup:BAAANQAECgMJBAAAAA==.',
Fe='Felfae:BAAANQAECgIJAgAAAA==.Feverish:BAAANQAECgcJDgAAAA==.',
Fi='Filip:BAAANQAECgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCggJFAAAAA==.Flumpy:BAABNQAECoEjAAIEAAkKqiPBBQCMAwAEAAkKqiPBBQCMAwAAAA==.Flurpymcdoof:BAAANQADCgYICAAAAA==.',
Fo='Folken:BAAANQAECgUJCgAAAA==.Foodtruck:BAAANQAECgEIAQABNQAECgYICgADAAAAAA==.Forbiddyn:BAAANQAECgcIEAAAAA==.Fornacater:BAAANQADCgcIBwAAAA==.Foxiefoxy:BAAANQAECgIJAgAAAA==.',
Fr='Fraiser:BAAANQADCgYICgABNQAECggIGwAIAN4TAA==.Freylyn:BAAANQADCgUIBQAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funkweave:BAEANQAECgYJEgAAAA==.Fupacabras:BAAANQAECgUICwAAAA==.Furidas:BAAANQAECgUJCAAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Gaius:BAAANQABCgIIAgAAAA==.Gangreenanus:BAAANQADCgYJCQAAAA==.Garogg:BAABNQAECoEZAAICAAgKhxIhDQDLAQACAAgKhxIhDQDLAQAAAA==.Garotomoreno:BAABNQAECoEcAAIOAAgKXB5NLgCgAgAOAAgKXB5NLgCgAgAAAA==.Garrut:BAAANQAECgYIDQAAAA==.Gaymr:BAAANQADCgIJAgAAAA==.',
Gi='Gigagrog:BAAANQAECgQIBQAAAA==.Giirthquakee:BAAANQAECgEIAQAAAA==.Gimmage:BAAANQAECgUJCwAAAA==.Gingebsham:BAAANQADCgcIBwABNQAECgUJDgADAAAAAA==.Girlyouthicc:BAAANQAECgIJAgABNQAFFAYJCwARAE4OAA==.Girthbrøøks:BAAANQADCgYIBgABNQAECgkJFwALAKYTAA==.',
Gl='Glorbruid:BAAANQADCggIEgAAAA==.',
Go='Gojosatóru:BAAANQAECgQJCwAAAA==.Goldenchef:BAAANQADCgYIBgAAAA==.Gordatamara:BAAANQADCgEIAQAAAA==.Gotcowbell:BAAANQAECgEIAQAAAA==.',
Gr='Grahnis:BAAANQADCgYIGAABNQAECgEIAQADAAAAAA==.Grasswhistle:BAAANQAECgUICAABNQAECgkJGQAUAAcjAA==.Grayzor:BAAANQAECgIIAgAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAAANQAECgYIEgAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAAANQAECgcJEwAAAA==.Grigdor:BAABNQAECoEeAAMQAAkKKhtyEQDRAQANAAcK1xrzPQAlAgAQAAYKVhtyEQDRAQAAAA==.Grimnativex:BAAANQADCgIIAgAAAA==.Gràcias:BAAANQADCgYIBgAAAA==.',
Gu='Guass:BAABNQAECoEcAAMVAAgKyBtaHACQAgAVAAgKyBtaHACQAgABAAEKaQONUAArAAAAAA==.Gunbolt:BAAANQAECgMIBQAAAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgUJEQAAAA==.',
Ha='Habrosh:BAAANQAECgQICQAAAA==.Hailrazor:BAAANQADCgIIAgAAAA==.Hakiry:BAAANQAECgUJCgAAAA==.Haliburton:BAAANQADCgMIAwAAAA==.Haramhabibi:BAAANQADCgYIBgAAAA==.Harike:BAAANQADCgMIAwAAAA==.Hatrix:BAAANQADCgMIAwAAAA==.Haunt:BAAANQAECgYIBQAAAA==.Havokhuntr:BAAANQADCgQIBAAAAA==.Hawkdalock:BAAANQADCgYICAAAAA==.Hawkkaye:BAAANQADCggJDAAAAA==.Haze:BAAANQAECgEIAgAAAA==.Hazesamaa:BAABNQAECoEvAAIWAAkKYg9xDgBeAgAWAAkKYg9xDgBeAgAAAA==.',
He='Healsforfree:BAAANQADCgIJAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIJAgAAAA==.Hernog:BAAANQAECgcIDwAAAA==.Hexmenixy:BAAANQAECgUJBwAAAA==.',
Hi='Hianu:BAAANQAECgYJDQAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.',
Ho='Holabenjy:BAAANQAECgQJCgAAAA==.Holybenjy:BAAANQAECgMIBAAAAA==.Holybibble:BAAANQADCgIIBAAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQAECgIIAwAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQAECgMJAwAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holysponge:BAAANQADCggJCAABNQAFFAEIAQADAAAAAA==.Holyzyn:BAAANQAECgEIAQAAAA==.Hoonding:BAAANQADCgcIFQABNQAECgkJLwAWAGIPAA==.Hordak:BAAANQADCgYIDQAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQADCgQIBAAAAA==.Hottodot:BAAANQAECgUJDgAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAAANQAECgQJBgAAAA==.',
Hu='Hudini:BAABNQAECoEjAAIJAAkKGRgvVQCMAgAJAAkKGRgvVQCMAgAAAA==.Hugs:BAAANQAECgMJAwAAAA==.Huntsmang:BAAANQADCgEJAQAAAA==.Hushweaver:BAAANQADCgQICgAAAA==.',
Hy='Hybridkaidou:BAAANQADCgMIAwAAAA==.Hypal:BAAANQAECgYICgABNQAECgMIBAADAAAAAA==.Hypd:BAAANQAECgMIBAAAAA==.Hypev:BAAANQAECgUJCgABNQAECgMIBAADAAAAAA==.Hypm:BAAANQADCgIIAgABNQAECgMIBAADAAAAAA==.Hyps:BAABNQAECoEiAAMMAAkKBx53FwDMAgAMAAkKBx53FwDMAgALAAUKjg4zfQAfAQABNQAECgMIBAADAAAAAA==.Hypt:BAAANQAECggIDwABNQAECgMIBAADAAAAAA==.',
Ia='Iakned:BAAANQAECgUJBQABNQAECgYJDAADAAAAAA==.',
Ib='Ibichi:BAAANQADCgYICwAAAA==.',
Ic='Icet:BAABNQAECoEZAAIWAAcKlxEaFwDsAQAWAAcKlxEaFwDsAQABNQADCggIDgADAAAAAA==.',
Il='Illshankya:BAAANQAECgIIAgAAAA==.',
Im='Imihn:BAAANQAECgMIBAAAAA==.',
In='Indàcouch:BAAANQABCgIIBAAAAA==.Invìctús:BAAANQAECgYJDgAAAA==.',
It='Ithir:BAAANQADCgcJDAAAAA==.Itsemma:BAAANQAECgYIDQAAAA==.',
Iu='Iustitia:BAAANQABCgMIBQAAAA==.',
Iv='Ivieruem:BAAANQADCgUIDAAAAA==.',
Iy='Iylara:BAAANQAECgEIAQAAAA==.',
Iz='Izhira:BAAANQABCgMIAgAAAA==.',
Ja='Jackdalilguy:BAAANQADCgUIBQAAAA==.Jackodes:BAAANQAECgcICwABNQAECgkJHQAJAO0iAA==.Jackodm:BAABNQAECoEdAAMJAAkK7SJ+GQBRAwAJAAkK7SJ+GQBRAwAXAAMKSRkwEwD6AAAAAA==.Jad:BAAANQAECgYIDwAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCgcJDgAAAA==.Jawa:BAAANQADCgUICgABNQAECgYIDQADAAAAAA==.Jawo:BAAANQAECgYIDQAAAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jersey:BAAANQADCgUIBQAAAA==.Jetts:BAAANQAECgYJEAAAAA==.',
Jo='Johnnysinz:BAAANQAECgYIEgAAAA==.Johnnyzyns:BAABNQAECoEXAAILAAkKphPTKQBvAgALAAkKphPTKQBvAgAAAA==.Johnret:BAAANQAECgQIBQABNQAECgUIBQADAAAAAA==.',
Jp='Jp:BAACNQAFFIEKAAIYAAUKOyWUAAApAgAYAAUKOyWUAAApAgA1AAQKgR0AAhgACQpyJkkAAOkDABgACQpyJkkAAOkDAAAA.',
Ju='Juhla:BAAANQADCgEIAQAAAA==.Juno:BAAANQADCgYJDwAAAA==.',
['Já']='Jáke:BAAANQAECgQIBAAAAA==.',
Ka='Kadester:BAAANQAECgEIAQAAAA==.Kaelwyn:BAAANQABCgIIAgAAAA==.Kaimen:BAAANQAECgUJBwAAAA==.Kainssoul:BAAANQADCgIIAgAAAA==.Kalipriest:BAAANQAECgYIDgAAAA==.Kalipso:BAAANQAECgQICQAAAA==.Kallea:BAAANQADCggICAAAAA==.Kalliz:BAAANQABCgQJBAAAAA==.Kamehameha:BAAANQADCggIDwAAAA==.Kamwar:BAACNQAFFIEJAAMZAAUKvxdZAABwAQAZAAQKZBlZAABwAQAIAAIKjgxdGACTAAA1AAQKgR0AAxkACQq8JTcAAOADABkACQq3JTcAAOADAAgAAwo/IAOzAOsAAAAA.Karideer:BAAANQAECgQJBAAAAA==.Karnaughm:BAAANQADCgUIAQAAAA==.Kataraxtis:BAAANQAECgQIBAAAAA==.Kaylax:BAAANQAECgIIAgAAAA==.Kaylost:BAAANQADCgMIBAAAAA==.Kaylub:BAAANQAECgYJDgAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQAECgMIBAAAAA==.Kenott:BAAANQAECgIIAgAAAA==.Kenparcell:BAAANQAECgIIAgAAAA==.Kerash:BAAANQADCgcIGwAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevindrd:BAAANQAECgUIBQABNQAECggJGQAaAKkWAA==.Kevintt:BAABNQAECoEZAAMaAAgKqRaWDwAhAgAaAAgKqRaWDwAhAgAbAAQKuglymQDSAAAAAA==.Keys:BAAANQAECgQIBgAAAA==.',
Kh='Kho:BAAANQADCgEIAQABNQAECgQIBwADAAAAAA==.Khodad:BAAANQADCgYICAABNQAECgQIBwADAAAAAA==.Khundalar:BAAANQAECgUIBQAAAA==.',
Ki='Kiarraa:BAAANQAECgIIAgAAAA==.Killachefcjr:BAAANQADCgcIFQAAAA==.Kimi:BAAANQADCgYIBgAAAA==.Kimori:BAAANQADCgUIBQAAAA==.Kinzee:BAAANQAECgIJAgAAAA==.',
Kn='Knugget:BAAANQAECgMJBAAAAA==.',
Ko='Kodiakhunter:BAAANQAECgUIBQAAAA==.Kodlighting:BAAANQADCgcJDAAAAA==.Komatsu:BAAANQADCgEIAQAAAA==.Koniqeo:BAAANQAECgEIAQAAAA==.Koressme:BAAANQADCggIEwAAAA==.Korlat:BAAANQAECgMJAwAAAA==.Kozdiniar:BAABNQAECoEnAAMVAAkKcyTMBQCMAwAVAAkKcyTMBQCMAwABAAYKVyF9EgBCAgAAAA==.Kozurai:BAAANQAECgUIBQABNQAECgkJJwAVAHMkAA==.',
Kr='Krimzin:BAAANQAECgEIAQABNQAFFAMIBQAEAEUVAA==.Kristree:BAAANQADCgMJBQAAAA==.Krëegz:BAAANQAECgcIDQAAAA==.Krëëgz:BAAANQADCgEIAQABNQAECgcIDQADAAAAAA==.',
Ku='Kugot:BAAANQADCggICAAAAA==.Kurupted:BAAANQAECgMJBgAAAA==.',
Ky='Kydrea:BAAANQAECgIJAgAAAA==.Kyne:BAAANQAECgQIBgAAAA==.Kynyselda:BAAANQAECgQJBAAAAA==.Kyrabear:BAAANQAECgEJAgAAAA==.',
['Kâ']='Kânê:BAABNQAECoEXAAIOAAcKLyC0NgB6AgAOAAcKLyC0NgB6AgAAAA==.',
La='Ladrón:BAAANQADCgYIDAAAAA==.Larayviana:BAAANQADCgcICAAAAA==.Larc:BAAANQAECgEJAgAAAA==.Larkos:BAAANQADCgcJCAAAAA==.Lassamyna:BAAANQAECgEJAQAAAA==.Latías:BAABNQAECoEaAAIJAAkKFh1uOwDaAgAJAAkKFh1uOwDaAgAAAA==.',
Le='Leechygos:BAAANQADCggIFQAAAA==.Legenddairy:BAAANQAECgIJAgAAAA==.Legirlas:BAAANQADCgQJBAABNQADCggIDwADAAAAAA==.Leha:BAAANQADCgEIAQAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAAANQAECgYJEAAAAA==.Lenorand:BAAANQADCgYJBgABNQAECgEJAgADAAAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyarrows:BAAANQADCggICAABNQAECggIGAATADYXAA==.Lickmyhorns:BAABNQAECoEYAAMTAAgKNhclHwAjAgATAAcKUBglHwAjAgAcAAYKkhC3MABZAQAAAA==.Liendrah:BAEBNQAECoEdAAIdAAkKuh7uAQAeAwAdAAkKuh7uAQAeAwAAAA==.Lightbeer:BAAANQABCgMIBQAAAA==.Lightmf:BAAANQAECgcIEQAAAA==.Lightninglip:BAAANQADCgcIFQAAAA==.Lightnleaf:BAAANQAECgEIAQAAAA==.Lightorange:BAAANQAECgEIAQAAAA==.Lightwaves:BAAANQAECgUICwAAAA==.Lilet:BAAANQAECgYJDQAAAA==.Lilitsune:BAAANQAECgEIAQAAAA==.Linareyna:BAAANQADCgIIAgAAAA==.Liotrix:BAAANQADCgYIBgABNQAECgYJDgADAAAAAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgQICAAAAA==.Lizolio:BAAANQAECgYIBwAAAA==.',
Ll='Llomel:BAAANQADCgYICAAAAA==.',
Lo='Lochlan:BAAANQADCggIDwAAAA==.Lohhano:BAAANQABCggIDQAAAA==.Londo:BAAANQADCgYJBgAAAA==.Louanna:BAAANQADCgUIBQAAAA==.',
Lu='Lucianagi:BAAANQAECgYIDAAAAA==.Lucilla:BAAANQADCgUIBQAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcIDgAAAA==.',
Ly='Lynavas:BAAANQADCgcIBwAAAA==.',
Ma='Machiné:BAAANQAECgEIAQAAAA==.Macnaulty:BAAANQADCggIBgAAAA==.Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAABNQAECoEaAAIRAAkKrCLFAwCMAwARAAkKrCLFAwCMAwAAAA==.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Maibutzfel:BAAANQADCgYIBgAAAA==.Majamojopowa:BAAANQABCgcIBwAAAA==.Majicman:BAAANQAECgIIAwAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manimal:BAAANQADCgcJBwABNQAECgUJCQADAAAAAA==.Manutters:BAAANQAECgQJBwAAAA==.Marrylanders:BAABNQAECoEuAAIJAAkKZSSbBQC+AwAJAAkKZSSbBQC+AwAAAA==.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAABNQAECoEkAAMGAAkKHRcqFAB0AgAGAAkKehUqFAB0AgAEAAIKNhHg1QB/AAAAAA==.Mastayoda:BAAANQABCgMIAwAAAA==.Mayven:BAAANQADCgUICgAAAA==.',
Mc='Mcboomii:BAAANQADCggICAAAAA==.',
Me='Megapally:BAAANQADCgQJBAAAAA==.Mellie:BAAANQADCgYJCQAAAA==.Melmei:BAAANQAECgMJBAAAAA==.Mephixto:BAAANQAECgQIBQAAAA==.Meriweather:BAAANQAECgQJBAAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Mertlek:BAAANQAECgUIBQABNQAECgkJJAAGAB0XAA==.Meszyra:BAABNQAECoEmAAIeAAkKLBtIBgD0AgAeAAkKLBtIBgD0AgAAAA==.',
Mi='Michaelcera:BAAANQAECgYIEgAAAA==.Mijuku:BAABNQAECoEeAAIHAAkKsRioGACjAgAHAAkKsRioGACjAgAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Minusgreen:BAAANQADCgYIBQAAAA==.Misoeternal:BAAANQAECgQJBAAAAA==.Mistafista:BAAANQAECgIIAgAAAA==.Mitchard:BAABNQAECoEYAAIfAAgKcgkLKwCbAQAfAAgKcgkLKwCbAQAAAA==.Mittenza:BAAANQADCggIFgAAAA==.Mixelplix:BAAANQAECgMJAwAAAA==.Mizstriss:BAAANQAECgUIBwAAAA==.',
Mo='Molari:BAAANQAECgEJAQAAAA==.Monksymeg:BAAANQADCgIIAgAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Moonfur:BAAANQAECgIIAgAAAA==.Mooseknuck:BAAANQADCgMIAwAAAA==.Mordath:BAAANQAECgEJAgAAAA==.Mordoom:BAAANQAECgQJBgAAAA==.Morikai:BAAANQAECgQIBAAAAA==.Morinn:BAAANQADCgcJDAAAAA==.Mosag:BAAANQAECgcIEQAAAA==.Moushou:BAAANQAECgUICwAAAA==.',
Ms='Mspacman:BAAANQAECgMIAwAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAABNQAECoEbAAILAAgKGB2RGwDQAgALAAgKGB2RGwDQAgAAAA==.Muppie:BAAANQADCgQIBQAAAA==.Mutovenator:BAAANQAECgEIAgAAAA==.',
My='Mychef:BAAANQADCgUIBQAAAA==.Myrrha:BAABNQAECoEdAAMeAAkKzB45BgD2AgAeAAgKfSE5BgD2AgAgAAYKwRMxGgCqAQAAAA==.',
['Mî']='Mîchael:BAAANQADCgIIAgAAAA==.',
['Mï']='Mïsterfox:BAAANQADCgcJDgAAAA==.',
['Mô']='Mônah:BAAANQADCgUJCQABNQADCggIEAADAAAAAA==.',
Na='Nakiro:BAAANQAECgQIBAAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICwAAAA==.',
Ne='Necroussy:BAAANQAECggIAgAAAA==.Nedilap:BAAANQAECgYJDAAAAA==.Nef:BAAANQAECgMIBAAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdchillpal:BAAANQADCgYIBgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQAECgQJBAAAAA==.Nerve:BAAANQAECgQIBAAAAA==.',
Ni='Nightx:BAAANQAECgUIDgAAAA==.Ninn:BAAANQADCgYIBgAAAA==.Nishkavel:BAAANQADCgUIBQAAAA==.Nitewang:BAAANQAECggIBwAAAA==.Nitewing:BAACNQAFFIEMAAIaAAYKdhzcAAAWAgAaAAYKdhzcAAAWAgA1AAQKgSQAAhoACQq7JFEBALsDABoACQq7JFEBALsDAAE1AAQKCAgHAAMAAAAA.Niza:BAAANQABCgYIDAAAAA==.',
No='Noccs:BAAANQADCgcIBQAAAA==.Noctaro:BAEANQAECggIEQAAAA==.Nokona:BAAANQADCggIEAAAAA==.Notpizza:BAAANQAECgMIAwABNQAECgkJGgAJAMIXAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAECggIGwALABgdAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
Ob='Obnixa:BAAANQAECgcJEwAAAA==.Obnixlis:BAAANQADCgYIBgAAAA==.',
Od='Ody:BAAANQAECgEIAQAAAA==.',
Og='Ogakal:BAAANQABCggIGQAAAA==.',
Oh='Ohsora:BAAANQADCgcIBwAAAA==.',
Ol='Oldstorm:BAAANQADCgEIAQABNQAECgYJEAADAAAAAA==.',
On='Onfiree:BAAANQAECggJCwAAAA==.',
Op='Opithel:BAABNQAECoEZAAIcAAgKHyQZBgBZAwAcAAgKHyQZBgBZAwAAAA==.Opiurza:BAAANQAECggIBwABNQAECggIGQAcAB8kAA==.Opizerka:BAAANQAECgcJEgABNQAECggIGQAcAB8kAA==.',
Or='Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAAANQAECgYIEAAAAA==.Oríllas:BAAANQAECgQICAAAAA==.',
Os='Osric:BAAANQADCgIJAgABNQAECgcIEQADAAAAAA==.',
Oy='Oyogo:BAACNQAFFIELAAIgAAcKBBVBAQBnAgAgAAcKBBVBAQBnAgA1AAQKgR0AAiAACQoQIhUEAEwDACAACQoQIhUEAEwDAAAA.Oyogu:BAAANQADCgUIBQABNQAFFAcICwAgAAQVAA==.Oyumi:BAAANQAECgYICwABNQAFFAcICwAgAAQVAA==.',
Pa='Paech:BAAANQADCgYIDAAAAA==.Pairädice:BAAANQADCgYIDAAAAA==.Paladane:BAAANQAECgMIBQAAAA==.Palakreegz:BAAANQADCgUJAwABNQAECgcIDQADAAAAAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQAECgEJAQAAAA==.Pamalinaa:BAAANQAECgIJAwAAAA==.Pamplemousse:BAAANQAECggIAQAAAA==.Pandadave:BAAANQADCgQICAAAAA==.Papanezz:BAAANQAECgQIBgAAAA==.Papasin:BAAANQAECggICAAAAA==.Patapouf:BAAANQAECgIJBAAAAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQAECgEIAQAAAA==.Pegully:BAAANQAECgUICgAAAA==.Pewxtwo:BAAANQADCgYJBwAAAA==.',
Ph='Phephraan:BAAANQAECgYIDwAAAA==.Phinehas:BAAANQADCggIHgAAAA==.Phwaz:BAAANQAECgQJBAAAAA==.Phyxyzin:BAAANQADCgUIDQAAAA==.',
Pi='Piccoloo:BAAANQADCgUICAAAAA==.Piddles:BAAANQADCgYJBgAAAA==.Pikeysham:BAAANQADCgMJAwAAAA==.Pinchebean:BAAANQAECgQIBQAAAA==.Pinktress:BAAANQAECgUJDAAAAA==.Pizzadough:BAABNQAECoEaAAIJAAkKwhfEUQCWAgAJAAkKwhfEUQCWAgAAAA==.Pizzapurse:BAAANQADCgQIBAAAAA==.',
Pk='Pkcontrol:BAAANQADCgUIBQAAAA==.',
Pl='Plavalagoona:BAAANQADCgMIBAABNQAECgUJDgADAAAAAA==.Plskillmie:BAAANQAECgYJEQAAAA==.',
Po='Pocahontis:BAAANQABCgIIAgAAAA==.Politics:BAAANQAECggIBgAAAA==.Polygonnacry:BAAANQAECgIJAgAAAA==.Popatop:BAAANQADCgQIBAAAAA==.Possecutor:BAACNQAFFIEKAAISAAQKOREsBQBLAQASAAQKOREsBQBLAQA1AAQKgSEAAhIACQrmHkAIACkDABIACQrmHkAIACkDAAAA.Pownadin:BAAANQADCgUICgAAAA==.',
Pr='Prabis:BAAANQADCggJHAAAAA==.Praesidius:BAAANQADCgcICgAAAA==.Priestalama:BAAANQADCgUIBQAAAA==.Promise:BAAANQAECgEIAQAAAA==.Pryîto:BAAANQAECgQIBgAAAA==.',
Pu='Pumachaka:BAAANQAECgIJAwAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Py='Pyresia:BAAANQAECgQJBQAAAA==.Pyrocity:BAAANQADCgYIBgAAAA==.',
Qu='Quackshot:BAAANQAECgYIEgAAAA==.',
Qw='Qwertysquid:BAAANQADCgMIBAAAAA==.',
Ra='Rads:BAAANQABCgEIAQAAAA==.Raegen:BAEANQADCgUIBQABNQAECggIEQADAAAAAA==.Raezer:BAEANQADCggICAABNQAECggIEQADAAAAAA==.Raiin:BAAANQAECgEJAQABNQAFFAYJCwARAE4OAA==.Raikomori:BAAANQAECgUIBQAAAA==.Ralroc:BAAANQADCgcIEAAAAA==.Ranare:BAAANQAECgYJCQAAAA==.Randomfatguy:BAAANQAECgEJAQAAAA==.Rathrus:BAAANQAECgQICwAAAA==.Ratonfusse:BAAANQABCgQJBAAAAA==.Ravenhart:BAAANQAECgMIAwAAAA==.Ravienn:BAAANQAECgEJAQABNQAECgkJJAAGAB0XAA==.Raxmanus:BAAANQAECgEJAQAAAA==.Rayru:BAAANQAECgIIAgAAAA==.Rayvienne:BAAANQADCgUIBwAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQAECgIJAgAAAA==.Reilini:BAABNQAECoEcAAIOAAkK0RsuKAC/AgAOAAkK0RsuKAC/AgAAAA==.Remedium:BAAANQABCgYJCwAAAA==.Renascor:BAAANQAECgQICQABNQAECgkJIAAeAB0hAA==.Reàp:BAAANQADCgMIAwAAAA==.',
Rh='Rhojin:BAAANQADCggIFgAAAA==.',
Ri='Rikimaruu:BAAANQAECggIDQAAAA==.Rinaari:BAAANQADCgUJBQAAAA==.Rinsecycle:BAAANQADCgUIBQAAAA==.Rivelia:BAAANQAECgIIAwABNQAECgkJHQAeAMweAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQAECgEIAQAAAA==.Ronek:BAAANQABCgUIBwAAAA==.Rosabella:BAAANQADCgQJBAAAAA==.Roshisain:BAAANQADCgQIBAAAAA==.Rouñders:BAAANQAECgEIAQABNQAFFAYJCwARAE4OAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAAANQAECgcJEgAAAA==.Rueldalf:BAAANQADCggJFwAAAA==.Ruïn:BAAANQADCggIEgAAAA==.',
['Ré']='Réka:BAAANQADCgQIBAABNQAECgYICgADAAAAAA==.',
['Rô']='Rôôst:BAAANQADCgIIAgAAAA==.Rôôstêr:BAAANQADCgQIBAAAAA==.',
Sa='Saino:BAAANQAECgEJAQAAAA==.Salidan:BAAANQADCgMIAwAAAA==.Salt:BAAANQAECgYIBwABNQAECggIGgAJAHAbAA==.Samlock:BAABNQAECoEgAAIQAAkKiR67AQBFAwAQAAkKiR67AQBFAwAAAA==.Sap:BAABNQAECoEbAAQhAAkKmB/uBABHAwAhAAkKix/uBABHAwAiAAYKLxdgCgCAAQAWAAMKiQ9eNACpAAABNQAECggIFgAIAFQlAA==.Satyrlord:BAAANQAECgMJAwAAAA==.Savella:BAAANQAECgUICAAAAA==.',
Sc='Scaleshot:BAAANQADCgYJBgAAAA==.Scarletblade:BAABNQAECoEcAAMOAAkKMB4IGwAJAwAOAAkKGB4IGwAJAwAaAAMKbRszKwDyAAAAAA==.Schamwoww:BAAANQAECgMIAwAAAA==.Sclas:BAAANQAECgEIAQAAAA==.Scubar:BAAANQAECgQJBAAAAA==.',
Se='Seafox:BAAANQAECgIJAgAAAA==.Sear:BAABNQAECoEYAAIcAAgKCRi1FwBWAgAcAAgKCRi1FwBWAgAAAA==.Selest:BAAANQADCgEIAQAAAA==.Selkets:BAAANQADCgUIBQAAAA==.Selkola:BAAANQABCgUIBwAAAA==.Sephimus:BAAANQADCgYIBgABNQAECgYJDwADAAAAAA==.Seraphiina:BAAANQAECgUJDQAAAA==.',
Sh='Shadowbinder:BAAANQADCggICAAAAA==.Shadowyclaws:BAAANQADCgEIAQAAAA==.Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgUIBgAAAA==.Shataree:BAAANQADCgQJBAAAAA==.Shineup:BAAANQADCggIEAAAAA==.Shintetsu:BAAANQADCggIDQAAAA==.Shockkor:BAAANQADCgcIDgAAAA==.Shockujin:BAAANQAECgIIAgABNQAECggIHAAbADENAA==.Shox:BAAANQADCgMIAwAAAA==.Shredder:BAAANQAECgEIAQABNQAECgYICgADAAAAAA==.Shý:BAAANQADCgIJAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sitaana:BAAANQAECgQJBAAAAA==.',
Sk='Skellek:BAAANQADCggICAAAAA==.Skillr:BAAANQAECgYIDAAAAA==.Skyekníght:BAAANQADCggICgAAAA==.',
Sl='Slaa:BAAANQADCgIIAgAAAA==.Sleezyaf:BAAANQAECgYIEgAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAABNQAECoEXAAMZAAgKMh6HBQA8AgAZAAcKQBuHBQA8AgAIAAcKKBd1dQCrAQAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQAECgMIAwAAAA==.',
So='Socketss:BAAANQAECgEIAQAAAA==.Sohjinra:BAAANQAECgEJAgAAAA==.Sollaria:BAAANQADCgYICQAAAA==.Sololvlin:BAAANQADCgYIDAAAAA==.Sololvling:BAAANQAECgQJEAAAAA==.Sovereign:BAACNQAFFIEKAAIOAAUKChGlAwCkAQAOAAUKChGlAwCkAQA1AAQKgSUAAg4ACQplIbcTADoDAA4ACQplIbcTADoDAAAA.',
Sp='Sp:BAAANQAECggIAQAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spicy:BAAANQAECgEIAQAAAA==.Splashaxuss:BAAANQADCgUICAAAAA==.Spookyloops:BAAANQAECggJCAAAAA==.Sproggles:BAAANQADCggIFAAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQABNQAECgUJBwADAAAAAA==.',
St='Stealthfire:BAABNQAECoEZAAIUAAkKByMuAQCaAwAUAAkKByMuAQCaAwAAAA==.Sterny:BAAANQAECgIIAwAAAA==.Stidetroll:BAAANQAECgEIAQAAAA==.Stnnisbrthon:BAAANQADCgQIBAAAAA==.Stormstrikes:BAAANQAECgEIAQAAAA==.Strongw:BAAANQAECggIDwAAAA==.Stul:BAAANQAECgYIDAAAAA==.',
Su='Substandard:BAAANQAECgYICQAAAA==.Sugaboomboom:BAAANQAECgEIAQAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sumwon:BAAANQAECgYICQAAAA==.Sunarr:BAAANQAECggJEwAAAA==.Sunkenlily:BAAANQADCgcIDAAAAA==.Superace:BAABNQAECoEcAAILAAkKHBYgIgChAgALAAkKHBYgIgChAgAAAA==.Surlee:BAAANQADCgcIBAAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQAECgMIAwAAAA==.',
Sw='Swaggernaut:BAAANQAECgMIBQAAAA==.Swiffys:BAAANQAECgYJEgAAAA==.Swissy:BAAANQADCgQIBwAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Synkadevour:BAAANQAECgQIBQABNQAECgUICgADAAAAAA==.Synkapriest:BAAANQAECgUICgAAAA==.Synkareaper:BAAANQADCgQIBgABNQAECgUICgADAAAAAA==.Synxzc:BAAANQADCgUIBQAAAA==.',
Ta='Taappy:BAAANQAECgQIBgAAAA==.Tacostuffing:BAAANQADCgYIBwAAAA==.Taggs:BAAANQAECgYIDwAAAA==.Taggsy:BAAANQADCgEIAQAAAA==.Tail:BAAANQAECgMJBgABNQAECgQIBQADAAAAAA==.Tails:BAAANQADCgYIEQAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQAECgQJBgAAAA==.Tanthora:BAAANQADCgYICQAAAA==.Tao:BAAANQADCgMIAwAAAA==.',
Te='Teddymouse:BAAANQAECggJCAAAAA==.Tenebris:BAAANQADCgUIBgAAAA==.Terrycrews:BAAANQAECgQJCQAAAA==.',
Th='Thanatóz:BAABNQAECoEeAAIHAAkK5h91DgAOAwAHAAkK5h91DgAOAwAAAA==.Thasper:BAAANQABCgMIAwAAAA==.Thebigkodiak:BAAANQADCggIDgAAAA==.Thebutler:BAAANQAECgcICQABNQAFFAYJCwARAE4OAA==.Thegrimus:BAABNQAECoEaAAIjAAgK9iINBAAmAwAjAAgK9iINBAAmAwAAAA==.Thekeres:BAAANQAECgEJAQAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Throh:BAAANQADCgUIBwAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Timøthy:BAAANQAECgYICgAAAA==.Tismtouched:BAAANQADCgQIBAAAAA==.',
Tk='Tkaniaa:BAAANQADCgQJCwAAAA==.',
To='Tokeyes:BAAANQAECgUJBQAAAA==.Toost:BAAANQAECgUJBQAAAA==.Torwa:BAAANQAECgIIBQAAAA==.Tossdirt:BAACNQAFFIEHAAILAAUK5RiZAwDDAQALAAUK5RiZAwDDAQA1AAQKgR8AAwsACQrUJEgFAKgDAAsACQrUJEgFAKgDAAwAAQoKCJ/eACYAAAAA.Toxle:BAAANQAECgEJAwAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trakshot:BAECNQAFFIELAAMEAAYKFgxiAQD1AQAEAAYK2gtiAQD1AQAFAAEKBAgkAQBVAAA1AAQKgRkAAwQACQqTGxYjAKwCAAQACQp+GxYjAKwCAAUAAwoFGuQIAAgBAAE1AAQKCAgcAAQAExgA.Trippdaddy:BAAANQAECgIIAgAAAA==.Truefaith:BAAANQADCgcIBwAAAA==.',
Ts='Tserendolgor:BAAANQABCgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgYIBwAAAA==.Tullegol:BAAANQAECgIIAgAAAA==.Tunasut:BAAANQADCgcIBwAAAA==.',
Tw='Twinswords:BAAANQAECgEJAQAAAA==.Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgQIBAAAAA==.',
Ty='Typhal:BAABNQAECoEbAAIOAAgKqCGVHAD/AgAOAAgKqCGVHAD/AgAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
['Té']='Téllah:BAAANQADCgYJBgAAAA==.',
Uh='Uhtain:BAAANQADCggIGwABNQADCggIGgADAAAAAA==.Uhtan:BAAANQADCggIGgAAAA==.',
Un='Uncleklaus:BAABNQAECoEbAAIOAAgKOyADJwDFAgAOAAgKOyADJwDFAgAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unicornfartz:BAAANQADCggICAAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQAECgYJDAAAAA==.',
Us='Ushiamdi:BAABNQAECoEbAAIKAAgK6xwlBgCQAgAKAAgK6xwlBgCQAgAAAA==.',
Ut='Utaan:BAAANQAECgMIAwABNQADCggIGgADAAAAAA==.',
Va='Vaduh:BAAANQADCgQIBAAAAA==.Vaerenaris:BAAANQADCgEIAQAAAA==.Vaiel:BAAANQAECgEIAQAAAA==.Valanthé:BAAANQADCgYICgAAAA==.Vandrey:BAAANQADCgcIDQAAAA==.Vazen:BAAANQADCgcIDwAAAA==.',
Ve='Velarasta:BAAANQADCgYIBwAAAA==.Veluna:BAAANQABCgMIAwABNQAECgYIEgADAAAAAA==.Veravvang:BAAANQAECgQIBwABNQADCggICAADAAAAAA==.Verdereina:BAAANQADCgcIBwAAAA==.Veroshia:BAAANQADCggIGwAAAA==.Vexea:BAAANQAECgMIBgABNQAECggIGgAJAHAbAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vi='Vinee:BAAANQADCgcJBwABNQAECgcJGgAEAIsiAA==.Vinladen:BAAANQADCgMIAwABNQAECgcIFQAhAGceAA==.Violettcloud:BAAANQAECgMIBAABNQAECggIIwAVAIYhAA==.Virali:BAAANQAECgYIEwAAAA==.Virussuckss:BAAANQADCgYIBgAAAA==.Vispper:BAAANQAECgUIDQAAAA==.Viyinx:BAAANQAECgQIBAABNQAECgkJHgAHAOYfAA==.Vizuel:BAAANQADCgUJDwABNQAECgEIAQADAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Vorel:BAAANQAECgQIBAAAAA==.',
Vp='Vpung:BAAANQAECgQIBAAAAA==.',
Vy='Vyllin:BAABNQAECoEaAAIaAAgKmxx+CwBvAgAaAAgKmxx+CwBvAgAAAA==.Vynarran:BAAANQAECgYIDwAAAA==.Vynlann:BAAANQADCgQIBAAAAA==.',
Wa='Warringmyer:BAAANQAECgUJCAAAAA==.Warriorlol:BAABNQAECoEWAAIIAAgKVCXfEwBCAwAIAAgKVCXfEwBCAwAAAA==.Watchdodo:BAAANQAECgIIBAAAAA==.Wax:BAAANQAECgMJAgAAAA==.',
We='Weebscum:BAABNQAECoEZAAIOAAgKvhPzVwD6AQAOAAgKvhPzVwD6AQAAAA==.',
Wi='Wiket:BAAANQABCgQIBAAAAA==.Wildestspice:BAAANQAFFAEIAQABNQAFFAUICwAbAMMXAA==.Willowblessu:BAABNQAECoEjAAIkAAkKBRT7AgCEAgAkAAkKBRT7AgCEAgAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQAECgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQADCgYIDQAAAA==.Woodglue:BAAANQADCggICAAAAA==.Wovenxlight:BAEANQAECgQIBAAAAA==.',
Wr='Wrathin:BAAANQAECgQIBAAAAA==.Wrayvin:BAAANQABCgEIAQAAAA==.',
Wu='Wufel:BAAANQAECgYJCQAAAA==.',
Xa='Xaeora:BAAANQAECgUICwAAAA==.',
Xe='Xeona:BAAANQADCgYJFAAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Ya='Yadhnak:BAAANQADCgQIBAAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yi='Yikes:BAAANQADCgEIAQAAAA==.',
Yo='Yoshikawa:BAABNQAECoEdAAMLAAkKThvXGwDOAgALAAgKeR7XGwDOAgAMAAQK/QSTmQC8AAAAAA==.',
Za='Zaivama:BAAANQAECgIJAgAAAA==.Zandren:BAAANQADCgYICgAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAAANQAFFAEIAQAAAA==.',
Ze='Zeenaheals:BAAANQAECgYIBwABNQAECgYICgADAAAAAA==.Zeenalizard:BAAANQAECgYICgAAAA==.Zegoo:BAAANQAECgMIBQAAAA==.Zendezit:BAAANQAECgQIBgAAAA==.Zenthura:BAAANQADCgIIAgABNQAFFAEIAQADAAAAAA==.Zenïca:BAAANQADCgYJDwAAAA==.',
Zi='Zimbadah:BAAANQAECgEJAQAAAA==.',
Zn='Znny:BAABNQAECoEZAAIZAAgK7xXtBABXAgAZAAgK7xXtBABXAgAAAA==.',
Zy='Zynling:BAAANQABCgUIBQAAAA==.Zynpouch:BAABNQAECoEfAAMNAAkKih+NLwBhAgANAAcKhh+NLwBhAgAQAAQKBx4nIQBDAQAAAA==.Zyrb:BAAANQADCggICwAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Ár']='Árthas:BAAANQADCgMIAwAAAA==.',
['Âr']='Ârthas:BAAANQAECgQJBQAAAA==.',
['Çr']='Çrimes:BAAANQAECgQJCAAAAA==.',
['Çu']='Çutty:BAAANQAECgMIBAAAAA==.',
['ßâ']='ßâßygirl:BAAANQADCgcIDQAAAA==.',
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
