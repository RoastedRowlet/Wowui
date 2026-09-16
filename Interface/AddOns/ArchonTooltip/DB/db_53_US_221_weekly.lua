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

local lookup = {'Druid-Restoration','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Paladin-Protection','Mage-Arcane','Druid-Guardian','Warrior-Arms','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Priest-Holy','Rogue-Subtlety','Shaman-Restoration','Mage-Frost','Monk-Mistweaver','Warrior-Fury','Rogue-Outlaw','Druid-Balance','Evoker-Devastation','DeathKnight-Unholy','Evoker-Preservation','Paladin-Holy','Rogue-Assassination','Paladin-Retribution','Priest-Discipline',}
local provider = {region='US',realm='Thunderlord',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaliyah:BAABNQAECoEXAAIBAAgJ2BrDCgCJAgABAAgJ2BrDCgCJAgAAAA==.',
Ab='Abyssknight:BAAANQADCggIDgAAAA==.',
Ac='Acesso:BAAANQADCggIGwAAAA==.',
Ad='Adeonus:BAAANQADCgYIDAAAAA==.Adraydenn:BAAANQADCggIHgABNQAECgYIDQACAAAAAA==.',
Ae='Aecheron:BAAANQADCgcIDAABNQAECgQIBQACAAAAAA==.',
Ag='Aggressor:BAAANQADCgMIAwAAAA==.Aggrocrack:BAAANQADCggIJQAAAA==.Agliam:BAAANQAECgEIAQAAAA==.',
Ah='Ahngus:BAAANQAECgMIBAAAAA==.',
Ai='Air:BAAANQAECgMIAwAAAA==.',
Al='Alakander:BAAANQAECgIIAwAAAA==.Alexcrowley:BAAANQADCgMIAwAAAA==.Alexdh:BAAANQADCgYIBwABNQAECgkJFgADAP4hAA==.Alexdruids:BAAANQAECgUIBQABNQAECgkJFgADAP4hAA==.Alexhunt:BAABNQAECoEWAAQDAAkJ/iEXHACgAgADAAgJSCIXHACgAgAEAAUJ4xz1IgB1AQAFAAEJYyDyCQBjAAAAAA==.Alplarn:BAAANQAECgQIBgAAAA==.Althsar:BAAANQADCgEIAQAAAA==.Alucardias:BAAANQADCgYIBgAAAA==.',
Am='Amorlorisy:BAAANQADCgYIBgABNQADCggIGQACAAAAAA==.',
An='Anitwa:BAAANQAECgcIDQABNQAECgkJIQAEAH0XAA==.Anomari:BAAANQADCgUIBQAAAA==.',
Ap='Apkuggull:BAAANQAECgEIAgAAAA==.Appeal:BAAANQADCgMIAwAAAA==.',
Ar='Arandiel:BAAANQAECgYIDwAAAA==.Aranina:BAAANQADCggIFwAAAA==.Arcturrus:BAAANQADCggIDwAAAA==.Arel:BAAANQAECgYIDAAAAA==.Arkayist:BAAANQAECgEIAQAAAA==.Arowid:BAAANQADCgUICQAAAA==.Arrwyn:BAAANQADCgIIAgABNQAFFAQIBgAGAK4YAA==.Arter:BAAANQAECgEIAQABNQAECgYIEQACAAAAAA==.Aryhm:BAAANQAECgEIAQAAAA==.',
As='Asatralth:BAAANQAECgIIAgAAAA==.Asguard:BAAANQAECgEIAQAAAA==.Asheryo:BAAANQADCgUIBQAAAA==.Assphyxiate:BAAANQAECgEIAQAAAA==.Aszshara:BAAANQADCgYICgAAAA==.',
Au='Automagic:BAAANQAECgQIBQAAAA==.',
Ay='Aymine:BAAANQAECgUICQAAAA==.',
Ba='Babihotdog:BAAANQAECgMIBAAAAA==.Badspec:BAAANQAECggIAQAAAA==.Badwolff:BAAANQAECgMIAwAAAA==.Baerog:BAAANQADCggIEgAAAA==.Banf:BAAANQAECgIIAwAAAA==.Baodabao:BAABNQAECoEaAAIHAAgJ4xmYUQBXAgAHAAgJ4xmYUQBXAgAAAA==.Barlake:BAAANQADCgUIBQAAAA==.Basicblends:BAAANQAECgQIBQAAAA==.',
Bb='Bblglizzy:BAAANQADCgEIAQAAAA==.',
Be='Beefglizzy:BAAANQAECgYICQAAAA==.Beelzaboot:BAAANQAECgUICQAAAA==.Belanor:BAAANQAECgYIDQAAAA==.Benjangles:BAAANQAECgQIBAAAAA==.Berry:BAABNQAECoEZAAIIAAgJ5CPcAQBBAwAIAAgJ5CPcAQBBAwAAAA==.Betrayer:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.',
Bh='Bhogrenoc:BAAANQADCgEIAQAAAA==.',
Bi='Bigbahungas:BAAANQADCggICgAAAA==.Bigchudifer:BAAANQADCgQIBAABNQAECgkJIQAEAH0XAA==.Bigdamfury:BAAANQADCggIEAAAAA==.Bignipsmcgee:BAAANQAECgEIAQAAAA==.Bigthunder:BAAANQADCgUIBQAAAA==.Binkalul:BAAANQADCgUIBQAAAA==.Biolimit:BAAANQAECgYIBAAAAA==.Bitss:BAAANQADCgEIAQABNQADCggIJQACAAAAAA==.',
Bl='Blacktastic:BAAANQADCggIDwAAAA==.Bladebane:BAAANQADCgQIBAAAAA==.Blastee:BAAANQAECgYIDwAAAA==.Blath:BAAANQADCggIGAAAAA==.Blazius:BAAANQAECgQIBQAAAA==.Bleebles:BAAANQADCgMIAwAAAA==.Blinkinpark:BAAANQADCgEIAQAAAA==.Blitzkregmag:BAAANQADCgEIAQAAAA==.',
Bo='Bobertl:BAAANQAECgUICAAAAA==.Boomnecrotic:BAAANQAECgQIBgAAAA==.Boonney:BAAANQADCgYIBgAAAA==.Bopgun:BAAANQADCgEIAQAAAA==.',
Br='Breathboy:BAAANQAECgEIAgAAAA==.Bronder:BAAANQADCgYIEAAAAA==.Bronzehoofs:BAAANQADCgUICQAAAA==.',
Bu='Bubblemews:BAAANQADCgQIAwAAAA==.Bulletbill:BAAANQADCgUIBQAAAA==.Bullwinklee:BAAANQABCgUIBwAAAA==.Burghmaul:BAAANQAECgMIBAAAAA==.',
Ca='Cahri:BAAANQADCgQICAAAAA==.Calenesandra:BAAANQAECgIIAwAAAA==.Canon:BAAANQADCgcIDAAAAA==.Capodost:BAAANQADCgEIAQAAAA==.',
Ce='Ceevee:BAAANQADCgcIBwAAAA==.Celasong:BAAANQADCgIIAgAAAA==.Celestialhex:BAAANQABCgIIAgAAAA==.Celtïc:BAAANQADCgQIBAAAAA==.Celydrea:BAAANQAECgMIAwAAAA==.Ceree:BAAANQAECgMIBAAAAA==.',
Ch='Chimeranzomb:BAAANQADCgQIBAAAAA==.Chippedbeef:BAAANQAECgIIAgAAAA==.Chiwi:BAAANQADCgYIAwAAAA==.Chocogeta:BAAANQAECgQIBAAAAA==.Chucknourysh:BAAANQADCgIIAgAAAA==.Chì:BAAANQAECgEIAQAAAA==.',
Cl='Cladie:BAAANQADCgQIBAAAAA==.Cladoe:BAAANQAECgEIAQAAAA==.Cladow:BAAANQAECgcIEQAAAA==.Clag:BAAANQADCgIIAgAAAA==.',
Co='Cogblock:BAAANQAECgUIDQAAAA==.Coldsteak:BAAANQADCggICAAAAA==.Conqor:BAAANQAECgQIBAAAAA==.',
Cr='Crimsonbull:BAAANQADCggICAABNQAECgcIEwACAAAAAA==.Cronosphere:BAAANQADCgcIEAAAAA==.Crushaturty:BAAANQADCgQIBwAAAA==.',
Cu='Cubes:BAAANQADCgUIBQAAAA==.',
Cy='Cyndrainna:BAAANQABCgQICAAAAA==.Cyndrin:BAAANQAECgYICAAAAA==.',
Da='Daddyglock:BAAANQAECgMIAwAAAA==.Daerper:BAAANQADCgcIBwABNQADCggIDAACAAAAAA==.Danayro:BAAANQADCgQIBAAAAA==.Darklego:BAACNQAFFIEGAAIJAAQJABaTBgBdAQAJAAQJABaTBgBdAQA1AAQKgSEAAgkACQmSJdQBAOIDAAkACQmSJdQBAOIDAAAA.Darksign:BAAANQADCgIIAgAAAA==.Dathundir:BAAANQAECgcIBgABNQAECggIEQACAAAAAA==.Davemage:BAAANQAECgIIAgAAAA==.Dawnhorn:BAAANQADCgQIBAAAAA==.',
De='Deaddhunter:BAAANQADCgEIAQAAAA==.Deaddmage:BAAANQADCgUIBwAAAA==.Deadlylight:BAAANQADCgYIBgAAAA==.Deepyram:BAAANQADCgEIAQAAAA==.Delillama:BAAANQAECgYICwAAAA==.Demolior:BAAANQABCgEIAQAAAA==.Destnny:BAAANQAECgIIAwAAAA==.Destrohunter:BAAANQADCggIDgAAAA==.Destroker:BAAANQAECgQIBwAAAA==.',
Dh='Dhspudd:BAAANQADCgYIBgABNQAECgUIBwACAAAAAA==.',
Di='Dillpo:BAAANQABCgUIBwAAAA==.Dioress:BAAANQAECgQIBgAAAA==.Dis:BAAANQAECgYICgABNQAECgkJGgAKAMAkAA==.Disyx:BAAANQAECgIIAgABNQAECgQICAACAAAAAA==.Diyanå:BAAANQAECggIEgAAAA==.',
Do='Domainz:BAAANQAECgYIDAAAAA==.Dommymommie:BAAANQADCgMIAwAAAA==.Donalan:BAAANQAECgEIAQAAAA==.Donzm:BAAANQADCgYIBgABNQAECgkJHAALAGIUAA==.Donzw:BAABNQAECoEcAAQLAAkJYhS+BQCSAQAMAAkJ5BJrJABXAgALAAcJTRK+BQCSAQANAAQJPQZuMQDIAAAAAA==.Dorkwaffle:BAAANQADCgIIAgAAAA==.',
Dr='Dracthick:BAAANQAECgcICgAAAA==.Dragonbender:BAEANQADCgUICgAAAA==.Dragun:BAAANQADCgIIAgAAAA==.Draxxor:BAAANQAECgEIAQAAAA==.Dreamender:BAAANQAECggIBQAAAA==.Droknor:BAAANQADCgQICAAAAA==.Druidllama:BAAANQAECgUIDAAAAA==.Drumin:BAAANQAECgYIDgAAAA==.',
Du='Dudewithpets:BAAANQADCgUIBQAAAA==.Durahar:BAAANQADCgQIAgAAAA==.',
Dw='Dwarvanhand:BAABNQAECoEhAAMOAAkJvCA0CgDhAgAOAAcJ4CQ0CgDhAgAPAAIJMhKBdgCMAAAAAA==.',
['Dâ']='Dâwn:BAAANQAECggICwAAAA==.',
['Dã']='Dãwn:BAAANQAECggIBgAAAA==.',
['Dæ']='Dærper:BAAANQADCggIDAAAAA==.',
Ea='Earthmender:BAAANQADCgYIBwAAAA==.Eatmacookie:BAAANQADCgYIEQAAAA==.',
El='Elazar:BAAANQAECgIIAgAAAA==.Elderian:BAAANQAECgcICAAAAA==.Elemenope:BAAANQAECgIIAgAAAA==.Elemitchard:BAAANQAECgEIAQAAAA==.Elguasonbb:BAAANQADCgUICAAAAA==.Elidori:BAAANQADCggICwAAAA==.',
Em='Emashasha:BAAANQADCgQIBAAAAA==.Emerys:BAAANQADCgIIAgAAAA==.Emitlyght:BAAANQADCggIFQAAAA==.Emmabeth:BAAANQADCgIIAgAAAA==.',
En='Eniri:BAAANQAECgIIAwAAAA==.Enyeto:BAAANQAECgYIEQAAAA==.',
Er='Erodras:BAAANQADCgIIAgAAAA==.Eroviaevia:BAAANQADCggIFgAAAA==.',
Es='Esterossa:BAAANQADCgYIBgAAAA==.',
Eu='Eunomia:BAABNQAECoEcAAIEAAcJ4hQzGgDuAQAEAAcJ4hQzGgDuAQAAAA==.',
Ex='Exra:BAAANQADCgQIAwAAAA==.',
Ez='Ezekeel:BAAANQAECgQIBwAAAA==.Ezoghoul:BAAANQAECgQICQAAAA==.',
Fa='Faeare:BAAANQADCgYIDAAAAA==.Faene:BAAANQADCgQIBAAAAA==.Fakedemon:BAEANQADCgIIAgABNQAECgEIAQACAAAAAA==.Fakelock:BAEANQADCgMIAwABNQAECgEIAQACAAAAAA==.Fakendruid:BAEANQAECgEIAQAAAA==.Fauxx:BAAANQADCgcIEgAAAA==.',
Fd='Fdup:BAAANQAECgIIAgAAAA==.',
Fe='Felfae:BAAANQADCgcIEgAAAA==.Feverish:BAAANQAECgcIBwAAAA==.',
Fi='Filip:BAAANQAECgEIAQAAAA==.',
Fl='Flamefenix:BAAANQADCggIFAAAAA==.Flumpy:BAAANQAECgcIEwAAAA==.Flurpymcdoof:BAAANQADCgYICAAAAA==.',
Fo='Folken:BAAANQAECgQIBgAAAA==.Foodtruck:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Forbiddyn:BAAANQAECgcIEAAAAA==.Fornacater:BAAANQADCgcIBwAAAA==.Foxiefoxy:BAAANQADCgcIFAAAAA==.',
Fr='Fraiser:BAAANQADCgYICgABNQAECgYIEQACAAAAAA==.Freylyn:BAAANQADCgUIBQAAAA==.',
Fu='Fulgrum:BAAANQADCgIIAwAAAA==.Funkweave:BAEANQAECgYICwAAAA==.Fupacabras:BAAANQAECgQIBgAAAA==.Furidas:BAAANQAECgIIAwAAAA==.',
['Fö']='Föxfïre:BAAANQADCgIIAgAAAA==.',
Ga='Gaius:BAAANQABCgIIAgAAAA==.Gangreenanus:BAAANQADCgYIBgAAAA==.Garogg:BAAANQAECgYIDgAAAA==.Garotomoreno:BAAANQAECgcIEgAAAA==.Garrut:BAAANQAECgQIBwAAAA==.Gaymr:BAAANQADCgIIAgAAAA==.',
Gi='Gigagrog:BAAANQAECgQIBQAAAA==.Giirthquakee:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Gimmage:BAAANQAECgQIBgAAAA==.Gingebsham:BAAANQADCgcIBwABNQAECgUICQACAAAAAA==.',
Gl='Glorbruid:BAAANQADCggIEgAAAA==.',
Go='Gojosatóru:BAAANQAECgQICwAAAA==.Goldenchef:BAAANQADCgYIBgAAAA==.Gordatamara:BAAANQADCgEIAQAAAA==.Gotcowbell:BAAANQAECgEIAQAAAA==.',
Gr='Grahnis:BAAANQADCgUIDwABNQAECgEIAQACAAAAAA==.Grasswhistle:BAAANQAECgMIAwABNQAECgYIDQACAAAAAA==.Grayzor:BAAANQAECgIIAgAAAA==.Greendust:BAAANQADCgYICQAAAA==.Greenperor:BAAANQAECgUIDAAAAA==.Grenthor:BAAANQADCgEIAQAAAA==.Grenvar:BAAANQAECgcIEQAAAA==.Grigdor:BAABNQAECoEZAAMNAAgJRBmBDwDcAQANAAYJVhuBDwDcAQAMAAYJyBX/PgDRAQAAAA==.Grimnativex:BAAANQADCgIIAgAAAA==.Gràcias:BAAANQADCgYIBgAAAA==.',
Gu='Guass:BAAANQAECgYIEQAAAA==.Gunbolt:BAAANQAECgMIBQAAAA==.',
['Gø']='Gøhåñ:BAAANQADCgYIBgAAAA==.',
['Gù']='Gùndèr:BAAANQAECgQIDAAAAA==.',
Ha='Habrosh:BAAANQAECgQICAAAAA==.Hailrazor:BAAANQADCgIIAgAAAA==.Hakiry:BAAANQAECgMIBQAAAA==.Haliburton:BAAANQADCgMIAwAAAA==.Harike:BAAANQADCgMIAwAAAA==.Hatrix:BAAANQADCgMIAwAAAA==.Haunt:BAAANQAECgYIAQAAAA==.Havokhuntr:BAAANQADCgQIBAAAAA==.Hawkdalock:BAAANQADCgYICAAAAA==.Hawkkaye:BAAANQADCgYICwAAAA==.Haze:BAAANQAECgEIAgAAAA==.Hazesamaa:BAABNQAECoEiAAIQAAkJxQ3GDABkAgAQAAkJxQ3GDABkAgAAAA==.',
He='Healsforfree:BAAANQADCgIIAgAAAA==.Healsgoodman:BAAANQADCgEIAgAAAA==.Hellviera:BAAANQADCgIIAgAAAA==.Hernog:BAAANQAECgcICQAAAA==.Hexmenixy:BAAANQAECgIIAgAAAA==.',
Hi='Hianu:BAAANQAECgYIBwAAAA==.Highlordhunt:BAAANQADCgUIBQAAAA==.',
Ho='Holabenjy:BAAANQAECgQIBgAAAA==.Holybenjy:BAAANQAECgMIAwAAAA==.Holybibble:BAAANQADCgIIBAAAAA==.Holybox:BAAANQAECgEIAQAAAA==.Holyfady:BAAANQAECgIIAwAAAA==.Holyfenix:BAAANQAECgEIAQAAAA==.Holynixy:BAAANQADCggIDgAAAA==.Holypaladinn:BAAANQADCgEIAQAAAA==.Holyzyn:BAAANQAECgEIAQAAAA==.Hoonding:BAAANQADCgcICAABNQAECgkJIgAQAMUNAA==.Hordak:BAAANQADCgYIDQAAAA==.Horne:BAAANQADCgEIAQAAAA==.Hotstuffbaby:BAAANQADCgQIBAAAAA==.Hottodot:BAAANQAECgUICQAAAA==.Howde:BAAANQADCggIDgAAAA==.Howdydoo:BAAANQAECgIIAgAAAA==.',
Hu='Hudini:BAABNQAECoEeAAIHAAgJ2Be4VABMAgAHAAgJ2Be4VABMAgAAAA==.Hushweaver:BAAANQADCgQICgAAAA==.',
Hy='Hybridkaidou:BAAANQADCgMIAwAAAA==.Hypal:BAAANQAECgMIBAABNQAECgMIAwACAAAAAA==.Hypd:BAAANQAECgMIAwAAAA==.Hypev:BAAANQAECgQIBQABNQAECgMIAwACAAAAAA==.Hypm:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.Hyps:BAABNQAECoEYAAMRAAkJ6BpNEADZAgARAAkJ6BpNEADZAgAKAAQJfgsWfADbAAABNQAECgMIAwACAAAAAA==.Hypt:BAAANQAECgcICQABNQAECgMIAwACAAAAAA==.',
Ia='Iakned:BAAANQADCggICAABNQAECgYICwACAAAAAA==.',
Ib='Ibichi:BAAANQADCgYICwAAAA==.',
Ic='Icet:BAAANQAECgYIEAABNQADCggICAACAAAAAA==.',
Il='Illshankya:BAAANQAECgIIAgAAAA==.',
Im='Imihn:BAAANQAECgEIAQAAAA==.',
In='Indàcouch:BAAANQABCgIIBAAAAA==.Invìctús:BAAANQAECgQICAAAAA==.',
It='Ithir:BAAANQADCgYICwAAAA==.Itsemma:BAAANQAECgUIBwAAAA==.',
Iu='Iustitia:BAAANQABCgMIBQAAAA==.',
Iv='Ivieruem:BAAANQADCgUIBQAAAA==.',
Iy='Iylara:BAAANQAECgEIAQAAAA==.',
Iz='Izhira:BAAANQABCgMIAgAAAA==.',
Ja='Jaanus:BAAANQADCgMIAwAAAA==.Jackdalilguy:BAAANQADCgUIBQAAAA==.Jackodes:BAAANQAECgIIAwABNQAECggIGAAHAF0jAA==.Jackodm:BAABNQAECoEYAAMHAAgJXSMnIQAQAwAHAAgJXSMnIQAQAwASAAMJSRl2DgADAQAAAA==.Jad:BAAANQAECgUICQAAAA==.Janicafae:BAAANQADCgMIAwAAAA==.Jareth:BAAANQABCgcIDgAAAA==.Jawa:BAAANQADCgUICgABNQAECgUICAACAAAAAA==.Jawo:BAAANQAECgUICAAAAA==.',
Je='Jeefberky:BAAANQADCgYIBgAAAA==.Jersey:BAAANQADCgUIBQAAAA==.Jetts:BAAANQAECgUICgAAAA==.',
Jo='Johnnysinz:BAAANQAECgUIDAAAAA==.Johnnyzyns:BAAANQAECggIDQAAAA==.Johnret:BAAANQAECgQIBQAAAA==.',
Jp='Jp:BAABNQAECoEbAAITAAkJWyYsAADuAwATAAkJWyYsAADuAwAAAA==.',
Ju='Juhla:BAAANQADCgEIAQAAAA==.Juno:BAAANQADCgYIDwAAAA==.',
['Já']='Jáke:BAAANQAECgQIBAAAAA==.',
Ka='Kadester:BAAANQAECgEIAQAAAA==.Kaelwyn:BAAANQABCgIIAgAAAA==.Kaimen:BAAANQAECgIIAgAAAA==.Kalipriest:BAAANQAECgUICAAAAA==.Kalipso:BAAANQAECgMIBQAAAA==.Kamehameha:BAAANQADCggIDwAAAA==.Kamwar:BAABNQAECoEbAAMUAAkJGiUqAADaAwAUAAkJFSUqAADaAwAJAAMJPyA6kAD/AAABNQAFFAUICgAVAPIhAA==.Karideer:BAAANQADCggIFAAAAA==.Karnaughm:BAAANQADCgUIAQAAAA==.Kataraxtis:BAAANQADCgYIBgAAAA==.Kaylax:BAAANQAECgIIAgAAAA==.Kaylost:BAAANQADCgMIAwAAAA==.Kaylub:BAAANQAECgQICAAAAA==.Kazrim:BAAANQADCgQIBAAAAA==.',
Ke='Keldhar:BAAANQAECgMIAwAAAA==.Kenparcell:BAAANQADCggIBwAAAA==.Kerash:BAAANQADCgYIFAAAAA==.Kevindk:BAAANQADCgYIBgAAAA==.Kevindrd:BAAANQAECgUIBQABNQAECgYIEAACAAAAAA==.Kevintt:BAAANQAECgYIEAAAAA==.Keys:BAAANQAECgIIAgAAAA==.',
Kh='Khodad:BAAANQADCgYICAABNQAECgQIBQACAAAAAA==.Khundalar:BAAANQAECgUIBQAAAA==.',
Ki='Kiarraa:BAAANQAECgEIAQAAAA==.Killachefcjr:BAAANQADCgcIEAAAAA==.Kimi:BAAANQADCgYIBgAAAA==.Kimori:BAAANQADCgUIBQAAAA==.Kinzee:BAAANQADCgEIAQAAAA==.',
Kn='Knugget:BAAANQAECgEIAQAAAA==.',
Ko='Kodiakhunter:BAAANQAECgEIAQAAAA==.Kodlighting:BAAANQADCgYICwAAAA==.Koniqeo:BAAANQAECgEIAQAAAA==.Koressme:BAAANQADCggIEwAAAA==.Korlat:BAAANQADCggIGwAAAA==.Kozdiniar:BAABNQAECoEhAAIWAAkJcyQ2AwCtAwAWAAkJcyQ2AwCtAwAAAA==.Kozurai:BAAANQAECgUIBQABNQAECgkJIQAWAHMkAA==.',
Kr='Kristree:BAAANQADCgIIAgAAAA==.Krëegz:BAAANQAECgQIBgAAAA==.Krëëgz:BAAANQADCgEIAQABNQAECgQIBgACAAAAAA==.',
Ku='Kugot:BAAANQADCggICAAAAA==.Kurupted:BAAANQAECgIIAwAAAA==.',
Ky='Kydrea:BAAANQADCgcIFAAAAA==.Kyne:BAAANQAECgIIAgAAAA==.Kynyselda:BAAANQAECgQIBAAAAA==.Kyrabear:BAAANQADCgUIBwAAAA==.',
['Kâ']='Kânê:BAAANQAECgcIEQAAAA==.',
La='Ladrón:BAAANQADCgYIDAAAAA==.Larayviana:BAAANQADCgYIBgAAAA==.Larc:BAAANQADCgYICQAAAA==.Larkos:BAAANQADCgYIBgAAAA==.Lassamyna:BAAANQADCgcIBwAAAA==.Latías:BAAANQAECggIEwAAAA==.',
Le='Leechygos:BAAANQADCggIEgAAAA==.Legenddairy:BAAANQADCggIHAAAAA==.Legirlas:BAAANQADCgQIBAABNQADCggIDwACAAAAAA==.Leheo:BAAANQADCgEIAQAAAA==.Leigong:BAAANQAECgYICgAAAA==.Lenorand:BAAANQABCgYIDAABNQAECgEIAQACAAAAAA==.',
Li='Liani:BAAANQADCgIIAgAAAA==.Lickmyhorns:BAAANQAECgYIEAAAAA==.Liendrah:BAEANQAECgcIEQAAAA==.Lightbeer:BAAANQABCgMIBQAAAA==.Lightmf:BAAANQAECgcIDAAAAA==.Lightninglip:BAAANQADCgcIFQAAAA==.Lightwaves:BAAANQAECgQIBgAAAA==.Lilet:BAAANQAECgQIBwAAAA==.Lilitsune:BAAANQAECgEIAQAAAA==.Linareyna:BAAANQADCgIIAgAAAA==.Liotrix:BAAANQADCgYIBgABNQAECgYICAACAAAAAA==.Liradel:BAAANQADCgIIAgAAAA==.Lisri:BAAANQAECgIIBAAAAA==.Lizolio:BAAANQAECgEIAQAAAA==.',
Ll='Llomel:BAAANQADCgYICAAAAA==.',
Lo='Lochlan:BAAANQADCggIDwAAAA==.Lohhano:BAAANQABCgcICgAAAA==.Louanna:BAAANQADCgUIBQAAAA==.',
Lu='Lucianagi:BAAANQAECgYIDAAAAA==.Lucilla:BAAANQADCgUIBQAAAA==.Lussprodz:BAAANQADCgUIBQAAAA==.Luurg:BAAANQADCgcIDgAAAA==.',
Ma='Macnaulty:BAAANQADCggIBgAAAA==.Mageunal:BAAANQADCgEIAQAAAA==.Magikkosa:BAAANQAECgcIDwAAAA==.Maibutzbrewy:BAAANQADCgQIBgAAAA==.Maibutzfel:BAAANQADCgYIBgAAAA==.Majamojopowa:BAAANQABCgcIBwAAAA==.Majicman:BAAANQADCgcIBwAAAA==.Malekíth:BAAANQADCggIAgAAAA==.Manutters:BAAANQAECgMIAwAAAA==.Marrylanders:BAABNQAECoEkAAIHAAkJBiL5EABjAwAHAAkJBiL5EABjAwAAAA==.Marrylock:BAAANQADCgUIBQAAAA==.Martiul:BAABNQAECoEhAAMEAAkJfRfQFAA9AgAEAAkJ5RXQFAA9AgADAAIJNhE+rQCFAAAAAA==.Mastayoda:BAAANQABCgMIAwAAAA==.Mayven:BAAANQADCgUICgAAAA==.',
Mc='Mcboomii:BAAANQADCggICAAAAA==.',
Me='Megapally:BAAANQADCgQIBAAAAA==.Mellie:BAAANQADCgMIAwAAAA==.Melmei:BAAANQAECgEIAQAAAA==.Mephixto:BAAANQADCgMIBAAAAA==.Meriweather:BAAANQADCggIGwAAAA==.Merlinajax:BAAANQADCgYIDAAAAA==.Mertlek:BAAANQADCggICgABNQAECgkJIQAEAH0XAA==.Meszyra:BAABNQAECoEeAAIXAAkJfRcJBwC6AgAXAAkJfRcJBwC6AgAAAA==.',
Mi='Michaelcera:BAAANQAECgYIDgAAAA==.Mijuku:BAABNQAECoEYAAIYAAgJZhJ9JAAVAgAYAAgJZhJ9JAAVAgAAAA==.Mikehawk:BAAANQADCgcIDAAAAA==.Minusgreen:BAAANQADCgYIBQAAAA==.Misoeternal:BAAANQADCggIGwAAAA==.Mistafista:BAAANQADCgUIBgAAAA==.Mitchard:BAAANQAECgcIDAAAAA==.Mittenza:BAAANQADCggIFgAAAA==.Mixelplix:BAAANQADCggIEwAAAA==.Mizstriss:BAAANQAECgUIBQAAAA==.',
Mo='Molari:BAAANQADCgcIEAAAAA==.Monksymeg:BAAANQADCgIIAgAAAA==.Monkwilbo:BAAANQADCgYIBgAAAA==.Moonfur:BAAANQAECgEIAQAAAA==.Mooseknuck:BAAANQADCgMIAwAAAA==.Mordath:BAAANQAECgEIAQAAAA==.Mordoom:BAAANQAECgQIBQAAAA==.Morikai:BAAANQAECgMIAwAAAA==.Morinn:BAAANQADCgYIBgAAAA==.Mosag:BAAANQAECgUICgAAAA==.Moushou:BAAANQAECgQIBgAAAA==.',
Ms='Mspacman:BAAANQADCggIDgAAAA==.',
Mu='Mudslide:BAAANQADCgUIBQAAAA==.Muffduster:BAAANQADCgUIBQAAAA==.Muffintopper:BAAANQAECgYIEQAAAA==.Muppie:BAAANQADCgQIBQAAAA==.Mutovenator:BAAANQAECgEIAQAAAA==.',
My='Mychef:BAAANQADCgUIBQAAAA==.Myrrha:BAABNQAECoEUAAMXAAgJeCB7BQDtAgAXAAgJeCB7BQDtAgAZAAMJ+xsCIQD5AAAAAA==.',
['Mî']='Mîchael:BAAANQADCgIIAgAAAA==.',
['Mï']='Mïsterfox:BAAANQADCgYIDQAAAA==.',
['Mô']='Mônah:BAAANQADCgUIBgABNQADCgcIDwACAAAAAA==.',
Na='Nakiro:BAAANQADCgcIEQAAAA==.Namhanharal:BAAANQADCgUIBQAAAA==.Natch:BAAANQADCgUICwAAAA==.',
Ne='Necroussy:BAAANQAECggIAgAAAA==.Nedilap:BAAANQAECgYICwAAAA==.Nef:BAAANQAECgEIAQAAAA==.Neqousa:BAAANQADCgIIAgAAAA==.Nerbench:BAAANQABCgIIAgAAAA==.Nerdchillpal:BAAANQADCgYIBgAAAA==.Nerdi:BAAANQADCgQIBAAAAA==.Nerokos:BAAANQADCggIDwAAAA==.Nerve:BAAANQADCgEIAQAAAA==.',
Ni='Nightx:BAAANQAECgUICgAAAA==.Ninn:BAAANQADCgYIBgAAAA==.Nishkavel:BAAANQADCgUIBQAAAA==.Nitewing:BAACNQAFFIEGAAIGAAQJrhiuAQBFAQAGAAQJrhiuAQBFAQA1AAQKgSEAAgYACQm7JNUAAMQDAAYACQm7JNUAAMQDAAAA.Niza:BAAANQABCgYIDAAAAA==.',
No='Noccs:BAAANQADCgcIBQAAAA==.Noctaro:BAEANQAECggIEQAAAA==.Nokona:BAAANQADCgcIDwAAAA==.Notpizza:BAAANQAECgMIAwABNQAECgkJFwAHAPwVAA==.',
Nu='Nuikha:BAAANQADCgYIBwAAAA==.Nukenfoobs:BAAANQADCgEIAQABNQAECgYIEQACAAAAAA==.',
Ny='Nyoazz:BAAANQADCgEIAQAAAA==.',
Ob='Obnixa:BAAANQAECgYIDAAAAA==.Obnixlis:BAAANQADCgYIBgAAAA==.',
Od='Ody:BAAANQAECgEIAQAAAA==.',
Og='Ogakal:BAAANQABCgYIFAAAAA==.',
Oh='Ohsora:BAAANQADCgcIBwAAAA==.',
Ol='Oldstorm:BAAANQADCgEIAQABNQAECgYICgACAAAAAA==.',
On='Onfiree:BAAANQAECggICwAAAA==.',
Op='Opithel:BAAANQAECgYIDQABNQAECgcIDgACAAAAAA==.Opizerka:BAAANQAECgcIDgAAAA==.',
Or='Oriestus:BAAANQADCgEIAQAAAA==.Oriko:BAAANQAECgUICgAAAA==.Oríllas:BAAANQAECgQICAAAAA==.',
Os='Osric:BAAANQADCgIIAgABNQAECgUICgACAAAAAA==.',
Oy='Oyogo:BAABNQAECoEbAAIZAAkJECKqAgBgAwAZAAkJECKqAgBgAwABNQAFFAYICwAaAIgeAA==.Oyogu:BAAANQADCgUIBQABNQAFFAYICwAaAIgeAA==.Oyumi:BAAANQAECgYIBgABNQAFFAYICwAaAIgeAA==.',
Pa='Paech:BAAANQADCgYIBgAAAA==.Pairädice:BAAANQADCgYIDAAAAA==.Paladane:BAAANQAECgMIBAAAAA==.Pallymorph:BAAANQADCgIIAgAAAA==.Palsdruid:BAAANQADCgcIEAAAAA==.Pamalinaa:BAAANQAECgIIAgAAAA==.Pamplemousse:BAAANQAECggIAQAAAA==.Pandadave:BAAANQADCgQIBAAAAA==.Papanezz:BAAANQAECgQIBgAAAA==.Papasin:BAAANQAECggICAAAAA==.Patapouf:BAAANQAECgIIAwAAAA==.Payback:BAAANQADCgEIAQAAAA==.',
Pe='Pearbandit:BAAANQAECgEIAQAAAA==.Pegully:BAAANQAECgQIBQAAAA==.Pewxtwo:BAAANQADCgEIAQAAAA==.',
Ph='Phephraan:BAAANQAECgUICQAAAA==.Phinehas:BAAANQADCggIFwAAAA==.Phwaz:BAAANQADCggIGgAAAA==.Phyxyzin:BAAANQADCgUIDQAAAA==.',
Pi='Piccoloo:BAAANQADCgUIBAAAAA==.Piddles:BAAANQADCgYIBgAAAA==.Pikeysham:BAAANQADCgMIAwAAAA==.Pinchebean:BAAANQAECgEIAQAAAA==.Pinktress:BAAANQAECgQIBwAAAA==.Pizzadough:BAABNQAECoEXAAIHAAkJ/BVtPACgAgAHAAkJ/BVtPACgAgAAAA==.Pizzapurse:BAAANQADCgQIBAAAAA==.',
Pk='Pkcontrol:BAAANQADCgUIBQAAAA==.',
Pl='Plavalagoona:BAAANQADCgEIAQABNQAECgQICQACAAAAAA==.Plskillmie:BAAANQAECgUICwAAAA==.',
Po='Pocahontis:BAAANQABCgIIAgAAAA==.Polygonnacry:BAAANQADCgMIAwAAAA==.Popatop:BAAANQADCgQIBAAAAA==.Possecutor:BAACNQAFFIEGAAIOAAQJxQ9HAwBMAQAOAAQJxQ9HAwBMAQA1AAQKgRoAAg4ACQmXHGAJAPQCAA4ACQmXHGAJAPQCAAAA.Pownadin:BAAANQADCgUICgAAAA==.',
Pr='Prabis:BAAANQADCggIFAAAAA==.Praesidius:BAAANQADCgYIBgAAAA==.Pryîto:BAAANQAECgIIAgAAAA==.',
Pu='Pumachaka:BAAANQAECgIIAgAAAA==.Pushinp:BAAANQADCgQIBAAAAA==.',
Py='Pyresia:BAAANQAECgQIBAAAAA==.Pyrocity:BAAANQADCgYIBgAAAA==.',
Qu='Quackshot:BAAANQAECgYIDAAAAA==.',
Qw='Qwertysquid:BAAANQADCgMIBAAAAA==.',
Ra='Rads:BAAANQABCgEIAQAAAA==.Raegen:BAEANQADCgUIBQABNQAECggIEQACAAAAAA==.Raezer:BAEANQADCggICAABNQAECggIEQACAAAAAA==.Raikomori:BAAANQAECgMIAwAAAA==.Ralroc:BAAANQADCgYICQAAAA==.Ranare:BAAANQAECgIIAwAAAA==.Randomfatguy:BAAANQAECgEIAQAAAA==.Rathrus:BAAANQAECgQIBgAAAA==.Ratonfusse:BAAANQABCgQIBAAAAA==.Ravenhart:BAAANQADCggICwAAAA==.Ravienn:BAAANQADCggICAABNQAECgkJIQAEAH0XAA==.Raxmanus:BAAANQADCgYIEAAAAA==.Rayru:BAAANQAECgIIAgAAAA==.Rayvienne:BAAANQADCgIIAgAAAA==.',
Re='Readthebible:BAAANQADCgIIAgAAAA==.Redvelvett:BAAANQADCggIEgAAAA==.Reilini:BAAANQAECggIEQAAAA==.Remedium:BAAANQABCgYICwAAAA==.Renascor:BAAANQAECgQICQABNQAECgkJHgAXAFYgAA==.Reàp:BAAANQADCgMIAwAAAA==.',
Rh='Rhojin:BAAANQADCggIFgAAAA==.',
Ri='Rikimaruu:BAAANQAECgcIDAAAAA==.Rinaari:BAAANQADCgUIBQAAAA==.Rivelia:BAAANQADCgcIBwABNQAECggIFAAXAHggAA==.',
Ro='Rockethunt:BAAANQAECgMIAwAAAA==.Rokurota:BAAANQAECgEIAQAAAA==.Ronek:BAAANQABCgUIBwAAAA==.Royalborn:BAAANQAECgEIAQAAAA==.',
Ru='Rubikon:BAAANQAECgYICwAAAA==.Rueldalf:BAAANQADCgcIFgAAAA==.Ruïn:BAAANQADCggIEgAAAA==.',
['Rô']='Rôôst:BAAANQADCgIIAgAAAA==.Rôôstêr:BAAANQADCgQIBAAAAA==.',
Sa='Salidan:BAAANQADCgMIAwAAAA==.Salt:BAAANQAECgYIBwABNQAECggICQACAAAAAA==.Samlock:BAABNQAECoEYAAINAAkJehgYAwDxAgANAAkJehgYAwDxAgAAAA==.Sap:BAABNQAECoESAAQbAAcJRhqNFAD3AQAbAAYJ4xmNFAD3AQAVAAYJLxd0CACSAQAQAAMJiQ9fLgCwAAABNQAECggIFgAJAFQlAA==.Satyrlord:BAAANQADCggIFAAAAA==.Savella:BAAANQAECgMIAwAAAA==.',
Sc='Scarletblade:BAAANQAECgcIDwAAAA==.Schamwoww:BAAANQAECgMIAwAAAA==.Sclas:BAAANQADCggIDAAAAA==.Scubar:BAAANQADCggIFQAAAA==.',
Se='Seafox:BAAANQADCgIIAgAAAA==.Sear:BAAANQAECgcIDwAAAA==.Selest:BAAANQADCgEIAQAAAA==.Selkets:BAAANQADCgUIBQAAAA==.Selkola:BAAANQABCgUIBwAAAA==.Sephimus:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.Seraphiina:BAAANQAECgQICAAAAA==.',
Sh='Shadowbinder:BAAANQADCggICAAAAA==.Shadowyclaws:BAAANQADCgEIAQAAAA==.Shamiam:BAAANQADCgUIBQAAAA==.Shamozmo:BAAANQADCgUIBgAAAA==.Shataree:BAAANQADCgQIBAAAAA==.Shineup:BAAANQADCggIEAAAAA==.Shintetsu:BAAANQADCggIDQAAAA==.Shockkor:BAAANQADCgcIDgAAAA==.Shockujin:BAAANQADCgcICwABNQAECgcIEwACAAAAAA==.Shox:BAAANQADCgMIAwAAAA==.Shý:BAAANQADCgIIAgAAAA==.',
Si='Silanris:BAAANQADCgQICAAAAA==.Sitaana:BAAANQADCgcIBwAAAA==.',
Sk='Skillr:BAAANQAECgQIBQAAAA==.Skyekníght:BAAANQADCggICgAAAA==.',
Sl='Sleezyaf:BAAANQAECgYIDAAAAA==.Slermp:BAAANQADCgYIBgAAAA==.Slicett:BAAANQADCgMIAwAAAA==.Slowcase:BAABNQAECoEXAAMUAAgJMh6fAwBPAgAUAAcJQBufAwBPAgAJAAcJKBfQWADPAQAAAA==.',
Sm='Smoochem:BAAANQADCggICAAAAA==.',
Sn='Sneaze:BAAANQADCgUIBQAAAA==.',
So='Socketss:BAAANQAECgEIAQAAAA==.Sohjinra:BAAANQAECgEIAQAAAA==.Sollaria:BAAANQADCgMIAwAAAA==.Sololvlin:BAAANQADCgYIDAAAAA==.Sololvling:BAAANQAECgQIDAAAAA==.Sovereign:BAACNQAFFIEFAAIcAAMJixLeBAD6AAAcAAMJixLeBAD6AAA1AAQKgSEAAhwACQmNIMEMAEMDABwACQmNIMEMAEMDAAAA.',
Sp='Sp:BAAANQAECggIAQAAAA==.Sparkleclaws:BAAANQADCgUIBgAAAA==.Sparkycleave:BAAANQADCgYICwAAAA==.Spicy:BAAANQAECgEIAQAAAA==.Splashaxuss:BAAANQADCgUICAAAAA==.Spookyloops:BAAANQAECggICAAAAA==.Sproggles:BAAANQADCggIEAAAAA==.',
Ss='Sslipknot:BAAANQADCgEIAQABNQAECgEIAgACAAAAAA==.',
St='Stealthfire:BAAANQAECgYIDQAAAA==.Sterny:BAAANQAECgIIAgAAAA==.Stidetroll:BAAANQAECgEIAQAAAA==.Stnnisbrthon:BAAANQADCgQIBAAAAA==.Stormstrikes:BAAANQAECgEIAQAAAA==.Strongw:BAAANQAECgQIBgAAAA==.Stul:BAAANQAECgQIBgAAAA==.',
Su='Substandard:BAAANQAECgMIAwAAAA==.Sumo:BAAANQABCgIIAgAAAA==.Sumwon:BAAANQAECgIIAwAAAA==.Sunarr:BAAANQAECgYICwAAAA==.Sunkenlily:BAAANQADCgcIDAAAAA==.Superace:BAABNQAECoEWAAIKAAkJ0xJEIQBoAgAKAAkJ0xJEIQBoAgAAAA==.Surlee:BAAANQADCgcIBAAAAA==.Surlydude:BAAANQADCgEIAQAAAA==.Suule:BAAANQADCggIFQAAAA==.',
Sw='Swaggernaut:BAAANQAECgIIAgAAAA==.Swiffys:BAAANQAECgYIDAAAAA==.Swissy:BAAANQADCgQIBwAAAA==.Swordnoob:BAAANQAECgEIAQAAAA==.',
Sy='Synkadevour:BAAANQAECgIIAwAAAA==.Synkapriest:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.Synkareaper:BAAANQADCgQIBgABNQAECgIIAwACAAAAAA==.Synxzc:BAAANQADCgUIBQAAAA==.',
Ta='Taappy:BAAANQAECgQIBQAAAA==.Tacostuffing:BAAANQADCgIIAgAAAA==.Taggs:BAAANQAECgYICQAAAA==.Taggsy:BAAANQADCgEIAQAAAA==.Tail:BAAANQAECgMIBAAAAA==.Tails:BAAANQADCgYIEQAAAA==.Tajomaru:BAAANQADCgIIAgAAAA==.Tanmand:BAAANQAECgIIAgAAAA==.Tanthora:BAAANQADCgYICQAAAA==.Tao:BAAANQADCgMIAwAAAA==.',
Te='Teddymouse:BAAANQADCgYICwABNQAECggIBQACAAAAAA==.Tenebris:BAAANQADCgUIBgAAAA==.Terrycrews:BAAANQAECgQIBQAAAA==.',
Th='Thanatóz:BAABNQAECoEWAAIYAAgJkCBvEQDJAgAYAAgJkCBvEQDJAgAAAA==.Thasper:BAAANQABCgMIAwAAAA==.Thebigkodiak:BAAANQADCggIDgAAAA==.Thebutler:BAAANQAECgIIAgABNQAECgkJIQAOALwgAA==.Thegrimus:BAAANQAECgcIEQAAAA==.Thekeres:BAAANQADCgUICQAAAA==.Thickums:BAAANQADCgEIAQAAAA==.Thornwhisper:BAAANQADCgcIBwAAAA==.Throh:BAAANQADCgUIBwAAAA==.Thussy:BAAANQAECgEIAQAAAA==.',
Ti='Timøthy:BAAANQAECgMIBAAAAA==.',
Tk='Tkaniaa:BAAANQADCgQICAAAAA==.',
To='Tokeyes:BAAANQAECgMIAwAAAA==.Torwa:BAAANQAECgIIAwAAAA==.Tossdirt:BAABNQAECoEaAAMKAAkJwCSKBAChAwAKAAkJwCSKBAChAwARAAEJCgiGuwAtAAAAAA==.Toxle:BAAANQAECgEIAwAAAA==.Toysruskid:BAAANQADCgIIAgAAAA==.',
Tr='Trakshot:BAEANQAFFAQIBAABNQAECggIFQADAJkWAA==.Trippdaddy:BAAANQAECgIIAgAAAA==.Truefaith:BAAANQADCgcIBwAAAA==.',
Ts='Tserendolgor:BAAANQABCgIIAgAAAA==.',
Tu='Tuckford:BAAANQADCgYIBwAAAA==.Tullegol:BAAANQADCggICAAAAA==.',
Tw='Twinswords:BAAANQAECgEIAQAAAA==.Twiz:BAAANQADCgEIAQAAAA==.',
Tx='Txcreekwoo:BAAANQADCgQIBAAAAA==.',
Ty='Typhal:BAAANQAECgYIEgAAAA==.Typo:BAAANQADCgEIAQAAAA==.',
['Té']='Téllah:BAAANQADCgYIBgAAAA==.',
Uh='Uhtain:BAAANQADCggIGwABNQADCggIGgACAAAAAA==.Uhtan:BAAANQADCggIGgAAAA==.',
Un='Uncleklaus:BAAANQAECgcIEQAAAA==.Ungnite:BAAANQAECgEIAQAAAA==.Unicornfartz:BAAANQADCggICAAAAA==.Unikorn:BAAANQADCgEIAQAAAA==.',
Ur='Urthron:BAAANQAECgQIBgAAAA==.',
Us='Ushiamdi:BAAANQAECgcIEQAAAA==.',
Ut='Utaan:BAAANQADCggIFAABNQADCggIGgACAAAAAA==.',
Va='Vaerenaris:BAAANQADCgEIAQAAAA==.Vaiel:BAAANQAECgEIAQAAAA==.Valanthé:BAAANQADCgYICgAAAA==.Vandrey:BAAANQADCgYIDAAAAA==.Vazen:BAAANQADCgcICAAAAA==.',
Ve='Velarasta:BAAANQADCgYIBwAAAA==.Veluna:BAAANQABCgMIAwABNQAECgYIDAACAAAAAA==.Veravvang:BAAANQAECgQIBwABNQADCggICAACAAAAAA==.Verdereina:BAAANQADCgcIBwAAAA==.Veroshia:BAAANQADCggIGwAAAA==.Vexea:BAAANQAECgMIBgABNQAECggICQACAAAAAA==.Vexx:BAAANQADCgcIDAAAAA==.',
Vi='Vinee:BAAANQADCgcIBwABNQAECgYIDwACAAAAAA==.Vinladen:BAAANQADCgMIAwABNQAECgUIDgACAAAAAA==.Violettcloud:BAAANQAECgMIBAABNQAECgcIGwAWAPkgAA==.Virali:BAAANQAECgUIDQAAAA==.Virussuckss:BAAANQADCgYIBgAAAA==.Vispper:BAAANQAECgQIBwAAAA==.Viyinx:BAAANQAECgQIBAABNQAECggIFgAYAJAgAA==.Vizuel:BAAANQADCgQICAABNQAECgEIAQACAAAAAA==.',
Vk='Vkdk:BAAANQADCgYIBgAAAA==.',
Vo='Vorel:BAAANQADCgYIBgAAAA==.',
Vp='Vpung:BAAANQAECgMIAwAAAA==.',
Vy='Vyllin:BAAANQAECgYIEQAAAA==.Vynarran:BAAANQAECgYIDgAAAA==.Vynlann:BAAANQADCgQIBAAAAA==.',
Wa='Warringmyer:BAAANQAECgMIAwAAAA==.Warriorlol:BAABNQAECoEWAAIJAAgJVCXgDABiAwAJAAgJVCXgDABiAwAAAA==.Watchdodo:BAAANQADCggIGgAAAA==.Wax:BAAANQADCgQIBAAAAA==.',
We='Weebscum:BAABNQAECoEZAAIcAAgJvhN0OwAOAgAcAAgJvhN0OwAOAgAAAA==.',
Wi='Wiket:BAAANQABCgQIBAAAAA==.Willowblessu:BAABNQAECoEaAAIdAAgJ2g+ZBAD7AQAdAAgJ2g+ZBAD7AQAAAA==.Willòw:BAAANQADCgEIAQAAAA==.Windler:BAAANQAECgEIAQAAAA==.Wisha:BAAANQADCgEIAQAAAA==.',
Wo='Wojiaonl:BAAANQADCgEIAQAAAA==.Wolty:BAAANQADCgYIDQAAAA==.Woodglue:BAAANQADCggICAAAAA==.Wovenxlight:BAEANQAECgQIBAAAAA==.',
Wr='Wrathin:BAAANQAECgQIBAAAAA==.Wrayvin:BAAANQABCgEIAQAAAA==.',
Wu='Wufel:BAAANQAECgQIBAAAAA==.',
Xa='Xaeora:BAAANQAECgUIBgAAAA==.',
Xe='Xeona:BAAANQADCgYIEAAAAA==.Xesolyt:BAAANQADCgMIAwAAAA==.',
Ya='Yadhnak:BAAANQADCgQIBAAAAA==.',
Ye='Yeahbrother:BAAANQADCgIIAgAAAA==.Yeralt:BAAANQADCgEIAQAAAA==.',
Yi='Yikes:BAAANQADCgEIAQAAAA==.',
Yo='Yoshikawa:BAAANQAECgcIEQAAAA==.',
Za='Zaivama:BAAANQADCgIIAgAAAA==.Zandren:BAAANQADCgYICgAAAA==.Zaranthari:BAAANQADCgMIAwAAAA==.Zarindela:BAAANQAECgcICgAAAA==.',
Ze='Zeenaheals:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Zeenalizard:BAAANQAECgUICAAAAA==.Zegoo:BAAANQAECgMIBQAAAA==.Zendezit:BAAANQAECgQIBgAAAA==.Zenthura:BAAANQADCgIIAgABNQAECgcICgACAAAAAA==.Zenïca:BAAANQADCgYIDwAAAA==.',
Zi='Zimbadah:BAAANQADCggIGwAAAA==.',
Zn='Znny:BAAANQAECgcIEQAAAA==.',
Zy='Zynling:BAAANQABCgUIBQAAAA==.Zynpouch:BAAANQAECgcIEwAAAA==.Zyrb:BAAANQADCggICAAAAA==.',
['Áf']='Áfterlight:BAAANQADCgUIBQAAAA==.',
['Ár']='Árthas:BAAANQADCgMIAwAAAA==.',
['Âr']='Ârthas:BAAANQAECgQIBQAAAA==.',
['Çr']='Çrimes:BAAANQAECgQIBAAAAA==.',
['Çu']='Çutty:BAAANQAECgMIBAAAAA==.',
['ßâ']='ßâßygirl:BAAANQADCgYIBgAAAA==.',
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
