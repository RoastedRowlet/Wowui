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

local lookup = {'Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Paladin-Retribution','Paladin-Protection','Mage-Arcane','DeathKnight-Unholy','Warrior-Fury','DemonHunter-Havoc','Mage-Frost','Druid-Balance','Evoker-Preservation','DemonHunter-Devourer','Monk-Mistweaver','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Blood','Warlock-Destruction','Druid-Restoration','Shaman-Enhancement','Monk-Windwalker','Priest-Shadow','Warlock-Demonology','Druid-Feral','Hunter-Marksmanship','Monk-Brewmaster',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aadolin:BAABNQAECoEYAAIBAAgKlhzjGwCzAgABAAgKlhzjGwCzAgAAAA==.Aardvarkeggs:BAAANQADCgIJAgAAAA==.',
Ab='Abaddon:BAAANQAECggJAQAAAA==.',
Ac='Acamar:BAAANQADCgYJFAAAAA==.',
Ad='Adeleska:BAAANQAECgYJDQAAAA==.Aderina:BAAANQADCgcJBwAAAA==.Adessa:BAAANQAECgYICQAAAA==.',
Ae='Aellibash:BAAANQADCgIIAgABNQAECgQIBwACAAAAAA==.Aenivath:BAAANQADCgUJCAAAAA==.',
Af='Aftercare:BAAANQAECgIJAgAAAA==.',
Ag='Agnergam:BAAANQADCgcIBwAAAA==.Agorath:BAAANQADCgYJBgAAAA==.',
Ah='Ahsnap:BAAANQADCgUIBAAAAA==.',
Ai='Airygrim:BAAANQADCgEJAQAAAA==.Aisatsana:BAAANQADCgQIBgAAAA==.',
Al='Alexstrasz:BAAANQAECgYICAAAAA==.Alopex:BAAANQAECgUIDAAAAA==.',
Am='Amaellara:BAAANQAECgYIDwAAAA==.Amajiki:BAAANQADCgYJAwAAAA==.',
An='Andrayah:BAAANQABCgMJBAAAAA==.Annorah:BAAANQADCgEIAQAAAA==.Anthathein:BAAANQAECgIIAgAAAA==.',
Ao='Aoda:BAAANQAECgMJBAAAAA==.Aotrom:BAAANQAECgUIBQAAAA==.',
Ar='Aracus:BAAANQADCgEJAQAAAA==.Arcanefire:BAAANQADCgYJBgABNQAECgQJBAACAAAAAA==.Archblade:BAAANQAECgQJCQAAAA==.Aristaana:BAAANQABCgIJAgABNQAFFAIJAwACAAAAAA==.Armagnac:BAABNQAECoEdAAIDAAgKmxluLwB1AgADAAgKmxluLwB1AgAAAA==.Arthias:BAAANQADCgEIAQAAAA==.',
As='Asroldal:BAAANQADCgYJBgAAAA==.Astralkitten:BAAANQADCgQJBAAAAA==.',
At='Atem:BAAANQABCgIIAgAAAA==.Atom:BAAANQAECgYIBgAAAA==.',
Au='Aufare:BAAANQAECgQIBgAAAA==.',
Av='Avarya:BAABNQAECoEYAAIEAAgKxSX6BAB3AwAEAAgKxSX6BAB3AwAAAA==.Averagerat:BAAANQAECgEIAQABNQAFFAcIEgAFALQhAA==.Averagesham:BAAANQAECggJDgABNQAFFAcIEgAFALQhAA==.Averagevoker:BAACNQAFFIESAAMFAAcKtCFRAAB4AgAFAAYK0iJRAAB4AgAGAAEKAxvVBABiAAA1AAQKgSQAAwUACQrvJfoAALgDAAUACQrvJfoAALgDAAYAAQouH9oUAFcAAAAA.Averwine:BAAANQADCgYICAAAAA==.',
Ba='Babychow:BAAANQADCgEIAQAAAA==.Babynimyk:BAAANQAECgUJBwAAAA==.Backyard:BAAANQADCgYJEgAAAA==.Bael:BAAANQAECgMIAwAAAA==.Bahamasoul:BAAANQAECgEJAQAAAA==.Balooi:BAAANQABCgYICQAAAA==.Baraxius:BAAANQABCgEIAQAAAA==.Bashtaz:BAAANQAECggJEAABNQAFFAUICgAHANMcAA==.Basixx:BAAANQAECgMJAwAAAA==.Bayleaf:BAAANQAECgUIEQABNQAFFAcIEgAFALQhAA==.',
Bb='Bbeloree:BAAANQAECgEIAQAAAA==.',
Bd='Bdiotlcth:BAAANQADCgUJBQAAAA==.',
Be='Bearykyns:BAAANQAECgYIEQAAAA==.Beastwarden:BAAANQAECgcJEgAAAA==.Beatrixkiddo:BAAANQADCgYIBgAAAA==.Bejay:BAAANQADCgYIBgABNQAECgcICwACAAAAAA==.Belladar:BAAANQADCgMIAwAAAA==.Belokk:BAAANQADCggICAAAAA==.Bemused:BAAANQAECgEJAQAAAA==.Benpai:BAAANQAECgEIAQAAAA==.Besticle:BAABNQAECoEmAAIIAAkKQiFyDgBmAwAIAAkKQiFyDgBmAwAAAA==.',
Bi='Bigcheddarz:BAAANQADCgMIAwAAAA==.Bigchungass:BAAANQAECgYIBgABNQAFFAIIAgACAAAAAA==.Bigttgothgf:BAAANQAECgUIBAAAAA==.Bilberry:BAAANQABCgQICAAAAA==.Binkie:BAAANQADCgcIEwABNQAECgUICwACAAAAAA==.',
Bj='Bjaculator:BAAANQAECgcICwAAAA==.',
Bl='Blackgranite:BAAANQADCggIDwABNQAECgEJAwACAAAAAA==.Blacklotus:BAAANQAECgIIAgAAAA==.Blayze:BAAANQADCgYIBgAAAA==.Blep:BAAANQAECgYIDQAAAA==.Bloodoath:BAAANQADCgEIAQABNQAECggIIAAJAC0UAA==.Blueheal:BAAANQADCgUICwAAAA==.Bluemilk:BAAANQAECgEIAQAAAA==.Blueshiver:BAAANQAECgIJAwAAAA==.',
Bo='Bombadore:BAAANQADCgYIBgAAAA==.Bonesaw:BAAANQADCgIIAgABNQAECgQICQACAAAAAA==.Booktök:BAAANQAECgUIBwABNQAECgUJEAACAAAAAA==.Bowlinder:BAABNQAECoEaAAMJAAgKuCGwEgAaAwAJAAgKuCGwEgAaAwAKAAgKORYIOgAJAgAAAA==.Boyvine:BAAANQAECgYICQAAAA==.',
Br='Braldar:BAAANQAECgIJAgAAAA==.Branas:BAAANQADCggIEAAAAA==.Braxiss:BAABNQAECoEXAAIDAAcKyBkARQAmAgADAAcKyBkARQAmAgAAAA==.Brilin:BAAANQAECgUIDwAAAA==.Brithio:BAAANQADCgQJAQAAAA==.Broguë:BAAANQAECgEJAgAAAA==.Brokton:BAAANQADCgQIBAAAAA==.Brucarus:BAAANQADCggJCQABNQAECgMJBAACAAAAAA==.Bruce:BAAANQADCgYIBgAAAA==.Brueld:BAAANQAECgIIAwABNQAECggIIAAJAC0UAA==.',
Bu='Bulldozzers:BAAANQADCgUIBQAAAA==.Bullshzitt:BAAANQAECggIAQAAAA==.Bumper:BAAANQADCgcJDAAAAA==.Busin:BAAANQAECgEIAQAAAA==.',
['Bë']='Bënzin:BAAANQADCgYIBgAAAA==.',
['Bî']='Bîllydakîd:BAAANQADCgYIBgAAAA==.',
Ca='Calabag:BAAANQAECgYIBwABNQAECggJGQALAJ8gAA==.Calabloom:BAABNQAECoEZAAILAAgKnyAXBADrAgALAAgKnyAXBADrAgAAAA==.Caland:BAAANQADCgIIAgAAAA==.Calibern:BAAANQADCggIEwAAAA==.Calmm:BAAANQAECgMIAwABNQAFFAIIAgACAAAAAA==.Canthndice:BAAANQAECgEJAQAAAA==.Capncrunchh:BAAANQADCgYIBwAAAA==.Caressaa:BAAANQADCgMJAwAAAA==.Catraxa:BAAANQADCgYIBgAAAA==.Cavalina:BAABNQAECoEgAAMMAAgK3hX9WgDvAQAMAAgKUxD9WgDvAQANAAUKtBhSIABQAQAAAA==.Cavick:BAAANQAECgUJCAAAAA==.Cawnor:BAAANQAECgQICAAAAA==.Caótica:BAAANQADCggJDgAAAA==.',
Ce='Celyanar:BAAANQADCgMJAgABNQAECgUJBQACAAAAAA==.Ceradwyn:BAAANQADCgcJFAAAAA==.',
Ch='Charön:BAABNQAECoEpAAIOAAkKrR8DKAAbAwAOAAkKrR8DKAAbAwAAAA==.Cheezewizard:BAAANQADCgQJBAAAAA==.Chentrocka:BAABNQAECoEpAAIOAAkKDCE2HABGAwAOAAkKDCE2HABGAwAAAA==.Chillberto:BAAANQADCggIEAAAAA==.Chiselin:BAAANQAECgUJCQAAAA==.Chopsui:BAAANQABCgQJBAAAAA==.',
Cl='Clankss:BAAANQADCggIEwAAAA==.Clerikyns:BAAANQADCgcIBwABNQAECgYIEQACAAAAAA==.Clicks:BAAANQADCgMIAwAAAA==.Clics:BAAANQADCggICAAAAA==.',
Co='Coalgrim:BAAANQAECgQJDQAAAA==.Cosmíc:BAAANQAECgEJAQAAAA==.',
Cp='Cptbyakuya:BAABNQAECoEmAAIMAAkKTyNNCgCEAwAMAAkKTyNNCgCEAwAAAA==.',
Cr='Craterbip:BAAANQAECgYJCwAAAA==.Crimsonk:BAAANQADCgYIBgAAAA==.',
Cu='Curoconcum:BAAANQADCgYIBwAAAA==.',
Cy='Cyrub:BAAANQADCgUICwAAAA==.',
Da='Dabrinto:BAAANQADCgYIBgAAAA==.Daedrian:BAAANQAECgUJBgAAAA==.Dallena:BAAANQAECgQIBwABNQAECgUIBAACAAAAAA==.Dankweaver:BAAANQAECgYIEAAAAA==.Daratri:BAAANQAECgIIAgAAAA==.Darktales:BAAANQADCgYIBgAAAA==.Darthxander:BAAANQADCgYJEwAAAA==.Daywrecker:BAAANQAECgQICQAAAA==.Dayyman:BAABNQAECoEaAAINAAgKUB0ACQCtAgANAAgKUB0ACQCtAgAAAA==.Dazuk:BAAANQADCgYIBgAAAA==.',
De='Deathlysham:BAAANQAECgEIAQAAAA==.Deathshroom:BAAANQADCgcJEAAAAA==.Deathsun:BAAANQAECgcJEAAAAA==.Deform:BAAANQAECgUIBQAAAA==.Deianaera:BAAANQADCgQIBAAAAA==.Delldestus:BAAANQAECgEIAQAAAA==.Delmonicó:BAAANQADCgUIBQAAAA==.Demonics:BAAANQADCgYIBgAAAA==.Demonstix:BAAANQAECgUICAAAAA==.Demv:BAAANQADCgIIAgAAAA==.Depressa:BAAANQADCgQIBAABNQAECggIDgACAAAAAA==.Dernius:BAAANQADCggIEQAAAA==.Derran:BAAANQADCgcJBwAAAA==.Despairykyns:BAAANQAECgEJAQABNQAECgYIEQACAAAAAA==.Dethbringa:BAABNQAECoEVAAMHAAcKDw2NLQCHAQAHAAcKDw2NLQCHAQAPAAMKeAc1dACYAAAAAA==.Dewfall:BAABNQAECoEaAAIQAAkKkhphAgDnAgAQAAkKkhphAgDnAgAAAA==.Deylithdreyn:BAAANQAECgEJAQAAAA==.',
Dh='Dhuoth:BAABNQAECoEZAAIRAAgKHiBlDQDuAgARAAgKHiBlDQDuAgAAAA==.',
Di='Diagoraz:BAAANQADCgUIBwAAAA==.Dialtone:BAAANQADCgQIBwAAAA==.Dialtonee:BAAANQADCgMIAwABNQADCgQIBwACAAAAAA==.Digitalbäth:BAAANQADCgUIBQAAAA==.Digoshadow:BAAANQAECgIJAwAAAA==.Dillonharper:BAAANQADCggICAAAAA==.Disgruntld:BAAANQAECgEJAgAAAA==.Disturbd:BAAANQAECgEIAQABNQAECgYIDQACAAAAAA==.Ditdoo:BAAANQAECgEJAQAAAA==.',
Dk='Dkmetcàlf:BAAANQADCggICAAAAA==.',
Do='Donkeymonk:BAAANQAECgUJBQAAAA==.Dorkyspork:BAAANQAECgEIAQAAAA==.',
Dr='Dragonis:BAAANQADCggICAAAAA==.Dravenstone:BAAANQADCgIIAgAAAA==.Dreamerzz:BAAANQADCgYIBwAAAA==.Drovac:BAAANQAECgIJAwAAAA==.Druidxd:BAAANQADCgQIBAAAAA==.Drumittz:BAAANQADCgEIAQAAAA==.Drworm:BAABNQAECoEjAAIHAAgKixtXFAB4AgAHAAgKixtXFAB4AgABNQAECgkJGAAIAAQbAA==.Drääko:BAAANQABCgYJEAAAAA==.Drêdd:BAAANQABCgIJAgAAAA==.',
Ds='Dsonic:BAAANQADCgQIBAAAAA==.',
Du='Dubbies:BAAANQAECgQIBgAAAA==.Durtluz:BAAANQADCgcICAAAAA==.Dustandblood:BAAANQADCgMIAgABNQADCgYIBgACAAAAAA==.',
Dy='Dyrim:BAAANQADCgUICwAAAA==.',
['Dæ']='Dæmonkawlr:BAAANQADCgQIBAAAAA==.',
['Dê']='Dêformjr:BAABNQAECoEXAAMSAAgKKwzxDgBBAQASAAYKGgvxDgBBAQAOAAYKcweg4QA+AQAAAA==.Dêvarim:BAAANQABCgQJBAAAAA==.',
['Dë']='Dëformjr:BAAANQADCgYIBgAAAA==.Dëförmjr:BAAANQAECgQJCAAAAA==.',
['Dú']='Dúbletap:BAAANQADCgYIBgAAAA==.',
Eh='Ehvie:BAAANQADCggJDQABNQAECggJGQATAGYTAA==.',
El='Elbrujo:BAAANQABCggICwAAAA==.Elenii:BAABNQAECoEYAAIEAAgKFBnNLgA9AgAEAAgKFBnNLgA9AgAAAA==.Eleynra:BAAANQADCgIIAgAAAA==.Elstinko:BAAANQADCgUJBQAAAA==.Elybear:BAAANQADCgUIBQAAAA==.Elychan:BAAANQADCgYIBgAAAA==.Elygance:BAAANQAECgIIAgAAAA==.Elÿ:BAABNQAECoEWAAIBAAkKABMPLQBOAgABAAkKABMPLQBOAgAAAA==.',
Em='Emptyside:BAAANQADCggJFwAAAA==.',
En='Enchorxxi:BAAANQAECgQJBgAAAA==.Enetrenazara:BAAANQAECgUIBwAAAA==.Eniar:BAAANQADCgUIBQABNQAECgMIAwACAAAAAA==.Eniaro:BAAANQAECgMIAwAAAA==.Enlonger:BAABNQAECoEdAAIUAAkK0Q1XFAAMAgAUAAkK0Q1XFAAMAgAAAA==.',
Ep='Epicgooner:BAAANQAECgUICQAAAA==.',
Er='Erahm:BAAANQADCgYICwAAAA==.Erahmm:BAAANQAECgMJBQAAAA==.Ergaraskreia:BAAANQADCgIIAgAAAA==.Erielia:BAAANQADCgIIAgABNQADCgYICAACAAAAAA==.',
Es='Esmirelda:BAAANQAECgUJCgAAAA==.Essn:BAACNQAFFIEHAAIVAAMKCSSiBQA7AQAVAAMKCSSiBQA7AQA1AAQKgSoAAhUACQpPJmYAAPkDABUACQpPJmYAAPkDAAAA.',
Eu='Eulune:BAEANQAECgIJAgABNQAECgkJGAAWAOISAA==.',
Ev='Evelynna:BAAANQADCggIFAAAAA==.',
Ex='Exsull:BAAANQAECgQICAAAAA==.',
Fa='Faible:BAAANQADCgMIAwAAAA==.Faithwarrior:BAAANQAECgUIBwAAAA==.Falk:BAAANQAECgEIAQAAAA==.Falron:BAABNQAECoHkAAINAAgKnCVDBgD7AgANAAgKnCVDBgD7AgAAAA==.Fathlia:BAAANQAECggIEQAAAA==.Fazrien:BAAANQABCgMJBAAAAA==.',
Fe='Fezzjin:BAAANQAECgUJCAAAAA==.',
Fi='Filbrust:BAAANQADCgIIAgAAAA==.Fishtanked:BAAANQADCgQIBgAAAA==.Fitzofrage:BAAANQADCgYIBwAAAA==.',
Fl='Flashlights:BAAANQADCgYICQABNQAECgUIBwACAAAAAA==.Fleshbiter:BAAANQADCggJEgAAAA==.Flowingdeath:BAAANQADCgYICQABNQAECgUICQACAAAAAA==.Flowingrage:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.',
Fm='Fmjserval:BAAANQAECgEIAQAAAA==.',
Fo='Fomtoolery:BAAANQABCgUIBQAAAA==.Foot:BAABNQAECoEdAAIIAAkKFB61JQDbAgAIAAkKFB61JQDbAgAAAA==.Forcedk:BAAANQAECgQIBAAAAA==.Forcefaith:BAAANQAECgYJEQAAAA==.',
Fr='Freduardo:BAAANQADCgUIBgAAAA==.Freva:BAAANQAECggJDgAAAA==.Friarfox:BAAANQADCgYJBgABNQAECgUICwACAAAAAA==.Frostfiree:BAAANQAECgEJAgABNQAECggIIAAJAC0UAA==.Fruitpuddle:BAAANQABCgEIAQABNQAECgkJGwAXAJMXAA==.Frøsty:BAAANQADCgEIAQAAAA==.',
Fu='Furlock:BAAANQADCgcJEAAAAA==.Furryhugger:BAAANQAECgcIDAAAAA==.Furstab:BAAANQADCgQIBwAAAA==.',
['Fì']='Fìzzypop:BAAANQADCgEIAQAAAA==.',
Ga='Galepalm:BAAANQAECgQJBAAAAA==.Gambriniss:BAAANQAECgEJAgAAAA==.Gamea:BAAANQAECgYIEAAAAA==.Garloch:BAAANQADCgcIBwAAAA==.Gazrosh:BAAANQADCggJHwABNQAECgQIBwACAAAAAA==.',
Ge='Geladra:BAAANQADCgcIBwABNQAECggIHAAYAJkZAA==.Gemmothy:BAAANQADCgYJCAAAAA==.',
Gi='Gibbychona:BAABNQAECoEcAAIZAAkKuBlmHQBrAgAZAAkKuBlmHQBrAgAAAA==.',
Gl='Glowshroom:BAAANQADCgEIAQABNQADCgcJEAACAAAAAA==.',
Go='Goldlust:BAAANQAECgEJAQAAAA==.Golotak:BAAANQADCgcIBwAAAA==.Gonnagetproc:BAAANQADCggICAAAAA==.Googale:BAAANQADCgIIAgAAAA==.Gordoc:BAAANQAECgMIAwAAAA==.Gothboy:BAAANQADCggICAAAAA==.',
Gr='Graff:BAAANQAECgUJCAAAAA==.Grailed:BAAANQADCgEIAQAAAA==.Gratiana:BAAANQAECgMIAwAAAA==.Gravem:BAAANQADCgUIBQAAAA==.Gravie:BAAANQADCgIIAgAAAA==.Graystaf:BAAANQAECgMIBAAAAA==.Greggorie:BAAANQAECgEIAQAAAA==.Grennan:BAAANQADCggJDQAAAA==.Greyowl:BAAANQADCggJFQAAAA==.Grifflez:BAAANQAECgUJCAAAAA==.Grumpli:BAABNQAECoEXAAIOAAkK6gx3lwDdAQAOAAkK6gx3lwDdAQAAAA==.',
Gu='Guytheshower:BAAANQAECgUJCgAAAA==.Guytoo:BAAANQADCgUJBQAAAA==.',
Gw='Gweilo:BAAANQAECgUIBQAAAA==.',
Ha='Habek:BAAANQADCgQIBQAAAA==.Hamadaver:BAAANQABCgQIBwAAAA==.Handofblood:BAAANQAECgUICQAAAA==.Handymandy:BAAANQAFFAIIAgAAAA==.Harderrock:BAAANQADCgEIAQABNQAECgYICQACAAAAAA==.Hardrockgirl:BAAANQAECgYICQAAAA==.Harmonechi:BAABNQAECoEYAAIaAAcKJhMjEQDVAQAaAAcKJhMjEQDVAQAAAA==.Haveasip:BAAANQAECgIIAgAAAA==.',
He='Healdealer:BAAANQADCgQIBAAAAA==.Healmonbello:BAAANQAECgcIDwAAAA==.Healystix:BAAANQAECgIJAwABNQAECgUICAACAAAAAA==.Hellzcrusade:BAAANQAECgQJBgAAAA==.Henchi:BAAANQADCgIJAgABNQADCgUIFQACAAAAAA==.',
Hi='Higherheal:BAAANQADCgMIAwAAAA==.',
Ho='Hodesh:BAAANQADCgMJAwAAAA==.Holypuuss:BAABNQAECoEeAAMMAAkK+SWxCgCAAwAMAAkKRiOxCgCAAwANAAEKEyWQPQBpAAABNQAFFAIIAgACAAAAAA==.Honeybumms:BAAANQAECgQJCQAAAA==.Hopeslayer:BAAANQADCgcIEQABNQAECggJGQALAJ8gAA==.Hoplitedruid:BAAANQAECgUICgABNQAECgYJBgACAAAAAA==.Hoplitescout:BAAANQAECgYJBgAAAA==.Houndoom:BAAANQADCgYICgAAAA==.',
Ht='Htiál:BAAANQADCgIIAgAAAA==.Htiâl:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.',
Hu='Huntko:BAAANQADCggIEgAAAA==.',
Hy='Hydrokyrios:BAAANQADCgYIBgAAAA==.Hyperthymia:BAABNQAECoEeAAIKAAkK+RhVIACSAgAKAAkK+RhVIACSAgAAAA==.Hyrakka:BAAANQAECgEJAQABNQADCgUIFQACAAAAAA==.',
Ic='Iceeveins:BAAANQADCggICAAAAA==.Icystyx:BAAANQAECgIIAwAAAA==.',
Il='Ilyamurometz:BAAANQAECggJEgAAAA==.',
Im='Immorta:BAABNQAECoEZAAMQAAgKBg78DABZAQAIAAgKoAy/aQDQAQAQAAYKWQ/8DABZAQAAAA==.',
In='Indigokiya:BAAANQAECgUJCQAAAA==.Influencer:BAAANQADCgcJBwAAAA==.Ingesteel:BAAANQADCgEIAQAAAA==.Inodoro:BAAANQAECgcJEAAAAA==.',
Io='Iordgodplaya:BAAANQAECgIJAgAAAA==.',
Ir='Irabmal:BAABNQAECoEeAAIbAAgKZB/mCQDQAgAbAAgKZB/mCQDQAgAAAA==.Iriclaw:BAACNQAFFIEFAAIDAAIKIyEoCwDPAAADAAIKIyEoCwDPAAA1AAQKgSQAAgMACQqWJqoAAPcDAAMACQqWJqoAAPcDAAAA.Ironpanda:BAAANQADCgEIAQAAAA==.',
Is='Isothymia:BAAANQAECgYJEAABNQAECgkJHgAKAPkYAA==.',
It='Itsmepip:BAAANQAECgUJCAAAAA==.',
Ja='Jacoby:BAAANQAECgUIBQABNQAECgkJKQAcAA0lAA==.Jadefires:BAAANQADCgYIDgABNQADCggIGAACAAAAAA==.Jadelite:BAAANQADCggIGAAAAA==.Jaderanger:BAAANQADCgIJAgABNQADCggIGAACAAAAAA==.Janddasham:BAAANQAECgYIDQAAAA==.Janddavoker:BAABNQAECoEqAAIUAAkKTSG4AwBWAwAUAAkKTSG4AwBWAwAAAA==.Jarnbrez:BAAANQADCgMJAwAAAA==.Jawnwick:BAAANQADCgMIAwAAAA==.Jaxo:BAAANQAECgQJBQABNQAECgUIDQACAAAAAA==.',
Jh='Jherri:BAAANQAECgIJAwAAAA==.',
Ji='Jimbeamer:BAAANQAECgEIAQAAAA==.',
Jk='Jkm:BAAANQAECgMIBQAAAA==.',
Jo='Joanexotic:BAAANQAECgUICQAAAA==.Joetothemama:BAAANQADCgYIBgAAAA==.Johnork:BAAANQADCgUIBQAAAA==.Jojolion:BAAANQAECgMIBQAAAA==.',
Jr='Jrocmfka:BAAANQAECgQJBQAAAA==.',
Jt='Jtama:BAAANQADCgUIBwAAAA==.',
Ju='Junefyre:BAAANQADCgEIAQABNQAECgMIBAACAAAAAA==.Juntor:BAAANQADCgcIBwAAAA==.',
Ka='Kaeliin:BAAANQADCgcJDAAAAA==.Kage:BAAANQADCgQIBgAAAA==.Kaiderten:BAAANQAECgEJAQAAAA==.Kailo:BAAANQAECgEIAQAAAA==.Kal:BAAANQADCgUICwAAAA==.Kalorondir:BAAANQADCgQIBAAAAA==.Kamila:BAAANQADCggIDAAAAA==.Kaorí:BAAANQAECgYICQAAAA==.Karatekyns:BAAANQADCgIIAgABNQAECgYIEQACAAAAAA==.Kaselian:BAAANQAECgIIAwAAAA==.Katherwind:BAAANQABCgcIDAAAAA==.Kattara:BAAANQAECgcIEAAAAA==.Kayalanii:BAAANQADCggICAAAAA==.Kayoti:BAAANQADCgEJAQABNQAECgQIBgACAAAAAA==.Kazuhla:BAAANQAECgQICgAAAA==.',
Ke='Keiryn:BAAANQAECgIJAwAAAA==.Kentyrakka:BAAANQAECgIJBAAAAA==.Keyndian:BAAANQADCggJCAAAAA==.',
Kh='Khaotikmeta:BAAANQAECgMIAwAAAA==.Khaotikpyre:BAACNQAFFIELAAIOAAUKKws2DQCKAQAOAAUKKws2DQCKAQA1AAQKgRwAAg4ACQp/GTdTAJICAA4ACQp/GTdTAJICAAAA.',
Ki='Kiffypoo:BAAANQAECgQJBQAAAA==.Kil:BAABNQAECoEdAAMWAAgKRhcgDQA+AgAWAAgKRhcgDQA+AgAdAAYKmgdVKgAaAQAAAA==.Kiljaiden:BAAANQABCgIIAgAAAA==.Kiltree:BAAANQADCgIIAgABNQAECggJHQAWAEYXAA==.Kisho:BAAANQADCgMIAwAAAA==.Kiyoshie:BAABNQAECoEaAAIDAAgKDRJ7QQAyAgADAAgKDRJ7QQAyAgAAAA==.',
Kl='Klanky:BAAANQADCggICAABNQAFFAQIBwAeAFAdAA==.',
Kn='Kn:BAAANQAECgIIAgAAAA==.Kneehighjake:BAAANQADCgYJBgAAAA==.',
Ko='Kobëbeef:BAAANQADCgUIBQAAAA==.Kodiakpax:BAAANQADCgQJCAAAAA==.Kontroll:BAEANQADCgkJGAAAAA==.Kookee:BAABNQAECoEjAAIfAAgKzBo+NgBFAgAfAAgKzBo+NgBFAgAAAA==.Korice:BAAANQAECgUICgAAAA==.',
Kr='Krypticgrip:BAABNQAECoEWAAIZAAkKAhy5EQDZAgAZAAkKAhy5EQDZAgABNQAFFAUICwAOACsLAA==.',
Ku='Kumaa:BAAANQAECgUICAAAAA==.Kunclebun:BAAANQADCgUIBgAAAA==.',
Ky='Kyle:BAAANQAECgEIAwAAAA==.Kylidon:BAAANQADCgYIBgAAAA==.Kynlauriana:BAAANQADCgEIAQAAAA==.',
La='Lalaind:BAAANQADCgYICAAAAA==.Larissa:BAAANQAECgUICwAAAA==.Lathillea:BAAANQAECgQJBQAAAA==.Launchpad:BAAANQADCgQIBAAAAA==.Lazzirus:BAAANQAECgcJEQAAAA==.',
Le='Leedict:BAAANQAECgUJDAAAAA==.Leerøy:BAAANQAECgQICgAAAA==.Leilani:BAAANQADCgYJDQAAAA==.Leinalei:BAAANQADCggICAABNQAECggJGgAOAFEiAA==.Lessii:BAEBNQAECoEeAAIPAAkK+hrGFQC/AgAPAAkK+hrGFQC/AgAAAA==.Leyalis:BAAANQADCgYIBgAAAA==.',
Li='Lidande:BAAANQADCgYIBgAAAA==.Lidarcis:BAAANQAECgYJEAAAAA==.Liedora:BAAANQADCgYJDAAAAA==.Lightpraiser:BAAANQAECgUJCAAAAA==.Limjahey:BAAANQADCggIEAAAAA==.Linra:BAAANQAECgYJDAAAAA==.Littlefatt:BAAANQAECgYIDQAAAA==.',
Ll='Llich:BAAANQAECgIJBAAAAA==.',
Lu='Luassei:BAAANQADCgMJBwAAAA==.Lucishifts:BAABNQAECoEWAAMTAAkKqyDeCABiAwATAAkKqyDeCABiAwALAAEKDSNDKQBlAAAAAA==.Lucîan:BAAANQADCggJIgAAAA==.Lumaris:BAAANQADCgcIBwAAAA==.Lunamorr:BAAANQADCgYIBgAAAA==.Luphoe:BAAANQADCgUJBwAAAA==.',
Ly='Lyserra:BAAANQAECgEIAgAAAA==.Lyudmila:BAAANQADCgcJBwABNQADCggIDAACAAAAAA==.',
Ma='Mabell:BAAANQADCgEIAQAAAA==.Mackori:BAAANQADCggJCwAAAA==.Maddawggamin:BAAANQADCgQIBAAAAA==.Maekar:BAAANQAECgIJAgAAAA==.Mafi:BAAANQADCgMIAwAAAA==.Magenos:BAAANQAECgQJBAAAAA==.Magic:BAAANQADCgUIBQAAAA==.Magicpants:BAAANQAECgEIAgAAAA==.Magobiga:BAAANQADCgYICAAAAA==.Mahrx:BAABNQAECoEfAAIdAAkKESXUAwB1AwAdAAkKESXUAwB1AwAAAA==.Malaricia:BAAANQADCgMIAQAAAA==.Mawaru:BAAANQAECgIJAwAAAA==.Maxanadu:BAAANQADCgcJEQAAAA==.',
Me='Meatpipe:BAAANQAECgEIAQAAAA==.Medarela:BAAANQAECgUJBgAAAA==.Meeke:BAACNQAFFIEHAAIeAAQKUB3qAwCAAQAeAAQKUB3qAwCAAQA1AAQKgSQAAh4ACQqtIckEAHIDAB4ACQqtIckEAHIDAAAA.Mell:BAABNQAECoEZAAIMAAkKARwKKgC2AgAMAAkKARwKKgC2AgAAAA==.Melmin:BAAANQAECgMJBwAAAA==.Meroman:BAAANQADCgUICwAAAA==.Metamora:BAAANQAECgIJAgABNQAECgUIBgACAAAAAA==.Meuria:BAAANQAECgMJBQAAAA==.',
Mi='Midgetlord:BAABNQAECoEjAAIMAAkKZyItFAA2AwAMAAkKZyItFAA2AwAAAA==.Miklos:BAAANQADCgYICwAAAA==.Minxmaxed:BAAANQADCgcJCQAAAA==.Misstearly:BAAANQADCgYIBgAAAA==.',
Mo='Moneebagz:BAAANQADCggJGwAAAA==.Montblanc:BAAANQADCggJCAAAAA==.Moonchylde:BAAANQADCgUJBQABNQAECgUICwACAAAAAA==.Moonem:BAABNQAECoEWAAITAAcKlB+xHgB6AgATAAcKlB+xHgB6AgAAAA==.Moosteerious:BAEANQADCggJEAABNQADCgkJGAACAAAAAA==.Mossacre:BAABNQAECoEaAAMIAAgKWBmwQwBZAgAIAAgKWBmwQwBZAgAQAAIKkhDzGAB/AAAAAA==.Mossherder:BAAANQABCgEIAQAAAA==.',
['Mé']='Méta:BAAANQAECgUIBgAAAA==.',
Na='Naanda:BAAANQABCgcJCwAAAA==.Nachopapa:BAAANQADCggJEgAAAA==.Nalorspace:BAAANQADCgYJEQAAAA==.Naniwa:BAAANQAECgcJEwAAAA==.Narwail:BAAANQAECgQICAAAAA==.Narweil:BAAANQADCgUIBQABNQAECgQICAACAAAAAA==.Narwhall:BAAANQADCgYJCwABNQAECgQICAACAAAAAA==.Nasathen:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Natanus:BAAANQADCgUICwAAAA==.Natsuko:BAAANQADCgMIAwAAAA==.Nazaric:BAAANQAECgYJCQAAAA==.Nazaricksm:BAAANQADCgMIAwABNQAECgYJCQACAAAAAA==.Nazgeul:BAAANQADCgYICwAAAA==.',
Nb='Nbi:BAAANQABCgQJBQABNQADCgEIAQACAAAAAA==.',
Ne='Necrodik:BAAANQADCgQIBAAAAA==.Neladris:BAAANQADCgIIAgAAAA==.Nelagorn:BAAANQAECgMJAwAAAA==.Nemesís:BAAANQABCgYIBwAAAA==.Neohorn:BAAANQAECgEIAwAAAA==.Neomyk:BAAANQADCggJDgAAAA==.Neoptolemus:BAAANQADCgUICwAAAA==.Neoqled:BAAANQAECgMJAwAAAA==.Neorhon:BAAANQADCgUIBQAAAA==.Nerclopse:BAABNQAECoEgAAIJAAgKLRSFMgA7AgAJAAgKLRSFMgA7AgAAAA==.Neverender:BAAANQAECgMIBAAAAA==.Nexian:BAAANQABCgQIBgAAAA==.',
Ni='Niarwodahs:BAAANQAECgIIAwAAAA==.Niaryci:BAAANQAECgQJCQAAAA==.Nightfangz:BAAANQADCgYIDAAAAA==.Nihilis:BAAANQADCgcIBwAAAA==.Nims:BAAANQADCgQICAABNQAECgQIBgACAAAAAA==.',
Nm='Nmoney:BAAANQADCgIJAgAAAA==.',
No='Noritotem:BAAANQAECgcIDAAAAA==.Note:BAAANQADCgUICQAAAA==.Notec:BAAANQADCggIAQAAAA==.Notics:BAAANQAECgIIAgAAAA==.Novacainê:BAAANQAECgQIBAAAAA==.',
Nu='Nuff:BAAANQADCgQIBAAAAA==.Nuikai:BAAANQAECgUJDgAAAA==.Nukum:BAAANQADCgYICwAAAA==.',
Ob='Obsidiansun:BAAANQAECgQIBwAAAA==.',
Oc='Octame:BAAANQAECgIIAgAAAA==.',
Ol='Olethvia:BAAANQADCgMJAwABNQAECgUJBQACAAAAAA==.',
On='Onlylight:BAAANQADCggICAAAAA==.',
Oo='Oororoe:BAAANQADCgUIBQAAAA==.',
Op='Opalescence:BAAANQADCgYIGQAAAA==.Opie:BAAANQABCgIJAgAAAA==.Optional:BAABNQAECoEfAAIYAAkKgyVXAAC3AwAYAAkKgyVXAAC3AwAAAA==.',
Or='Orgargo:BAAANQAECgUJBQAAAA==.',
Os='Osley:BAAANQADCgMIBgAAAA==.',
Ou='Oule:BAEBNQAECoEYAAIWAAkK4hIBDQBBAgAWAAkK4hIBDQBBAgAAAA==.',
Pa='Pallorx:BAAANQADCgQJBAAAAA==.Pallyzombi:BAAANQADCgQIBAABNQAECgYIDwACAAAAAA==.Palpatiné:BAAANQADCgQIBAAAAA==.Paluoth:BAAANQADCgEIAQAAAA==.Pandasennin:BAAANQADCgUICwAAAA==.Papachains:BAAANQADCgYIDAABNQAECggJAQACAAAAAA==.Papashootin:BAAANQAECggJAQAAAA==.Paperplate:BAABNQAECoEgAAMbAAgKgiPaCgDAAgAbAAcKNyPaCgDAAgATAAYKtxNtPACPAQAAAA==.Paradox:BAABNQAECoEcAAIgAAgKJyDJAwDuAgAgAAgKJyDJAwDuAgAAAA==.Pattyhealsu:BAACNQAFFIEFAAIKAAMK/hRtCQAFAQAKAAMK/hRtCQAFAQA1AAQKgR0AAgoACQpNIYANAB4DAAoACQpNIYANAB4DAAAA.Pawlyn:BAAANQADCgEIAQAAAA==.',
Pe='Peachizz:BAAANQAECgEIAQAAAA==.Pelikohjo:BAAANQAECgQICAABNQAECggIKQAYAKMYAA==.Pelivarondo:BAABNQAECoEpAAMYAAgKoxgLBAAzAgAYAAcKDRsLBAAzAgADAAMKPA1+xQC6AAAAAA==.Pelizandeth:BAAANQADCggIHAABNQAECggIKQAYAKMYAA==.Pepegas:BAAANQADCggJHQAAAA==.Pestillia:BAAANQAECgUICwAAAA==.',
Ph='Phoffynax:BAAANQADCggJIgAAAA==.Phundip:BAAANQADCgMIBgABNQAECgQIBgACAAAAAA==.',
Pi='Pistolbeat:BAAANQADCgUIBQAAAA==.',
Pk='Pkthunder:BAAANQADCgUIBQAAAA==.',
Pl='Playful:BAAANQADCggIDgAAAA==.Plopopotamus:BAAANQAECgcJDgAAAA==.',
Po='Poedanrin:BAAANQAECgEJAQAAAA==.Polikarp:BAAANQABCgQIBwAAAA==.Pookìe:BAAANQAECgQJBgAAAA==.Poorsol:BAAANQAECgQJBwAAAA==.',
Ps='Psychoclaw:BAAANQAECgIJAgAAAA==.Psyko:BAAANQADCgMIAwABNQADCggICAACAAAAAA==.',
Qu='Quickbrown:BAAANQAECgMIBAAAAA==.',
Ra='Ragenel:BAAANQADCgYJBgAAAA==.Rahxe:BAAANQADCggIHgAAAA==.Raikz:BAAANQAECgQICQAAAA==.Raiyne:BAAANQADCggIDwAAAA==.Randolphus:BAAANQAECgQIBQABNQAECgQJBgACAAAAAA==.Rateddz:BAAANQAECgEIAQAAAA==.Rats:BAABNQAECoEpAAIVAAkKliAOBgBZAwAVAAkKliAOBgBZAwAAAA==.Ratshield:BAAANQAECgcIEAABNQAECgkJKQAVAJYgAA==.Ratwynne:BAAANQADCggICAAAAA==.',
Re='Rendis:BAAANQADCgIIAgAAAA==.Reno:BAAANQAECgUIDgAAAA==.Renthyr:BAAANQADCgUJBQAAAA==.Reportcard:BAAANQAECgEIAQABNQAECgQJBAACAAAAAA==.Reurog:BAAANQAECgUJCgAAAA==.Revanjmt:BAAANQADCgYIBAAAAA==.',
Rh='Rhakudu:BAAANQADCgYIBgABNQAECgUICQACAAAAAA==.',
Ri='Rian:BAABNQAECoEcAAIhAAkKfyNIAwCNAwAhAAkKfyNIAwCNAwABNQAFFAcJDQAOAMkaAA==.Rigbee:BAAANQABCgIIAgAAAA==.Ritalia:BAAANQAECgcIDgAAAA==.',
Rm='Rmnieech:BAAANQAECgQIBQAAAA==.',
Ro='Roadiee:BAAANQADCgYIEAAAAA==.Roadiex:BAAANQADCgIIAwAAAA==.Roadkyll:BAAANQAECgEJAgAAAA==.Ronynn:BAAANQADCgEIAQAAAA==.Roobern:BAAANQADCgEIAQAAAA==.Rosamoon:BAAANQADCggJEgAAAA==.Rosilyn:BAAANQAECgUICgAAAA==.',
Ru='Rurrick:BAAANQAECgEIAQAAAA==.',
Ry='Ryzee:BAAANQAFFAEIAQAAAA==.',
['Rå']='Råinè:BAAANQADCgcIBwABNQAECgMIAwACAAAAAA==.',
Sa='Sahmash:BAAANQADCgIIAgAAAA==.Salara:BAAANQAECgUJDgAAAA==.Salasong:BAAANQADCgYJEQAAAA==.Saltytoast:BAAANQAECgEIAQAAAA==.Sambda:BAAANQADCgYIBwABNQADCggIDAACAAAAAA==.Sambraicho:BAAANQADCggIDAAAAA==.Samburai:BAAANQADCgcJDAABNQADCggIDAACAAAAAA==.Samuella:BAAANQAECgYJDwAAAA==.Sandrinea:BAAANQAECgUJBwAAAA==.Sarinya:BAAANQADCgcJDQAAAA==.Sauceym:BAAANQABCgcICQAAAA==.Saytens:BAAANQAECggJEAAAAA==.',
Sc='Scargiver:BAAANQADCgEJAQAAAA==.Scarllett:BAAANQAECgIJBAABNQAECgcIDAACAAAAAA==.Scarykyns:BAAANQADCgYIBgABNQAECgYIEQACAAAAAA==.Schatzi:BAAANQADCggICAAAAA==.Scrubmage:BAAANQADCggJCwAAAA==.',
Se='Secondwall:BAAANQAECgQIBAAAAA==.Sedale:BAAANQAECgUJBQAAAA==.Seesdeline:BAAANQADCggIBwABNQADCgYICAACAAAAAA==.Seilene:BAAANQADCgcJFgABNQAECgEIAQACAAAAAA==.Selisi:BAAANQAECgQICAABNQAECgUICgACAAAAAA==.Senddra:BAAANQABCgYICAAAAA==.Seo:BAAANQAECgQJBgAAAA==.Seraf:BAABNQAECoEjAAMPAAkK5CSzBwBmAwAPAAkKqiGzBwBmAwAZAAgKnh+VEQDaAgAAAA==.Serafain:BAAANQAECgYJBwABNQAECgkJIwAPAOQkAA==.',
Sh='Shadowerise:BAAANQADCgYIBwAAAA==.Shaforgold:BAABNQAECoEbAAIJAAkK0R0CEgAgAwAJAAkK0R0CEgAgAwAAAA==.Shalaz:BAAANQADCggJCAAAAA==.Shalazard:BAAANQAECgQIBAAAAA==.Shamananana:BAAANQADCgYIBgAAAA==.Sharrina:BAAANQABCgEIAQAAAA==.Shawtyschit:BAAANQAECgQJBAAAAA==.Shibal:BAAANQAECgQJCgAAAA==.Shinystepdad:BAAANQADCgUIBQAAAA==.Shotorock:BAAANQAECgIJAgAAAA==.Shreckfive:BAAANQADCgYIBgAAAA==.Shrekismydad:BAAANQADCgQIBAAAAA==.Shroompie:BAAANQADCgYIBgABNQADCgcJEAACAAAAAA==.Shroomshock:BAAANQADCgcJCQABNQADCgcJEAACAAAAAA==.Shushumen:BAAANQAECgQJCwAAAA==.Shänk:BAAANQADCgcICAAAAA==.',
Si='Sicknezz:BAAANQADCgYJCwABNQAECggJDAACAAAAAA==.Sidewinder:BAAANQAECgQIBQABNQAECgkJHwAYAIMlAA==.Siinyster:BAAANQADCgMIAwAAAA==.Sikmode:BAAANQAECgQIBgAAAA==.Sildrusil:BAAANQADCgEIAQAAAA==.Sindari:BAAANQAECgUJEAAAAA==.Sinturio:BAAANQAECgMIBQAAAA==.Sipsy:BAAANQAECgMIBQAAAA==.',
Sk='Skarg:BAAANQAECgMJCAAAAA==.Skyeashe:BAAANQADCgYJEwAAAA==.',
Sl='Sleezytease:BAAANQADCgcIBwAAAA==.Slimdusty:BAAANQADCgQICAAAAA==.Slingblades:BAAANQAECggJDAAAAA==.Slobbrknckr:BAAANQADCgcIBwABNQAFFAIIAgACAAAAAA==.Slowmo:BAAANQAECggJDAAAAA==.',
Sm='Smittles:BAAANQAECgQIBgAAAA==.',
Sn='Sneakystix:BAAANQADCgYIBgABNQAECgUICAACAAAAAA==.Snowtigerr:BAAANQABCgIJAgAAAA==.',
So='Sootclaw:BAAANQADCgYICQAAAA==.Sophus:BAAANQAECgEIAgAAAA==.Soren:BAAANQADCgYICAAAAA==.Sorenko:BAAANQAECgIJAwABNQADCgYICAACAAAAAA==.',
Sp='Spagooter:BAABNQAECoEdAAMfAAkKhRyBIQCjAgAfAAgKJx2BIQCjAgAaAAEKdRdWWwBIAAAAAA==.Sparklepants:BAABNQAECoEdAAIOAAkK6B4NIAA3AwAOAAkK6B4NIAA3AwAAAA==.Spencerz:BAAANQADCgEIAQAAAA==.Speyesee:BAAANQAECgUICgAAAA==.Splashydank:BAAANQAECgEIAQAAAA==.Spookyish:BAAANQAECgUJCgAAAA==.',
Sq='Squidstens:BAAANQABCgMIAwAAAA==.',
St='Stabbydank:BAAANQAECgIIAgAAAA==.Stackss:BAAANQAECgEIAQAAAA==.Staypuff:BAAANQABCgMIAwAAAA==.Stnkychz:BAAANQADCggIDAAAAA==.Stonedninja:BAAANQADCgIIAQAAAA==.Stonemason:BAAANQAECgEIAQAAAA==.Stoneskin:BAAANQADCgUJCQAAAA==.Strawberymik:BAAANQADCgEIAQAAAA==.',
Su='Submisive:BAAANQAECgEJAQAAAA==.Supe:BAAANQAECgMIBAAAAA==.Superstar:BAAANQADCggICAAAAA==.',
Sw='Swagruid:BAAANQAECgUICwAAAA==.Swampslinger:BAAANQAECgMIBQAAAA==.Swordlady:BAAANQAECgUIDgABNQAECggJGAAEABQZAA==.',
Sy='Syntari:BAAANQAECgQIBgAAAA==.Syntyr:BAAANQADCgMIAwAAAA==.Synyra:BAAANQADCgcIBwAAAA==.Synìk:BAAANQADCgUICgAAAA==.',
['Sö']='Söma:BAAANQAECgYICQAAAA==.',
Ta='Taktixxloxx:BAAANQABCgMIAwAAAA==.Talenalat:BAAANQAECggJAgAAAA==.Tankerbelle:BAAANQADCgEIAQAAAA==.Tannarisse:BAAANQADCgQIBQAAAA==.Taymatt:BAAANQAECgMIBQAAAA==.Tazstinko:BAABNQAECoEYAAIIAAkKBBvBJgDVAgAIAAkKBBvBJgDVAgAAAA==.',
Te='Teaveen:BAAANQADCgIIAgAAAA==.Tectonic:BAAANQAECgYIDAABNQAFFAIJAwACAAAAAA==.Tejasgeek:BAAANQAECgMIBQAAAA==.Tenleron:BAAANQABCgIIAgAAAA==.Tenntoes:BAAANQADCgYIBgAAAA==.Tewiyakichkn:BAAANQAECgEIAQAAAA==.',
Th='Thegoob:BAAANQABCgMIAwAAAA==.Theiceflare:BAAANQADCgcJEAAAAA==.Themuffinman:BAAANQAECgEIAQAAAA==.Theworrirawr:BAABNQAECoEaAAILAAkKHiZJAAD1AwALAAkKHiZJAAD1AwAAAA==.Thour:BAAANQABCgIIAgAAAA==.Thur:BAAANQAECgYIDAAAAA==.Thänatos:BAAANQAECgIIAgAAAA==.',
Ti='Tiesci:BAABNQAECoEaAAIOAAgKUSI0KwAPAwAOAAgKUSI0KwAPAwAAAA==.Tinyclash:BAAANQADCgQIBAAAAA==.Tinypap:BAAANQADCggIFwAAAA==.Tippe:BAAANQADCggIGAAAAA==.',
Tl='Tlálocx:BAAANQAECgQJBQAAAA==.',
To='Toastedblade:BAAANQAECgQJBwAAAA==.Toldyousoul:BAAANQAECgEIAQAAAA==.Tonytots:BAAANQAECgQIBAAAAA==.Tottemakk:BAAANQADCgEIAQAAAA==.Toughshots:BAAANQADCgEIAQAAAA==.Toxenima:BAAANQAECgUIBwAAAA==.Toxiciti:BAAANQAECgUJBwAAAA==.',
Tr='Tramlaw:BAAANQADCgIIAgAAAA==.Trashedara:BAAANQADCgUIBQAAAA==.Treebirth:BAABNQAECoEfAAIbAAkKAyEMBABUAwAbAAkKAyEMBABUAwAAAA==.Treyu:BAAANQADCgYIBgAAAA==.Triegh:BAAANQAECgMIAwAAAA==.Troyano:BAAANQADCgQIBAAAAA==.Trunder:BAAANQAECgUJCAAAAA==.',
Ts='Tsaindorcus:BAABNQAECoEUAAIZAAYKDAkSWgAMAQAZAAYKDAkSWgAMAQAAAA==.Tsunamyz:BAAANQADCgIIBQAAAA==.',
Tu='Tuskgwel:BAAANQADCgIIAQAAAA==.',
Ty='Tyfoon:BAAANQABCgIIAgAAAA==.',
Ud='Uders:BAAANQAECgUJBgAAAA==.',
Uh='Uhlvar:BAAANQAECgcJCwAAAA==.Uhm:BAABNQAECoEXAAIIAAkK0SBJEgBLAwAIAAkK0SBJEgBLAwAAAA==.',
Ui='Uil:BAEANQAECgIIAgABNQAECgkJGAAWAOISAA==.',
Ul='Ultramad:BAAANQAECgcJDQAAAA==.Ultramellow:BAAANQAECgEIAQABNQAECgcJDQACAAAAAA==.',
Un='Unclesquid:BAAANQADCggIEwAAAA==.Unholydubzzy:BAAANQADCgEIAQAAAA==.',
Up='Upngo:BAABNQAECoEaAAIIAAkKHyKECgCGAwAIAAkKHyKECgCGAwAAAA==.',
Ur='Urotherdaddy:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.',
Us='Uskthyr:BAAANQADCgYJDwAAAA==.',
Va='Vanakin:BAAANQAECgQIBAABNQAFFAYIEgARAJccAA==.Vandredor:BAACNQAFFIESAAIRAAYKlxx1AQAsAgARAAYKlxx1AQAsAgA1AAQKgR4AAxEACQrRIFkOAOICABEACQqjIFkOAOICABcABgpaHD8IANgBAAAA.Vastatio:BAAANQADCgEIAQAAAA==.Vasträ:BAAANQADCgUICwAAAA==.',
Ve='Velicelia:BAAANQAECgYJEQAAAA==.Vesroth:BAAANQAECgQJCAAAAA==.',
Vi='Viborge:BAAANQADCggIEAAAAA==.View:BAABNQAECoEYAAIYAAgKRiNBAQAlAwAYAAgKRiNBAQAlAwAAAA==.Vince:BAAANQADCggJIAAAAA==.Vissra:BAAANQADCgUIBQAAAA==.',
Vo='Vojak:BAAANQAECgUIBQAAAA==.',
Vu='Vulpermon:BAAANQADCgMIBAAAAA==.Vuly:BAAANQADCgEIAQAAAA==.',
['Vä']='Vääko:BAAANQAECgEJAgAAAA==.',
['Ví']='Vínce:BAAANQADCgIIAgAAAA==.',
Wa='Waluigi:BAAANQADCggJCAABNQAECgIJAwACAAAAAA==.Warbaby:BAAANQADCggIDwAAAA==.Warlarren:BAAANQADCgEIAQAAAA==.',
We='Weatherr:BAABNQAFFIEIAAMfAAQKWhOWBgBVAQAfAAQKWhOWBgBVAQAaAAEKcQlPFABOAAAAAA==.Weki:BAAANQADCggIDAAAAA==.',
Wh='Whippoorwill:BAABNQAECoEZAAITAAgKZhNnJwAuAgATAAgKZhNnJwAuAgAAAA==.Whiskyslayer:BAAANQAECgcIDgAAAA==.Whosmofunky:BAAANQADCgcJBwAAAA==.',
Wi='Wickeda:BAAANQAECgQIBwAAAA==.Williamp:BAAANQADCgYICgAAAA==.',
Wn='Wntlmd:BAAANQAECgMIBQAAAA==.',
Wo='Wolfnacht:BAAANQAECgQJBQAAAA==.',
Wu='Wukangmei:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrødør:BAAANQAECgQIBQAAAA==.',
Xe='Xene:BAABNQAECoEYAAIJAAUKnSB1SADRAQAJAAUKnSB1SADRAQAAAA==.',
Xh='Xhade:BAAANQADCgIIAgABNQADCggIGAACAAAAAA==.',
Xr='Xriss:BAAANQADCgYJFAAAAA==.Xrs:BAAANQADCgQIBAABNQAECgQIBgACAAAAAA==.',
Ya='Yanedin:BAABNQAECoEaAAIiAAgK7wUuEgBMAQAiAAgK7wUuEgBMAQAAAA==.Yathrr:BAAANQADCgYICwAAAA==.',
Yi='Yippeezippee:BAAANQABCgIIAgAAAA==.',
Yo='Yorforger:BAAANQAECgQIBAABNQAECggIEQACAAAAAA==.Youngbj:BAAANQAECgcICAABNQAECgcICwACAAAAAA==.Younger:BAAANQAECgEIAgAAAA==.Youngerxx:BAAANQADCgYIBgAAAA==.',
Ys='Yserene:BAAANQADCgcJDAAAAA==.',
Yu='Yukonícus:BAAANQADCgYICgABNQAECgkJHAARACggAA==.Yukonïcus:BAABNQAECoEcAAIRAAkKKCAzBgBgAwARAAkKKCAzBgBgAwAAAA==.Yumm:BAAANQADCgcIBwAAAA==.Yuridemo:BAAANQAECgcIDAAAAA==.',
['Yè']='Yènnefer:BAAANQADCggJEAAAAA==.',
Za='Zaldrena:BAAANQADCgYIBgAAAA==.Zanotgaming:BAAANQADCgcIBwAAAA==.Zaraydorine:BAAANQADCgUIBQAAAA==.',
Zb='Zbrickashaw:BAAANQAECgQJBwAAAA==.',
Ze='Zelrin:BAACNQAFFIEIAAIOAAUKthc5CQDFAQAOAAUKthc5CQDFAQA1AAQKgSAAAg4ACQogGE5YAIQCAA4ACQogGE5YAIQCAAAA.Zenthalion:BAAANQAECgEIAQAAAA==.',
Zi='Zippee:BAAANQADCgQIBAAAAA==.',
Zo='Zobi:BAAANQADCgMIAwAAAA==.Zoomhunt:BAAANQAFFAQIBAAAAA==.Zoommage:BAAANQAFFAEIAQABNQAFFAQIBAACAAAAAA==.',
Zu='Zuluugargorg:BAAANQAECgQIBwAAAA==.',
Zy='Zyrun:BAAANQADCgQIBAAAAA==.',
['Ãd']='Ãdaria:BAAANQADCgIIAgAAAA==.',
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
