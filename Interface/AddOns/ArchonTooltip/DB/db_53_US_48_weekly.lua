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

local lookup = {'Unknown-Unknown','Priest-Discipline','Warrior-Arms','Hunter-BeastMastery','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Priest-Holy','Mage-Arcane','Warrior-Protection','Rogue-Assassination','Druid-Guardian','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','Warrior-Fury','Hunter-Marksmanship','Warlock-Affliction','Druid-Feral','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Caelestrasz',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abbyss:BAAANQAECgIJAgABNQAECgUJCAABAAAAAA==.Abirnar:BAAANQAECgUICgAAAA==.Abramelinn:BAAANQAECgUJCQAAAA==.Abygayle:BAAANQAECgQIBQAAAA==.',
Ac='Acca:BAAANQAECgIIAwAAAA==.',
Ad='Adget:BAAANQAECgYIEwAAAA==.Adicas:BAAANQABCgIJAgAAAA==.Adorion:BAAANQADCgYIDgAAAA==.',
Ae='Aerali:BAABNQAECoEaAAICAAgKOh00AgC9AgACAAgKOh00AgC9AgAAAA==.Aerîz:BAAANQADCggICAAAAA==.Aetós:BAAANQADCgYIBgAAAA==.',
Ag='Agial:BAAANQAECgYJDQAAAA==.Agôny:BAAANQAECgQJCAABNQAECgYJEAABAAAAAA==.',
Ah='Ahsõka:BAAANQADCgYJEAAAAA==.',
Ai='Aidzboy:BAAANQAECgEIAgABNQAECgUIDgABAAAAAA==.',
Al='Aldin:BAAANQAECgEJAQAAAA==.Alexandrõs:BAAANQAECgcJCAAAAA==.Alfah:BAAANQADCggJHAAAAA==.Aliatris:BAAANQAECgQIBgAAAA==.Alicia:BAAANQADCgUIBQAAAA==.Alkamay:BAAANQAECgQJBwAAAA==.Allor:BAAANQAECgEJAQAAAA==.Allorpally:BAAANQAECgcIDwAAAA==.Altofmyalt:BAAANQADCgIJAgAAAA==.Aluii:BAABNQAECoEkAAIDAAkKwh+IHAAOAwADAAkKwh+IHAAOAwAAAA==.Alyssana:BAAANQAECgQJCgAAAA==.Alyssius:BAAANQAECgUIBQAAAA==.Alyxdt:BAAANQABCgQIBAAAAA==.Alyxpally:BAAANQAECgEIAQAAAA==.Alyxpants:BAAANQAECgYJDAAAAA==.',
Am='Amakhozi:BAAANQADCgYIDAAAAA==.Amaniguyxd:BAAANQAECgMIAgAAAA==.Amaria:BAAANQAECgYICwAAAA==.Ambulance:BAAANQAECgcIDAAAAA==.Amity:BAAANQADCgUIBQAAAA==.',
An='Aneth:BAAANQAECgUIBwAAAA==.Angelsfly:BAAANQAECgUIBwAAAA==.Angæl:BAAANQAECgMJBQAAAA==.Annallyne:BAAANQADCgUIBQABNQAECgcIGgAEAJIZAA==.Anti:BAAANQADCgQIBAAAAA==.Antifridge:BAAANQAECgEJAQAAAA==.Anultrun:BAAANQAECgIIBAAAAA==.',
Ar='Arabellaa:BAAANQAECgQIBAAAAA==.Arcanarot:BAAANQADCgEIAQAAAA==.Archaeøn:BAAANQADCggJHQAAAA==.Arcyandor:BAAANQADCgcJEAAAAA==.Arity:BAAANQAECgEIAQAAAA==.Arkanote:BAAANQAECgYJEwAAAA==.',
As='Asapxmello:BAAANQADCgMIAwAAAA==.Ashmear:BAAANQAECgIJAgAAAA==.Ashê:BAAANQAECgMIAgABNQAECgcICAABAAAAAA==.Astalon:BAAANQABCgYJEQAAAA==.',
At='Athreos:BAAANQAECgUIBwAAAA==.Atüned:BAABNQAECoEZAAMFAAcK1SMLFwDVAgAFAAcK1SMLFwDVAgAGAAEKchMJHQE2AAAAAA==.',
Au='Auraeus:BAAANQADCgQIBAAAAA==.Aurelia:BAABNQAECoEpAAMHAAgKeg1aVAChAQAHAAcKuQ5aVAChAQAIAAIK/AWGuQBrAAAAAA==.Aurelía:BAAANQADCggJCAAAAA==.',
Av='Avelane:BAAANQAECgYIEQAAAA==.Averia:BAAANQABCgIJAgAAAA==.',
Az='Azrukia:BAAANQADCgcIBwAAAA==.Azubasaurus:BAABNQAECoEhAAMJAAkKEiQhAQCwAwAJAAkKEiQhAQCwAwAKAAIKCBt0JACgAAAAAA==.',
Ba='Baeladar:BAAANQADCgYJBgAAAA==.Baelor:BAAANQAECgIJAgAAAA==.Baggageho:BAAANQADCgEIAQAAAA==.Bakrah:BAAANQADCgUIBQAAAA==.Balan:BAAANQAECgYJDgAAAA==.Balerion:BAAANQAECgMIBAAAAA==.Barback:BAAANQABCgcIDgAAAA==.Barkstard:BAABNQAECoEgAAMLAAkKOhaKIQBhAgALAAgKfxiKIQBhAgAMAAMKvxInMwDVAAAAAA==.Barleyalive:BAAANQADCgEIAQAAAA==.Battleaxe:BAAANQAECgQIBQAAAA==.',
Be='Belarii:BAAANQAECgQIBAAAAA==.Bellonae:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Belmenth:BAAANQADCgMIBAAAAA==.Bendecida:BAAANQAECgIIAgABNQAECgUJCQABAAAAAA==.Benington:BAAANQAECgYJCwAAAA==.Benn:BAACNQAFFIEOAAMNAAQKpw26BgDeAAANAAMKsQ66BgDeAAAOAAEKigpXIQAmAAA1AAQKgTMAAw0ACQp+JfMBALgDAA0ACQp+JfMBALgDAA8AAgpKH2B2AI4AAAAA.Bergarr:BAAANQADCgQJBAAAAA==.',
Bh='Bhyta:BAAANQAECgcIDAAAAA==.',
Bi='Bishopbob:BAAANQADCgcIBwAAAA==.Bit:BAAANQADCgQIBAAAAA==.Bitingholes:BAABNQAECoEcAAIQAAgKdAXFWgBtAQAQAAgKdAXFWgBtAQAAAA==.',
Bj='Bjartastrasz:BAAANQAECgQJBgAAAA==.Bjorc:BAAANQADCgQJBAAAAA==.Bjoriannm:BAAANQAECggIBAAAAA==.',
Bl='Blackroot:BAAANQADCgIIAQAAAA==.Bladetwo:BAABNQAECoEbAAIEAAgK+iNOCQBiAwAEAAgK+iNOCQBiAwAAAA==.Blaumeux:BAAANQADCgYIBgAAAA==.Blazine:BAAANQABCggJCwAAAA==.Bliksem:BAAANQADCggICAAAAA==.Bliss:BAAANQADCggIFQAAAA==.Bloodaddict:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Bloodflaps:BAAANQADCgEIAQAAAA==.Bluerock:BAAANQADCggIDQABNQAECgcIEwABAAAAAA==.Bluesham:BAAANQAECgMJBQAAAA==.',
Bo='Bocko:BAAANQAECgEIAQAAAA==.Bogblant:BAABNQAECoEnAAILAAgKIxlpLAACAgALAAgKIxlpLAACAgAAAA==.Bowsbfrhoez:BAABNQAECoErAAIEAAgKtBltLwB1AgAEAAgKtBltLwB1AgAAAA==.Boyaka:BAAANQAECgMIAwABNQAECgQIBgABAAAAAA==.',
Br='Branbeard:BAAANQAECgEIAgAAAA==.Brokkr:BAAANQADCgEIAQAAAA==.Brushbuffalo:BAAANQAECgIIBAABNQAECgQIBQABAAAAAA==.',
Bu='Bubblëøseven:BAAANQAECgYICQABNQAECggIBAABAAAAAA==.Bundie:BAAANQAECgYICQAAAA==.Burdhammer:BAAANQADCgYICwABNQAECgYJEQABAAAAAA==.',
['Bë']='Bëllädonna:BAAANQADCggJKwAAAA==.',
['Bö']='Böhseronkel:BAAANQABCgEIAQAAAA==.',
Ca='Cactus:BAABNQAECoE7AAIRAAkKdR4wOQDgAgARAAkKdR4wOQDgAgAAAA==.Cardoney:BAAANQAECgUIEQAAAA==.Cariah:BAAANQAECgYJEgAAAA==.Catashax:BAAANQADCgcJGAAAAA==.',
Cd='Cdkit:BAABNQAECoErAAISAAgKfxXyCQAbAgASAAgKfxXyCQAbAgAAAA==.',
Ce='Celestè:BAAANQADCggIFgAAAA==.',
Ch='Chasstise:BAAANQAECgQIBQAAAA==.Chazze:BAAANQAECgEJAQAAAA==.Cheazdruid:BAAANQADCgQJBAAAAA==.Cheggery:BAAANQAECgEJAQAAAA==.Chikubiz:BAAANQAECggICAAAAA==.Chillet:BAAANQADCggJDgAAAA==.Chirp:BAAANQADCgIIAgABNQAECgQJBwABAAAAAA==.Chirpe:BAAANQAECgQJBAABNQAECgQJBwABAAAAAA==.Chokehan:BAAANQABCgEIAQAAAA==.Chubbypope:BAAANQAECgIIAgABNQAECgkJHAATAAglAA==.',
Ci='Cinderi:BAAANQADCgYIBgABNQADCgMJAwABAAAAAA==.Cindrick:BAACNQAFFIEKAAIJAAMKVg2FCQDdAAAJAAMKVg2FCQDdAAA1AAQKgSwAAgkACQokH04DAGMDAAkACQokH04DAGMDAAAA.',
Cl='Clessta:BAAANQAECgIJBAAAAA==.Cloudmagus:BAAANQADCgIIAgAAAA==.Cloudmonk:BAAANQAECgcIEAAAAA==.Clownworld:BAAANQADCgcIBQABNQAECgMJDAABAAAAAA==.Clynefate:BAAANQADCgIIAgAAAA==.',
Co='Coffêê:BAABNQAECoEbAAIIAAgKbyKiDgAUAwAIAAgKbyKiDgAUAwAAAA==.Coggers:BAAANQAECgQJBAAAAA==.Coldbringer:BAAANQAECgcIDAAAAA==.Coldpalmer:BAAANQAECgQIBAABNQAECggIFwADACQTAA==.Coleostrasz:BAAANQADCgQJBAAAAA==.Conkoura:BAAANQAECgEIAgAAAA==.Conzriest:BAAANQAECgEJAQAAAA==.Corastrasza:BAAANQAECgMJAwAAAA==.Courtan:BAAANQADCgYJBgAAAA==.',
Cr='Cresentmoon:BAAANQADCggJGQAAAA==.Crimsonmage:BAAANQAECgUICgAAAA==.Crowchild:BAAANQADCgQIBAAAAA==.',
Ct='Ctrlaltdel:BAAANQADCgUJCgAAAA==.',
Cu='Cursedlight:BAAANQAECgcIDwAAAA==.',
Cy='Cynnal:BAAANQAECgcIBwAAAA==.',
Da='Daazkul:BAAANQADCgYIBgAAAA==.Dadoinkle:BAAANQADCgIIAgAAAA==.Daemos:BAAANQADCgUICQAAAA==.Dahj:BAAANQAECgMJBQAAAA==.Dalanar:BAAANQAECgQIBQAAAA==.Danathjo:BAAANQAECgIIAwAAAA==.Danguinar:BAAANQADCgYIBgAAAA==.Dazius:BAAANQADCgMIBQAAAA==.',
Dc='Dclyne:BAAANQAECgUJDQAAAA==.',
De='Deathlydazz:BAAANQADCgQIBAAAAA==.Deathtainted:BAAANQAECgYIEAAAAA==.Debris:BAAANQAECgYJDAAAAA==.Dedmongrel:BAAANQAECgQIBwAAAA==.Delina:BAAANQADCgIIAgAAAA==.Delây:BAAANQAECgQIBQAAAA==.Demonicmonk:BAAANQADCggICAABNQAFFAYJDgAUAFwbAA==.Dengar:BAAANQAECgYICgAAAA==.Desyphium:BAACNQAFFIEGAAIGAAQKehA/BgA9AQAGAAQKehA/BgA9AQA1AAQKgSAAAwYACQqZImsTADwDAAYACQqZImsTADwDABUAAQpKIDFAAFsAAAAA.Deviltrigger:BAAANQADCgUJCAAAAA==.Devonar:BAAANQAECgQIBAAAAA==.Devorra:BAAANQADCggJGwAAAA==.Deweysan:BAAANQAECgIIAwAAAA==.Dex:BAACNQAFFIEHAAIIAAMKJhnvCAAOAQAIAAMKJhnvCAAOAQA1AAQKgTMAAggACQryIUwMACkDAAgACQryIUwMACkDAAAA.',
Di='Direforge:BAAANQAECgUICQAAAA==.Disreputable:BAAANQADCgUIBAAAAA==.',
Dk='Dkaillou:BAAANQADCgMJAwAAAA==.',
Do='Doccoddle:BAAANQADCgUIBQAAAA==.Dogzofwar:BAAANQADCgIIAgAAAA==.Doovezr:BAAANQADCgEIAQAAAA==.',
Dr='Dracarsynimz:BAEANQAECgQIBAAAAA==.Dracothyr:BAAANQAECgQJCAAAAA==.Draemon:BAABNQAECoE/AAIWAAgK6yXKAAB5AwAWAAgK6yXKAAB5AwAAAA==.Draezual:BAAANQADCgYIBgAAAA==.Dragonhead:BAACNQAFFIEVAAIXAAcKwyQuAAD1AgAXAAcKwyQuAAD1AgA1AAQKgR8AAxcACQqqJUICAL8DABcACQqqJUICAL8DABgABgpoIKEjANQBAAAA.Drannith:BAAANQAECgMIBAAAAA==.Drasston:BAAANQADCgEIAQABNQAECggIFwADACQTAA==.Drastiricka:BAAANQADCgcJEgAAAA==.Dreadlocksta:BAAANQADCgMJAwAAAA==.Dreamer:BAAANQADCggJEgAAAA==.Drinkwater:BAAANQAECgMJDAAAAA==.Drizztdemon:BAAANQAECgIJAgABNQAFFAUJDQAZAOMfAA==.Drucaila:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Druidss:BAAANQADCgYIBgABNQAECggIGwAaAFIiAA==.Drunkenpel:BAAANQADCgUIBQAAAA==.',
Du='Dudesrock:BAAANQAECgYIEgAAAA==.Duty:BAAANQADCgMIAwAAAA==.',
Dy='Dynam:BAAANQAECgUJBgAAAA==.',
['Dë']='Dëmönatrix:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
['Dî']='Dîv:BAABNQAECoEjAAIRAAkK3h4HJwAeAwARAAkK3h4HJwAeAwAAAA==.',
['Dö']='Döinkle:BAAANQADCgcIBwAAAA==.',
Ea='Eatduhpupu:BAAANQAECgUIDgAAAA==.',
El='Elclapo:BAAANQADCgUIBQABNQAECgYIDQABAAAAAA==.Elfhelm:BAAANQAECgMJBQAAAA==.Elipsis:BAAANQAECgIIAgAAAA==.Ellisinor:BAAANQAECgEIAQAAAA==.Eluneschosen:BAAANQAECgUJAgAAAA==.Elured:BAAANQAECgYJEAAAAA==.',
Em='Embermist:BAAANQAECgMJBQAAAA==.Emliy:BAAANQAECggIEQAAAA==.Emogirl:BAAANQAECgEIAQABNQAECggIHAAEAHkmAA==.',
En='Endee:BAAANQADCgQIBwAAAA==.Enerchifists:BAAANQAECgcIDwAAAA==.',
Ep='Ephesian:BAAANQAECgUICAAAAA==.',
Er='Erakiel:BAAANQADCgYIBgAAAA==.Ero:BAAANQADCgEIAQABNQAECgcIEwABAAAAAA==.Erobas:BAABNQAECoEhAAIDAAcKoRFmcQC3AQADAAcKoRFmcQC3AQAAAA==.Erodan:BAAANQAECgcIEwAAAA==.',
Es='Esserian:BAAANQAECgMJBwAAAA==.Estarae:BAABNQAECoEnAAQbAAgK0hIzMwD/AAAbAAYKsw0zMwD/AAAQAAIKfAKfqgA0AAACAAEKggFiIgAQAAAAAA==.Esthane:BAAANQAECgYIDQAAAA==.',
Et='Eternaldawn:BAAANQADCgYIDAAAAA==.Ethereall:BAAANQAECgIJAgAAAA==.',
Eu='Euphuzadan:BAABNQAECoEbAAIaAAgKUiJxEQACAwAaAAgKUiJxEQACAwAAAA==.',
Ev='Eveliala:BAAANQABCgMIAwAAAA==.Everhealer:BAABNQAECoEwAAICAAgKnBr8AgCEAgACAAgKnBr8AgCEAgAAAA==.Evienarian:BAAANQABCgUICwAAAA==.Evillumber:BAAANQAECgMJBAAAAA==.',
Ex='Exiledemon:BAAANQAECgYICgAAAA==.Exterminatus:BAAANQAECgYIBgABNQAECgcIDwABAAAAAA==.',
Ey='Eyéspy:BAAANQAECgYIBgAAAA==.',
Fa='Faldor:BAAANQABCgIIAgAAAA==.Falewin:BAAANQADCgEIAQAAAA==.Fatonement:BAAANQAECgYJBwABNQAECgcJBwABAAAAAA==.Fauvm:BAABNQAECoEZAAIRAAcKfBZ+gQAUAgARAAcKfBZ+gQAUAgAAAA==.',
Fe='Feanassa:BAAANQAECgUICQAAAA==.Fearwood:BAAANQADCggIDgAAAA==.Felfeet:BAAANQAECgQJBQAAAA==.Felmytats:BAAANQADCgYIBgAAAA==.Fenrisfox:BAAANQADCggJIQAAAA==.Ferrousman:BAAANQAECgEIAQAAAA==.',
Fi='Fishing:BAABNQAECoEdAAIHAAkKPiM9BgCcAwAHAAkKPiM9BgCcAwAAAA==.',
Fl='Flaviousqt:BAAANQAECgQJBQAAAA==.Flavorofkrel:BAAANQADCggICAABNQAECggIGwARADIdAA==.Flekzakzak:BAAANQAECgcJEAAAAA==.Flekzugzug:BAAANQADCgcICwABNQAECggIFQAPAFQeAA==.Flezappezix:BAABNQAFFIEJAAIHAAQK6B6iDgC1AAAHAAQK6B6iDgC1AAAAAA==.Florota:BAAANQADCgUIBQAAAA==.Fluffpriest:BAABNQAECoEbAAMQAAkKXhbMMwAjAgAQAAkKXhbMMwAjAgACAAcKLgmyCQBaAQAAAA==.',
Fo='Fong:BAAANQAECgIIAgABNQAFFAUJDAAJAAIUAA==.Forald:BAAANQAECgQJBAAAAA==.Forezyn:BAAANQADCgYIBgAAAA==.Forman:BAACNQAFFIEKAAMNAAUKVCPxAQCbAQANAAQKkCLxAQCbAQAPAAMKgh3OBAAiAQA1AAQKgRoAAw8ACQosJNcNABUDAA8ACAofJdcNABUDAA0ABwohI4IPALYCAAAA.',
Fr='Fragmented:BAAANQADCggIEAAAAA==.Fragments:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Frair:BAABNQAECoFKAAIMAAkKZhPQEABdAgAMAAkKZhPQEABdAgAAAA==.Frostienips:BAAANQAECgMIAwAAAA==.Frostiness:BAAANQADCgYICwAAAA==.Frostmagee:BAAANQADCggJHAAAAA==.Frostyemliy:BAAANQADCgQIBQAAAA==.',
Fu='Fubár:BAAANQAECgcJEwAAAA==.Fupanchoo:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Furbulous:BAAANQADCgYIBgAAAA==.',
Ga='Garthurn:BAAANQADCgYJDAAAAA==.Gaskull:BAAANQAECgQICAAAAA==.Gaybacon:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Ge='Gemli:BAAANQABCgQJBAAAAA==.Geno:BAAANQADCggICAABNQAECgkJKgADAKwkAA==.',
Gh='Ghostsaber:BAAANQAECgQJBgAAAA==.',
Gi='Giddykitty:BAAANQADCggIFgAAAA==.Gimballock:BAAANQAECgMJBAAAAA==.Gisakagda:BAAANQADCgQIBAAAAA==.Gital:BAAANQAECgEJAQAAAA==.',
Gl='Glennthehen:BAAANQAECgEIAQAAAA==.',
Go='Goatvier:BAACNQAFFIEGAAIcAAQKVyVSAAC+AQAcAAQKVyVSAAC+AQA1AAQKgR8AAhwACQoaJjYAAOwDABwACQoaJjYAAOwDAAAA.Goblinator:BAAANQAECgYJCgAAAA==.Golojo:BAAANQADCgQICAAAAA==.Goodenia:BAAANQADCgQIBgAAAA==.Googoo:BAAANQAECgEIAwAAAA==.Goosef:BAAANQAECgQIBQAAAA==.Gopro:BAAANQADCgYIDwAAAA==.Gorbag:BAAANQADCgYJBwAAAA==.Gorhowl:BAAANQAECgcJEwAAAA==.Gorli:BAAANQADCggIHgAAAA==.Gottoloveit:BAAANQADCgYIBgABNQAECgMJAwABAAAAAA==.Gottolurveit:BAAANQAECgMJAwAAAA==.Gozunholnite:BAAANQADCgEIAQAAAA==.',
Gr='Gracela:BAAANQADCggIEAAAAA==.Grantuss:BAABNQAECoEYAAMGAAkKTSLvGQAPAwAGAAgKICLvGQAPAwAFAAIKZQjBtgB/AAAAAA==.Gravadin:BAAANQAECgUIBgAAAA==.Great:BAAANQADCgYIBgABNQAECgkJJQAVANgkAA==.Grennu:BAAANQADCggICAAAAA==.Gretchin:BAAANQAECgIIBAAAAA==.Groshlow:BAAANQAECgIIAgAAAA==.',
Gu='Guinness:BAAANQADCgIJAgAAAA==.Gulios:BAAANQAECgMJAwAAAA==.Gunji:BAAANQAECgQICQAAAA==.Guud:BAAANQAECgYJBgAAAA==.',
Gy='Gyukatsu:BAAANQADCgUJBQAAAA==.',
['Gä']='Gändalf:BAAANQAECgQIBgAAAA==.',
['Gó']='Gódmóde:BAAANQADCgEIAQAAAA==.',
Ha='Hadesarrow:BAAANQAECgMJBgABNQAFFAUICwAOAKcaAA==.Hadesblood:BAACNQAFFIELAAIOAAUKpxo7BQCVAQAOAAUKpxo7BQCVAQA1AAQKgSQAAg4ACQoHHxoOAAEDAA4ACQoHHxoOAAEDAAAA.Hakiheal:BAAANQAECgcIEQAAAA==.Hakzert:BAACNQAFFIEMAAIdAAUKUxLUAQChAQAdAAUKUxLUAQChAQA1AAQKgSMAAx0ACQqAHb8EABsDAB0ACQqAHb8EABsDAB4ABwoZCrcoACwBAAAA.Happyfeett:BAAANQADCgQIBAAAAA==.Happyÿeet:BAAANQAECgQIBAAAAA==.Harex:BAAANQAECgYJEAAAAA==.Harlon:BAAANQADCgUJCQAAAA==.Hartcake:BAAANQADCggJDAAAAA==.Haylø:BAAANQADCggICwAAAA==.Hazkalzzak:BAAANQADCgcIDgAAAA==.',
He='Healdewin:BAAANQADCgYICwAAAA==.Hektîc:BAAANQAECgcIBwAAAA==.Hellsgate:BAAANQAECgIIAgAAAA==.Hellshunter:BAAANQAECgYIEQAAAA==.Hemillir:BAAANQAECggIAQAAAA==.Herbaleyes:BAAANQADCgcIAgAAAA==.Hetzlock:BAAANQADCgYIBwAAAA==.Hexalock:BAAANQAECgYIEgAAAA==.Hexavoke:BAAANQADCgQIBAAAAA==.Hexdh:BAAANQADCgYICwAAAA==.Hexdk:BAAANQADCggIDQAAAA==.Hexentjie:BAAANQADCggIIAAAAA==.Hexiemattel:BAAANQAECgQJBQAAAA==.Hexington:BAAANQABCgMIAwAAAA==.Hexpriest:BAAANQAECgQIBgAAAA==.Hextralarge:BAAANQAECgcJBwAAAA==.Hezaq:BAAANQAECgMJBQAAAA==.',
Hi='Himtom:BAAANQADCgIIAgAAAA==.',
Ho='Hollowvoice:BAAANQAECgYJEAAAAA==.Holycheese:BAAANQADCgIIAwAAAA==.Holyviixen:BAAANQAECgYJEQAAAA==.Horacio:BAAANQADCggJIgAAAA==.',
Hu='Hugedps:BAAANQADCgMIAwAAAA==.Humin:BAAANQADCgUIBgAAAA==.Huntingness:BAAANQADCgYJBgAAAA==.Huntymcshoot:BAAANQAECgEIAgABNQAECggIBAABAAAAAA==.Huntér:BAAANQAECgYIBwAAAA==.',
['Hù']='Hùntrèss:BAAANQAECgMJBAAAAA==.',
Ic='Icdedpple:BAAANQAECgYJDQAAAA==.Icymama:BAAANQADCggJGAAAAA==.',
Id='Idevouryou:BAAANQADCgYIEQAAAA==.',
Ig='Iggie:BAAANQADCgcIBwAAAA==.',
Il='Illicet:BAAANQADCgcIEAAAAA==.',
Im='Imchirp:BAAANQAECgQIBgABNQAECgQJBwABAAAAAA==.Imicedup:BAAANQAECgQIBQAAAA==.Impblaster:BAAANQAECgEJAQABNQAECgQJDAABAAAAAA==.',
In='Inarius:BAAANQAECgQJCwAAAA==.Incompetent:BAAANQADCgcIFgAAAA==.Indriná:BAAANQAECgYJEQAAAA==.Inflictor:BAAANQAECgYJEAAAAA==.Insanenachos:BAAANQAECgUICgAAAA==.Inumbra:BAAANQAECgQJBgAAAA==.',
Ir='Ironknee:BAABNQAECoEYAAICAAgKHhk5AwBzAgACAAgKHhk5AwBzAgAAAA==.',
Is='Isterra:BAAANQADCgUJBQAAAA==.',
It='Ithareos:BAAANQAECgQIBgAAAA==.',
Iv='Ivybrew:BAAANQADCgYICAAAAA==.Ivycinders:BAAANQAECgIJAgAAAA==.',
Iz='Izate:BAAANQAECgQIBgAAAA==.Izulia:BAAANQAECgYIDQAAAA==.Izulid:BAAANQADCgYICAABNQADCgcJEwABAAAAAA==.',
Ja='Jaathen:BAAANQADCgYIBQAAAA==.Jabiraka:BAAANQADCggJEAAAAA==.Jackiexx:BAAANQAECgIIBAAAAA==.Jaedrae:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Jahwe:BAAANQABCgMJBAAAAA==.Jakestanater:BAAANQADCggIFQAAAA==.Jassel:BAAANQAECgQJBwAAAA==.Jazmeine:BAAANQADCgIIAgAAAA==.',
Jd='Jdubbs:BAAANQADCgIJAgAAAA==.',
Je='Jestër:BAAANQAECgEJAQABNQAECgQJBAABAAAAAA==.',
Ji='Jimjam:BAAANQADCggIFQAAAA==.Jinx:BAABNQAECoEnAAMfAAgKxA+FEQDGAQAfAAcKdwyFEQDGAQAHAAgKRQ4AAAAAAAAAAA==.',
Jj='Jjester:BAAANQAECgQJBAAAAA==.',
Jl='Jlabinos:BAAANQAECgQJBAABNQAECgYJDgABAAAAAA==.Jlaby:BAAANQAECgYJDgAAAA==.',
Jp='Jpxhunter:BAAANQAECggICgAAAA==.',
Ju='Juicei:BAAANQAECgYIEAAAAA==.Julint:BAAANQADCgYIBgAAAA==.',
Jw='Jw:BAAANQAECggIAwAAAA==.',
['Jë']='Jëster:BAAANQADCgEJAQABNQAECgQJBAABAAAAAA==.',
Ka='Kaesoron:BAABNQAECoEhAAIaAAgKNhl6MQBZAgAaAAgKNhl6MQBZAgAAAA==.Kagéslammer:BAAANQADCggIGgAAAA==.Kaiser:BAAANQAECgUICgAAAA==.Kanundrum:BAAANQAECgQJBwAAAA==.Karaxynn:BAABNQAECoEeAAIYAAgKNh1YDgDQAgAYAAgKNh1YDgDQAgAAAA==.Karmasnightt:BAAANQADCgYIEAAAAA==.Kaulder:BAAANQAECgEIAQAAAA==.',
Ke='Kebabyy:BAABNQAECoEbAAMHAAcKhhW2TAC/AQAHAAYKChe2TAC/AQAIAAUKhRpiXgByAQAAAA==.Keeze:BAAANQADCgMJBAABNQAECggJGwAbAEMLAA==.Keheia:BAAANQADCgYICQAAAA==.Keilna:BAAANQADCgQJBAAAAA==.Keintotdoch:BAAANQADCgQIBAAAAA==.Kelil:BAAANQADCgcIDQAAAA==.',
Kh='Khacey:BAAANQAECgMJBQAAAA==.Khodii:BAAANQAECgQJCQAAAA==.Khoho:BAAANQAECgQIBQAAAA==.Khrøne:BAAANQAECgcJEAAAAA==.Khursed:BAAANQADCgYIBgAAAA==.Khyra:BAAANQAECgEJAQAAAA==.',
Ki='Killsaw:BAAANQABCgIIAgAAAA==.Kity:BAAANQAECgIJAwAAAA==.',
Kn='Knail:BAAANQAECgIIAwAAAA==.Knickyou:BAAANQADCgYJCAAAAA==.',
Ko='Kombatkoala:BAAANQADCgIIAgAAAA==.Konoko:BAAANQAECgEIAgAAAA==.Konokö:BAAANQADCgUJBQABNQAECgEIAgABAAAAAA==.',
Kr='Kreuzschlitz:BAAANQAECgEIAQAAAA==.Kreztek:BAAANQADCgQIBAAAAA==.Krin:BAAANQADCgIIAgAAAA==.Krinksdk:BAAANQAECgQJBQAAAA==.Krippg:BAAANQADCgIIAgABNQAECggIGQADAI0ZAA==.Kripwar:BAABNQAECoEZAAIDAAgKjRnMQQBgAgADAAgKjRnMQQBgAgAAAA==.Krizkin:BAAANQAECgQJBQAAAA==.Krugg:BAAANQAECgEJAQAAAA==.',
Ku='Kungpao:BAAANQAECgUJBQAAAA==.Kurono:BAAANQADCgUJBQAAAA==.',
Ky='Kynhark:BAAANQADCgQJDwAAAA==.Kyoudo:BAABNQAECoEnAAMgAAgKKBrWBgAOAgAgAAcKYBfWBgAOAgADAAgKjxUOrQD7AAAAAA==.',
La='Laelha:BAAANQADCgUIBQAAAA==.Lasalia:BAAANQADCgUJBQAAAA==.Latricia:BAAANQADCggJEAAAAA==.Laurél:BAAANQAECgUJDwAAAA==.Layonpaws:BAABNQAECoEtAAMVAAcKmiLjCwBnAgAVAAYKiSPjCwBnAgAGAAcK+RrLUgALAgAAAA==.',
Le='Lecked:BAAANQAECgMJBQAAAA==.Leggodex:BAAANQAECgQIBQAAAA==.Leighandra:BAAANQADCggJGQAAAA==.Lemures:BAAANQAECgYJDAAAAA==.Leonà:BAAANQAECgUICQAAAA==.',
Li='Lidera:BAAANQADCggIDQAAAA==.Liebspawn:BAAANQAECgEIAQAAAA==.Lightdefence:BAAANQADCgMIAwABNQAECgIIBQABAAAAAA==.Lightreign:BAAANQAECgQIBgAAAA==.Linarisa:BAABNQAECoEXAAIhAAUKrhvwKAB+AQAhAAUKrhvwKAB+AQAAAA==.Liquidate:BAAANQAECgUJDQAAAA==.Litori:BAAANQAECgUIDAAAAA==.Littlepaly:BAAANQABCgQJBAAAAA==.',
Ll='Llux:BAAANQADCggIDAAAAA==.',
Lo='Loft:BAAANQADCgYIBgAAAA==.Lookatmoi:BAABNQAECoEhAAIGAAgKxBA3XwDhAQAGAAgKxBA3XwDhAQAAAA==.Looksmaxxor:BAAANQAECggIEQAAAA==.Loryn:BAAANQAECgcJEwAAAA==.',
Lu='Lucarro:BAAANQAFFAEIAQABNQAFFAMJCgAJAFYNAA==.Luciousmaxim:BAAANQADCgYIBgAAAA==.Lumbajack:BAAANQAECgQIDgAAAA==.Lunavale:BAAANQAECgcICwAAAA==.',
Ly='Lyraesel:BAAANQAECgEIAQABNQAECgYIEQABAAAAAA==.Lytemup:BAAANQAECgIIAgAAAA==.',
['Lä']='Läkan:BAAANQAECgEIAQAAAA==.',
['Lù']='Lùcifer:BAAANQAECgEJAQABNQAECggIIgAOABcdAA==.',
Ma='Maddiexi:BAAANQADCgUIBQABNQAECgcIGgAEAJIZAA==.Maenir:BAAANQADCggIDwAAAA==.Magnytize:BAAANQAECgUJCAAAAA==.Magoose:BAAANQAECgcJDwAAAA==.Mags:BAABNQAECoEhAAILAAgKjxmKIABqAgALAAgKjxmKIABqAgAAAA==.Majinboom:BAAANQAECgQIBAAAAA==.Maldred:BAAANQADCggIFAABNQAECgcIGQAFANAcAA==.Maldreds:BAABNQAECoEZAAIFAAcK0BxuKQBiAgAFAAcK0BxuKQBiAgAAAA==.Manicmonday:BAAANQADCggJFwAAAA==.Marsie:BAAANQAECgUIDAAAAA==.Mashex:BAAANQAECgQJCgAAAA==.',
Me='Medieval:BAAANQAECgYJEAAAAA==.Mediyah:BAAANQADCgYIEwAAAA==.Medusula:BAAANQADCgYIBgAAAA==.Melevany:BAAANQAECgEJAQABNQAECgQIBwABAAAAAA==.Meljira:BAAANQAECgQIBwAAAA==.Melonyummy:BAACNQAFFIEMAAIXAAYKEiZuAACvAgAXAAYKEiZuAACvAgA1AAQKgSIAAhcACQq/JsYAAO4DABcACQq/JsYAAO4DAAAA.Menzel:BAAANQADCgYJCwABNQAECgQJBQABAAAAAA==.Mercior:BAAANQADCgUIBQAAAA==.Merrytear:BAAANQAECgQJBQAAAA==.Mesohorni:BAAANQAECgUJAgAAAA==.Messerian:BAAANQADCgMIAwABNQAECgMJBwABAAAAAA==.',
Mi='Mikarika:BAAANQADCgEIAQAAAA==.Milky:BAAANQAECgEJAQABNQAECgcJFwAFAEcZAA==.Milzey:BAAANQAECgYIEAAAAA==.Mindweaver:BAAANQAECgUICgAAAA==.Miniscule:BAAANQADCggICAAAAA==.Miradin:BAAANQAECgIJAwAAAA==.Mirv:BAABNQAECoEfAAIiAAkK1B7wAAAxAwAiAAkK1B7wAAAxAwAAAA==.Misshapp:BAAANQADCgIIAgAAAA==.Misspickles:BAAANQAECgYJEQAAAA==.Mistakoji:BAAANQAECgUICAAAAA==.',
Mo='Mogwii:BAAANQAECggJAgAAAA==.Moit:BAAANQADCgQJBAAAAA==.Mojomaster:BAAANQAFFAIIAgAAAA==.Mojìto:BAAANQAECgQJCAAAAA==.Monkel:BAAANQADCgEIAQAAAA==.Monkork:BAAANQAECgQIAwAAAA==.Monoblood:BAAANQAECggJAgAAAA==.Monononoke:BAAANQADCgYIDQAAAA==.Monque:BAAANQADCgQIBAAAAA==.Monstershift:BAAANQADCggIDgAAAA==.Moosocalypse:BAAANQADCgUIBQAAAA==.Morella:BAAANQAECgEIAQAAAA==.Morgai:BAAANQABCgQJBAAAAA==.',
Mu='Munta:BAAANQADCgYIFAAAAA==.Munter:BAABNQAECoEXAAIFAAcKRxl2NwAcAgAFAAcKRxl2NwAcAgAAAA==.Mursha:BAAANQAECgIIBQAAAA==.Muted:BAAANQAECgcJBwAAAA==.Muzblue:BAABNQAFFIEFAAIHAAIKzyGODQDMAAAHAAIKzyGODQDMAAAAAA==.Muzw:BAAANQAECgUICwAAAA==.',
My='Mythreem:BAAANQAECgMJAwAAAA==.',
['Mï']='Mïkarika:BAAANQAECgUICAAAAA==.',
Na='Naalaxii:BAABNQAECoEaAAIEAAcKkhmxSAAaAgAEAAcKkhmxSAAaAgAAAA==.Naero:BAAANQAECgQJBQAAAA==.Naerond:BAAANQAECgEIAQAAAA==.Nalfeiin:BAAANQAECgQIDAAAAA==.Narnardk:BAABNQAECoEbAAINAAkKvB7zCAAZAwANAAkKvB7zCAAZAwAAAA==.Narnarx:BAAANQAECgQIBAAAAA==.Natrstorm:BAABNQAECoEnAAISAAgKrSLcBQCcAgASAAgKrSLcBQCcAgAAAA==.Naturised:BAAANQAECgMJBQAAAA==.Naursalla:BAAANQADCggIEgAAAA==.Nawe:BAAANQAECgcJDAAAAA==.',
Ne='Necratia:BAAANQAECgQIBAAAAA==.Neflyn:BAAANQADCggIHwAAAA==.Nemmystrata:BAAANQAECgUIBQAAAA==.Nessaandra:BAAANQAECgYIEQAAAA==.Nestle:BAAANQADCgEIAQAAAA==.Neverdies:BAAANQADCgcIDgAAAA==.',
Ni='Niftage:BAAANQADCgYIFAABNQAECgMJBQABAAAAAA==.Niftana:BAAANQAECgMJBQAAAA==.Nimirie:BAAANQAECgQIBwAAAA==.Nincastro:BAAANQADCgMIAwAAAA==.Nitrofizz:BAAANQABCgIIAgAAAA==.',
No='Noimen:BAAANQAECgQJBgAAAA==.Nokpaladin:BAAANQAECgIIAgABNQAECgUIDQABAAAAAA==.Nokshaman:BAAANQAECgUIDQAAAA==.Noxtard:BAAANQADCggJEAAAAA==.',
Ny='Nyghtware:BAAANQAECgUIBgAAAA==.',
['Nú']='Nútz:BAAANQAECgIIAgAAAA==.',
Ob='Obalo:BAAANQAECgUJBQAAAA==.',
Oc='Ocienianix:BAAANQADCgEIAQAAAA==.',
Od='Odlid:BAAANQADCgYIEwAAAA==.',
Ok='Okazi:BAAANQAECgUJDAABNQAECgYJEAABAAAAAA==.',
Ol='Olafuga:BAABNQAECoEnAAIMAAgKGxuREABhAgAMAAgKGxuREABhAgAAAA==.Oldblood:BAAANQABCgIJAgABNQADCgUIBQABAAAAAA==.',
Oo='Ookolok:BAAANQADCggIDQAAAA==.Oompaloompa:BAAANQABCgQJBAAAAA==.',
Op='Oppressor:BAAANQADCgcJDQAAAA==.',
Or='Orctredies:BAAANQADCgQICAAAAA==.Orianna:BAAANQADCggIFAAAAA==.Ormal:BAAANQADCggJGgAAAA==.',
Os='Osma:BAAANQAECgUJBwABNQAFFAUJDQAZAOMfAA==.Osmess:BAAANQAECgYJEwABNQAFFAUJDQAZAOMfAA==.Osmology:BAACNQAFFIENAAQZAAUK4x/rAgDRAAAaAAMKmhoBCwALAQAZAAIKJSLrAgDRAAAiAAEKPx1bBABZAAA1AAQKgSIABBoACQr0JTYYANcCABoABwrgJTYYANcCABkABgrDGAcTAMEBACIAAQrnFqkdAEMAAAAA.',
Oz='Ozzietree:BAABNQAECoEjAAILAAkKqh+AEgDzAgALAAkKqh+AEgDzAgAAAA==.',
Pa='Paddingtonn:BAAANQADCgcJHAAAAA==.Pandachì:BAAANQAECgUICwAAAA==.Pandamick:BAAANQADCggICgAAAA==.Pandur:BAAANQADCgQIBAAAAA==.Paracadabra:BAAANQADCggJCAABNQAECgkJHAAaAHggAA==.Parallaxia:BAABNQAECoEcAAMaAAkKeCBcOwAwAgAaAAcKMB9cOwAwAgAZAAIK9CTmOAC6AAAAAA==.Paulmedic:BAAANQAECgcIEwAAAA==.',
Pb='Pbjellytime:BAAANQAECgIJBAAAAA==.',
Pe='Peadle:BAAANQAECgEIAQABNQAECggIHAAQAHQFAA==.Persistënce:BAAANQADCgYIBgAAAA==.Petaryzn:BAAANQADCgYIEAAAAA==.',
Ph='Phallics:BAAANQAECgcIEgABNQAFFAUJDQAVAJAaAA==.Phoènix:BAAANQAECgQJCwAAAA==.',
Pi='Pikyx:BAAANQAECgUJCAAAAA==.Pinkrock:BAAANQAECgcIEwAAAA==.',
Pl='Playboicarti:BAAANQAECggIDwAAAA==.Plopperoo:BAAANQAECgYJCwAAAA==.',
Po='Pocaface:BAAANQAECgEJAQAAAA==.Pogmourne:BAABNQAECoFKAAIOAAkKbB3vDwDsAgAOAAkKbB3vDwDsAgAAAA==.Polyform:BAABNQAECoEcAAMUAAgKESMsAwAaAwAUAAgKESMsAwAaAwAjAAEK8xTIIgA+AAAAAA==.',
Pr='Preserved:BAAANQAECgQIBwAAAA==.Priestsen:BAAANQADCgcIEwAAAA==.Prime:BAAANQADCggICAAAAA==.Proteccoleos:BAAANQADCgQIBAAAAA==.Prottyboo:BAAANQADCgcICAAAAA==.',
Pu='Pure:BAAANQADCgEIAQABNQADCggIFAABAAAAAA==.Puru:BAAANQAECgQIBgAAAA==.',
Py='Pyrhus:BAAANQAECgYJEAAAAA==.',
['Pâ']='Pâkerious:BAAANQAECgEIAQAAAA==.',
['Pæ']='Pælstrå:BAAANQAECgYJBgAAAA==.',
['Pè']='Pèppermint:BAAANQAECgYJEAAAAA==.',
Qi='Qicacid:BAABNQAECoEhAAMgAAkK9B/zAQAGAwAgAAgKYSHzAQAGAwADAAYKeBzbYwDlAQABNQAFFAMJCgAJAFYNAA==.',
Ra='Racoondog:BAAANQAECgQIBAABNQAECggIGQADAI0ZAA==.Raehalian:BAAANQADCgcICQAAAA==.Rafedrood:BAAANQAECgUICgAAAA==.Rafemonk:BAAANQAECgUJCQABNQAECgcIEwABAAAAAA==.Rafepally:BAAANQAECgcIEwAAAA==.Raharn:BAAANQADCgYIBgAAAA==.Raiigun:BAAANQAECgYJDAAAAA==.Rakutina:BAAANQADCgUIDwAAAA==.Ramann:BAAANQAECgUJDAABNQAECgYJEAABAAAAAA==.Rampart:BAAANQADCgcIBwAAAA==.Raspberry:BAAANQADCgQIBAAAAA==.Rastianklin:BAAANQADCggJHQAAAA==.Ratbro:BAAANQAECgQJCgAAAA==.Rawrbewbz:BAABNQAECoEeAAIRAAgKBCX+GwBHAwARAAgKBCX+GwBHAwAAAA==.Rawrbutt:BAAANQAECgEIAQABNQAECggIHgARAAQlAA==.Rayburd:BAAANQAECgYJEQAAAA==.Raypejeet:BAABNQAECoEXAAIPAAkKnyLnCQBEAwAPAAkKnyLnCQBEAwAAAA==.Raziiel:BAAANQAECgUJCgAAAA==.',
Rb='Rbed:BAAANQAECgYJDwAAAA==.',
Re='Realhuman:BAABNQAECoEXAAIDAAgKJBMDWwADAgADAAgKJBMDWwADAgAAAA==.Recharge:BAAANQAECgcJEgAAAA==.Redpally:BAAANQAECgIJAgAAAA==.Redrock:BAAANQADCgYIBwABNQAECgcIEwABAAAAAA==.Relinna:BAAANQAECgYIDAAAAA==.Remdelacrem:BAAANQAECgEJAQABNQAECggIIQALAI8ZAA==.Rend:BAAANQADCgMIAwAAAA==.Resly:BAABNQAECoEjAAIeAAkKTx65CQDuAgAeAAkKTx65CQDuAgAAAA==.Reulna:BAAANQADCgIIAgAAAA==.Revolutionix:BAAANQAECgIIBAAAAA==.',
Rh='Rhodie:BAAANQAECgUICgAAAA==.',
Ri='Ricuid:BAAANQAECgMJBQAAAA==.Ridemption:BAAANQAECgUIBAAAAA==.Rifkin:BAAANQADCggJGQAAAA==.Rigamautist:BAAANQAECgUJCwAAAA==.Rightguy:BAAANQADCgYIBgAAAA==.',
Ro='Roadkill:BAAANQADCgYICwAAAA==.Roots:BAAANQAECgQJBQAAAA==.Rotelle:BAAANQADCgMJBQAAAA==.Rottenalbo:BAAANQAECgQJDAAAAA==.',
Ru='Rustyaslock:BAABNQAECoEnAAMaAAgK2QvWcABxAQAaAAgK2QvWcABxAQAZAAEK9wM9agAwAAAAAA==.',
['Rè']='Rèmorseléss:BAAANQAECgQIBQAAAA==.',
Sa='Safy:BAAANQAECgIIAgAAAA==.Saladin:BAAANQAECgQJCAAAAA==.Samhradh:BAAANQAECgEIAQAAAA==.Samixi:BAAANQAECgEJAQAAAA==.Samoid:BAAANQADCgcIDQABNQAFFAQICAAdAGQaAA==.Sanguiniüs:BAAANQAECgQJCwAAAA==.Santhea:BAAANQADCgYICgAAAA==.Sarixz:BAABNQAECoEXAAIHAAcKyRUMQQDyAQAHAAcKyRUMQQDyAQAAAA==.Sarzyb:BAAANQAECgcIEwAAAA==.Sashka:BAAANQAECggIEQAAAA==.Satsuy:BAAANQAECggJAgAAAA==.Savaric:BAAANQADCgYJBgAAAA==.',
Sc='Scott:BAABNQAECoEjAAIDAAgK/xqnOACDAgADAAgK/xqnOACDAgAAAA==.Scrubturkey:BAAANQAECgQIBQAAAA==.Scuntpetz:BAAANQADCggIDQAAAA==.',
Se='Seamonology:BAABNQAECoEVAAIaAAgKvhizOAA7AgAaAAgKvhizOAA7AgAAAA==.Seether:BAAANQAECgIJAgABNQAFFAQJCAATADcYAA==.Seibäh:BAAANQAECgEIAQAAAA==.Seraithe:BAAANQABCgIJBAAAAA==.Seravael:BAAANQAECgQJCAAAAA==.Sethbash:BAAANQADCggIDwAAAA==.',
Sh='Shadowvoice:BAAANQAECgUICAAAAA==.Shallan:BAABNQAECoEaAAMRAAgKZBledQA0AgARAAcK3xledQA0AgAWAAEKBBYuKQBKAAAAAA==.Shamann:BAAANQADCgYIBgABNQAECgUIDgABAAAAAA==.Shapymcshift:BAAANQAECgEIAQABNQAECggIBAABAAAAAA==.Shard:BAAANQADCggJEgAAAA==.Shelemouncy:BAAANQADCgQIBAABNQAECggIHAAQAHQFAA==.Shieldzu:BAAANQADCgcJEwAAAA==.Shlappy:BAACNQAFFIEHAAIOAAMKQR6yCQARAQAOAAMKQR6yCQARAQA1AAQKgUUAAg4ACQpKIPUJADcDAA4ACQpKIPUJADcDAAAA.',
Si='Silversham:BAAANQAECgYJDgAAAA==.Silversnow:BAAANQADCggJFAAAAA==.Silverstaria:BAAANQADCgYIDQAAAA==.Sisha:BAAANQADCgQIAgAAAA==.',
Sk='Skeld:BAAANQAECgUJCwAAAA==.Skiddy:BAACNQAFFIEMAAIJAAUKAhQzBAC0AQAJAAUKAhQzBAC0AQA1AAQKgSIAAgkACQqtIfEEADYDAAkACQqtIfEEADYDAAAA.Skinnypuppy:BAAANQABCgEIAQAAAA==.Skrug:BAAANQAECgUIBwAAAA==.',
Sl='Slysham:BAAANQAECgUICgAAAA==.',
Sm='Smeevil:BAAANQAECgYJEAAAAA==.Smellyfridge:BAAANQADCgQICAABNQAECgEJAQABAAAAAA==.',
Sn='Sneeds:BAACNQAFFIEaAAIOAAUKyx09BAC4AQAOAAUKyx09BAC4AQA1AAQKgUwAAg4ACQqJJCwDAKoDAA4ACQqJJCwDAKoDAAAA.Snowdrifter:BAAANQADCgEIAQAAAA==.Snowhail:BAAANQAECgYJDQAAAA==.',
So='Soal:BAAANQAECgQIBgAAAA==.Soaringsky:BAABNQAECoEeAAIRAAkKLBsEOwDbAgARAAkKLBsEOwDbAgAAAA==.Softfireball:BAAANQADCgYICAAAAA==.Solarflares:BAAANQAECgcIEAAAAA==.Sopheeaa:BAAANQAECgYIDwAAAA==.Soria:BAAANQAECgYIDQAAAA==.Soulblessed:BAABNQAECoEcAAMFAAkKyhl/HgCjAgAFAAgKUBp/HgCjAgAGAAYKkA34kQBPAQAAAA==.Soursop:BAAANQADCgUJCAAAAA==.',
Sp='Sparkychops:BAAANQAECgUIBwAAAA==.Spaztik:BAAANQAECggICwAAAA==.Spectrefive:BAAANQADCgcJCAAAAA==.Spectretwo:BAAANQAECgMJAwAAAA==.Spherical:BAAANQAECgEIAQABNQAECgkJHQAKAIoeAA==.Spknox:BAAANQADCggIIAABNQAECgYIDwABAAAAAA==.Spooklet:BAAANQAECgEIAQAAAA==.Spoonboy:BAABNQAECoEVAAIPAAgKFx7TFQC+AgAPAAgKFx7TFQC+AgAAAA==.',
Sq='Squirtmore:BAAANQAECgQICQAAAA==.Squirtsalot:BAAANQAECgQICQAAAA==.',
St='Starielle:BAAANQAECgIIBQAAAA==.Stark:BAAANQAECgQJDAAAAA==.Steinman:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Stemple:BAAANQAECgUJDgAAAA==.Stereotype:BAAANQADCggICAAAAA==.Stormblessed:BAAANQAECgUJCAAAAA==.Stormfur:BAAANQAECgMIAwAAAA==.Stormyshadow:BAAANQADCggJGgAAAA==.Stubsy:BAAANQADCgQJBAAAAA==.',
Su='Sublet:BAAANQAECgQJBQAAAA==.Subwayy:BAAANQAECgQJDAAAAA==.Sunshÿne:BAAANQAECgEIAQAAAA==.Suunshine:BAABNQAECoEiAAIOAAgKFx1VGQCNAgAOAAgKFx1VGQCNAgAAAA==.',
Sw='Swampÿ:BAAANQAECgEIAQAAAA==.Swordriel:BAAANQAECgYIEAAAAA==.',
Sy='Sybers:BAAANQADCgUIBQAAAA==.Synfal:BAAANQAECgUIDAAAAA==.Syrenn:BAAANQADCgMIBgAAAA==.Syrez:BAAANQAECgUIDwAAAA==.Syrezz:BAAANQAECgEIAQAAAA==.',
Sz='Szeras:BAAANQAECgYJDwAAAA==.',
['Sì']='Sìrsharmìng:BAAANQADCgcIDQABNQAECgUICgABAAAAAA==.',
['Sö']='Söurcream:BAAANQADCggICwAAAA==.',
['Sý']='Sýrézz:BAAANQADCggICAAAAA==.',
Ta='Taemire:BAAANQAECgMIAwABNQAECggIJwAbANISAA==.Tahlia:BAABNQAECoEVAAIIAAgKWhEMRgDTAQAIAAgKWhEMRgDTAQAAAA==.Takaiya:BAAANQAECgUICAAAAA==.Tanglethorn:BAAANQADCgQIBAAAAA==.Tauna:BAAANQADCgQIBAAAAA==.Taur:BAAANQAECgMIAwAAAA==.',
Te='Technosis:BAAANQADCggIGAAAAA==.Techuu:BAACNQAFFIEMAAMDAAYKxw0mBQDcAQADAAYKxw0mBQDcAQAgAAEKYQXXAgBKAAA1AAQKgSIAAgMACQrjIjINAHEDAAMACQrjIjINAHEDAAAA.',
Th='Thade:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.Thatdamdruid:BAAANQAECgYJDQAAAA==.Thekhole:BAAANQAECgYICgAAAA==.Thekrelltoss:BAABNQAECoEbAAIRAAgKMh1jTgCgAgARAAgKMh1jTgCgAgAAAA==.Thoriandis:BAAANQAECgQJBAAAAA==.',
Ti='Tinderella:BAAANQADCgIJAgAAAA==.Tinjam:BAAANQADCgYJBgAAAA==.Tintarella:BAAANQADCgQJBAAAAA==.Titaniumman:BAAANQADCgIJAgAAAA==.',
Tj='Tjirp:BAAANQAECgQIBAABNQAECgQJBwABAAAAAA==.',
To='Tohkna:BAAANQAECgIIAgABNQAECggJHgAdAAslAA==.Torale:BAAANQADCggJFQAAAA==.Tormentar:BAAANQADCgEIAQAAAA==.Totemstout:BAAANQAECgQICAAAAA==.Toteshadow:BAAANQADCgUIBQAAAA==.Tovuk:BAAANQAECgUIDwAAAA==.',
Tr='Tranquilitee:BAAANQAECgUIDAAAAA==.Traumateam:BAAANQADCgYJEAABNQAECgQJBQABAAAAAA==.Trebdk:BAAANQAECgMIBAAAAA==.Trebpal:BAAANQAECgcJDAAAAA==.Treecoleos:BAAANQAECgIJAwAAAA==.Treigha:BAAANQADCggIDwABNQAECggIJwAgACgaAA==.Tripleseven:BAAANQADCgUIBQAAAA==.Triplesix:BAAANQADCggIDgAAAA==.',
Tw='Tweetconic:BAAANQADCggJFwAAAA==.Tweetess:BAAANQADCgEJAQAAAA==.Twothreesix:BAAANQAECgEIAwAAAA==.Twîsted:BAAANQADCggIGAAAAA==.',
Ty='Tyborel:BAABNQAECoEaAAMEAAgK9SIEFAAEAwAEAAgK9SIEFAAEAwAkAAEKmwUDDgAzAAAAAA==.Tydro:BAAANQAECgQJBgAAAA==.Tyranoc:BAAANQAECgUJBQAAAA==.',
Ul='Ulthane:BAAANQADCgUICgAAAA==.',
Us='Usedtobecool:BAAANQAECgYIBwAAAA==.',
Ut='Utopist:BAAANQADCgQIBAAAAA==.',
Va='Vacuumpump:BAAANQAECgQIBAAAAA==.Vaenir:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.Valadria:BAAANQAECgUIDwAAAA==.Valaraz:BAAANQADCgMIAwAAAA==.Valeroth:BAAANQABCgYIBwAAAA==.Valthalus:BAAANQADCgYIDwAAAA==.Valvet:BAAANQAECgMIAwAAAA==.Vanirr:BAAANQAECgEIAgAAAA==.',
Ve='Velerodron:BAAANQADCgcIBwAAAA==.Vellarya:BAAANQAECgMJBQAAAA==.Velthrax:BAABNQAECoEkAAIEAAgKwiWaBwB1AwAEAAgKwiWaBwB1AwAAAA==.Velypsi:BAAANQADCgQICgAAAA==.Velìn:BAAANQADCgYJDgAAAA==.Velín:BAABNQAECoEeAAMDAAgKIxyxOQB/AgADAAgKIxyxOQB/AgAgAAIKVAzQGgBrAAAAAA==.',
Vi='Vilaina:BAAANQADCgEJAQAAAA==.Villeneth:BAAANQADCggIDQAAAA==.Virâl:BAAANQADCgUIBQAAAA==.Vivarius:BAAANQAECggIEgAAAA==.Vividèlity:BAAANQADCggIEgAAAA==.Vizzo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Vo='Vocck:BAAANQABCgEIAgAAAA==.Vock:BAAANQABCgUIBQABNQAECgcIGgARABUZAA==.Vokk:BAAANQADCgYIBgABNQAECgcIGgARABUZAA==.Vozie:BAABNQAECoEaAAIRAAcKFRkagAAXAgARAAcKFRkagAAXAgAAAA==.',
Vr='Vrothraxia:BAAANQAECgMIBAAAAA==.',
Vu='Vulcanos:BAABNQAECoEXAAIRAAgKxRSRcABBAgARAAgKxRSRcABBAgAAAA==.',
Vy='Vynestril:BAAANQADCgUIBQAAAA==.Vyxenn:BAAANQADCgIIAgAAAA==.',
['Vâ']='Vânâ:BAAANQADCgYIBgAAAA==.',
['Vó']='Vóltron:BAAANQADCgYICQABNQAECgQIBAABAAAAAA==.',
Wa='Wackman:BAABNQAECoEVAAIPAAgKVB5MEgDiAgAPAAgKVB5MEgDiAgAAAA==.Wargold:BAAANQADCggICAABNQAECgYJDgABAAAAAA==.Warmfridge:BAAANQAECgEJAQAAAA==.Wartiant:BAABNQAECoEdAAIDAAcKPgkkhgB1AQADAAcKPgkkhgB1AQAAAA==.',
Wh='Whitehall:BAAANQAECgQJBgAAAA==.Whocouldube:BAAANQADCgEJAQAAAA==.Wholegrain:BAAANQAECgEJAgABNQAECgYJEAABAAAAAA==.',
Wi='Windhorn:BAAANQAECgMJBQAAAA==.Windi:BAAANQADCgYJEAAAAA==.Wiro:BAAANQADCgUJBwAAAA==.Wirø:BAAANQADCgIIAwAAAA==.',
Wo='Wobbling:BAAANQAECggJEwAAAA==.Wobblock:BAAANQAECgQJCgAAAA==.Wombee:BAAANQADCggJEwAAAA==.Worldwide:BAAANQADCgMIAwAAAA==.',
Wy='Wylia:BAAANQAECgYICwAAAA==.',
['Wí']='Wíiman:BAAANQAECggIDwAAAA==.',
Xa='Xalath:BAAANQAECgIIAwAAAA==.',
Xe='Xeenah:BAABNQAECoErAAMhAAgKtwUhLgBJAQAhAAcKxgQhLgBJAQAEAAIK1Qj+0wCFAAAAAA==.',
Xi='Xilef:BAAANQAECgMJAwAAAA==.',
Xx='Xxjackie:BAAANQADCgcIDQABNQAECgIIBAABAAAAAA==.',
Xy='Xyz:BAACNQAFFIEIAAMTAAQKNxilAgB0AQATAAQKNxilAgB0AQAlAAEK9BaFDABQAAA1AAQKgRsAAxMACQpxH3wKAOMCABMACQotH3wKAOMCACUABQpvFlIkAFkBAAAA.',
Ya='Yamaka:BAACNQAFFIEMAAIUAAYKxiAiAABoAgAUAAYKxiAiAABoAgA1AAQKgSEAAhQACQoOJm8AAOYDABQACQoOJm8AAOYDAAAA.',
Ys='Yseult:BAAANQAECgQIBgAAAA==.',
Za='Zaarocc:BAAANQAECgYIBgAAAA==.Zaarock:BAABNQAECoElAAMPAAkKzB3XDgAJAwAPAAkKzB3XDgAJAwAOAAEKgRNxlQA5AAAAAA==.Zaishadow:BAAANQAECgYJDQAAAA==.Zandro:BAAANQAECgEJAQAAAA==.Zandrocas:BAAANQADCgIIAgAAAA==.Zanduill:BAAANQADCggIIQAAAA==.Zanhighawen:BAAANQADCggIFgAAAA==.Zansa:BAAANQADCgMIAwAAAA==.Zaraçk:BAAANQAECgUIBQAAAA==.Zayva:BAAANQAECgQJBQAAAA==.',
Ze='Zeali:BAAANQADCgEIAQABNQAECgQJCAABAAAAAA==.Zealthyr:BAAANQAECgQJCAAAAA==.Zeztuknar:BAAANQAECgEJAQAAAA==.',
Zi='Zincberg:BAAANQADCggJGgAAAA==.Ziyn:BAAANQAECgYIEAABNQAECgkJJgAEAN4hAA==.',
Zo='Zorbax:BAAANQAECgEIAQAAAA==.',
Zy='Zykaei:BAABNQAECoEeAAIdAAgKCyUZAwBSAwAdAAgKCyUZAwBSAwAAAA==.',
Zz='Zzeldris:BAAANQAECgUICAAAAA==.',
['Zã']='Zãráck:BAAANQAECgEIAgABNQAECgUIBQABAAAAAA==.',
['Áy']='Áylamao:BAABNQAECoEWAAIXAAUK8gmpPgAFAQAXAAUK8gmpPgAFAQAAAA==.',
['Äa']='Äang:BAAANQAECgQIBAAAAA==.',
['Æc']='Æclipsè:BAAANQADCggJLwAAAA==.',
['Éh']='Éh:BAAANQAECgYJDwAAAA==.',
['Ði']='Ðiesel:BAAANQADCgEIAgABNQAECgcIKgACABkbAA==.Ðisciple:BAABNQAECoEqAAMCAAcKGRupBQDsAQACAAYK0RupBQDsAQAQAAYKjBH+WAB1AQAAAA==.',
['Øb']='Øbiwan:BAAANQADCgYIEAAAAA==.',
['Øc']='Øctavia:BAAANQADCgQIBQAAAA==.',
['ßi']='ßinchicken:BAAANQAECgQIDAAAAA==.',
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
