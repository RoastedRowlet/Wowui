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

local lookup = {'Paladin-Holy','Unknown-Unknown','Mage-Arcane','Rogue-Assassination','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Druid-Guardian','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Unholy','Warrior-Fury','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Subtlety','DeathKnight-Blood','Warlock-Destruction','Shaman-Enhancement','Druid-Feral','Priest-Shadow','Warlock-Demonology','Warlock-Affliction','Hunter-Marksmanship','Monk-Brewmaster',}
local provider = {region='US',realm='Garrosh',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aadolin:BAABNQAECoEeAAIBAAgKsBzLIgCwAgABAAgKsBzLIgCwAgAAAA==.Aardvarkeggs:BAAANQAECgEIAQAAAA==.',
Ab='Abaddon:BAAANQAECggIAgAAAA==.Abi:BAAANQAECgEIAQAAAA==.',
Ac='Acamar:BAAANQADCggIFgAAAA==.',
Ad='Adeleska:BAAANQAECgYIEwAAAA==.Aderina:BAAANQADCgcJBwAAAA==.Adessa:BAAANQAECgcICgAAAA==.',
Ae='Aellibash:BAAANQADCgIIAgABNQAECgUICgACAAAAAA==.Aenivath:BAAANQADCgUJCAAAAA==.',
Af='Aftercare:BAAANQAECgIJAgAAAA==.',
Ag='Agerthel:BAAANQADCgIIAgAAAA==.Agnergam:BAAANQADCgcIBwAAAA==.Agorath:BAAANQADCgYJBgAAAA==.',
Ah='Ahsnap:BAAANQADCgUIBAAAAA==.',
Ai='Airchiefsosa:BAAANQAECgUIBQAAAA==.Airygrim:BAAANQADCgEJAQAAAA==.Aisatsana:BAAANQADCgQIBgAAAA==.',
Al='Alexstrasz:BAAANQAECgYICgAAAA==.Alopex:BAAANQAECgYIEgAAAA==.',
Am='Amaellara:BAABNQAECoEaAAIDAAgKSxeKewBPAgADAAgKSxeKewBPAgAAAA==.Amajiki:BAAANQADCgYJAwAAAA==.',
An='Andrayah:BAAANQADCggICAAAAA==.Annorah:BAAANQADCgEIAQAAAA==.Anthathein:BAAANQAECgIIAwAAAA==.',
Ao='Aoda:BAAANQAECgMJBAAAAA==.Aotrom:BAAANQAECgUIBQAAAA==.',
Ar='Aracus:BAAANQADCgEJAQAAAA==.Arcanefire:BAAANQADCgYIBgABNQAECggIDAACAAAAAA==.Archblade:BAAANQAECgQIDAAAAA==.Aristaana:BAAANQAECgEIAQABNQAFFAMIBgAEAOgTAA==.Armagnac:BAABNQAECoElAAIFAAkKPBqyKAC5AgAFAAkKPBqyKAC5AgAAAA==.Arthias:BAAANQADCgEIAQAAAA==.',
As='Asroldal:BAAANQADCgYIBgAAAA==.Astralkitten:BAAANQADCgQJBAAAAA==.',
At='Atem:BAAANQABCgIIAgAAAA==.Atom:BAAANQAECgYIBgAAAA==.',
Au='Aufare:BAAANQAECgYIDAAAAA==.',
Av='Avacyn:BAAANQAECgEIAQAAAA==.Avarya:BAABNQAECoEgAAIGAAgKOyaQBQCBAwAGAAgKOyaQBQCBAwAAAA==.Averagerat:BAAANQAECgUIBgABNQAFFAcIGQAHALQhAA==.Averagesham:BAAANQAECggIDwABNQAFFAcIGQAHALQhAA==.Averagevoker:BAACNQAFFIEZAAMHAAcKtCGuAABcAgAHAAYK0iKuAABcAgAIAAIK1hQ/BQCpAAA1AAQKgScAAwcACQrvJVwBAKcDAAcACQrvJVwBAKcDAAgAAQouHwUZAFQAAAAA.Averwine:BAAANQADCgcICQAAAA==.',
Ba='Babychow:BAAANQADCgEIAQAAAA==.Babynimyk:BAAANQAECgUICwAAAA==.Backyard:BAAANQADCgYIFgAAAA==.Bael:BAAANQAECgMIAwAAAA==.Bahamasoul:BAAANQAECgQIBAAAAA==.Balooi:BAAANQABCgYICQAAAA==.Baraxius:BAAANQABCgEIAQAAAA==.Bashtaz:BAABNQAECoEZAAMJAAkKmyGyGwAqAwAJAAkKCCGyGwAqAwAKAAYKFhxyDgDrAQABNQAFFAUICgALANMcAA==.Basixx:BAAANQAECgMJAwAAAA==.Bayleaf:BAAANQAECgUIEwABNQAFFAcIGQAHALQhAA==.',
Bb='Bbeloree:BAAANQAECgEIAQAAAA==.',
Bd='Bdiotlcth:BAAANQADCgUJBQAAAA==.',
Be='Bearykyns:BAABNQAECoEbAAQMAAgKtBS9MAAVAgAMAAgKkRO9MAAVAgANAAQKEBAwOwDcAAAOAAEKSBVVPAA/AAAAAA==.Beastwarden:BAABNQAECoEcAAMPAAgK6g5VBQAfAgAPAAgK6g5VBQAfAgAFAAEKMAGGKgEjAAAAAA==.Beatrixkiddo:BAAANQADCgYIBgAAAA==.Bejay:BAAANQADCgYIBgABNQAECgcICwACAAAAAA==.Belladar:BAAANQADCgMIAwAAAA==.Belokk:BAAANQADCggIEAAAAA==.Belwarr:BAAANQAECgQIBwAAAA==.Bemused:BAAANQAECgEJAQAAAA==.Benpai:BAAANQAECgEIAQAAAA==.Besticle:BAABNQAECoEuAAIJAAkKvCHYEwBTAwAJAAkKvCHYEwBTAwAAAA==.',
Bi='Bigcheddarz:BAAANQADCgMIAwAAAA==.Bigchungass:BAAANQAECgYIBgABNQAFFAIIAgACAAAAAA==.Bigttgothgf:BAAANQAECgUIBAAAAA==.Bilberry:BAAANQABCgQICAAAAA==.Binkie:BAAANQADCgcIGQABNQAECgYIEQACAAAAAA==.',
Bj='Bjaculator:BAAANQAECgcICwAAAA==.',
Bl='Blackcoat:BAAANQADCgIIAgAAAA==.Blackgranite:BAAANQADCggIDwABNQAECgQIBwACAAAAAA==.Blacklotus:BAAANQAECgIIAgAAAA==.Blayze:BAAANQADCgYIBgAAAA==.Blep:BAAANQAECgYIEwAAAA==.Bloodoath:BAAANQADCgEIAQABNQAECggIJgAQAOIVAA==.Blueheal:BAAANQADCgUICwAAAA==.Bluemilk:BAAANQAECgEIAQAAAA==.Blueshiver:BAAANQAECgIJAwAAAA==.',
Bo='Bombadore:BAAANQADCgYIBgAAAA==.Bonesaw:BAAANQADCgIIAgABNQAECgQICQACAAAAAA==.Booktök:BAAANQAECgUIBwABNQAECgcIEgACAAAAAA==.Bowlinder:BAABNQAECoEdAAMQAAkKECLDCgB8AwAQAAkKECLDCgB8AwARAAgKORY1SwDmAQAAAA==.Bowlinderr:BAAANQAECgEIAQAAAA==.Boyvine:BAAANQAECgYICQAAAA==.',
Br='Brahmana:BAAANQABCgYICwAAAA==.Braldar:BAAANQAECgIIAgAAAA==.Branas:BAAANQADCggIEAAAAA==.Braxiss:BAABNQAECoEfAAIFAAcKiBxaTAA8AgAFAAcKiBxaTAA8AgAAAA==.Break:BAAANQAECgIIBAABNQAFFAcKEwASAMYfAA==.Breellspace:BAAANQADCgEIAQAAAA==.Brilin:BAABNQAECoEcAAMJAAkK8BqXQgCIAgAJAAgKOxqXQgCIAgAKAAYKwx0XDwDcAQAAAA==.Brithio:BAAANQADCgQJAQAAAA==.Broguë:BAAANQAECgIIBAAAAA==.Brokton:BAAANQADCgQIBAAAAA==.Brucarus:BAAANQADCggJCQABNQAECgMJBAACAAAAAA==.Bruce:BAAANQADCgYIBgAAAA==.Brueld:BAAANQAECgUICAABNQAECggIJgAQAOIVAA==.',
Bu='Bulldozzers:BAAANQADCgUIBQAAAA==.Bullshzitt:BAAANQAECggIAQAAAA==.Bumper:BAAANQADCgcJDAAAAA==.Busin:BAAANQAECgQICQAAAA==.',
['Bë']='Bënzin:BAAANQADCgYIBwAAAA==.',
['Bî']='Bîllydakîd:BAAANQADCgYIBgAAAA==.',
Ca='Calabag:BAEANQAECgYICwABNQAECggIIQAOAP8gAA==.Calabloom:BAEBNQAECoEhAAIOAAgK/yByBQDrAgAOAAgK/yByBQDrAgAAAA==.Caland:BAAANQADCgIIAgAAAA==.Calibern:BAAANQADCggIEwAAAA==.Calmm:BAAANQAECgQIBgABNQAFFAIIAgACAAAAAA==.Canthndice:BAAANQAECgEJAQAAAA==.Capncrunchh:BAAANQAECgMIAwAAAA==.Caressaa:BAAANQADCgMJAwAAAA==.Cavalina:BAABNQAECoErAAMSAAgKjBfLWQA1AgASAAgKLRXLWQA1AgATAAUKtBhTKwApAQAAAA==.Cavick:BAAANQAECgYIDgAAAA==.Cawnor:BAAANQAECgUIDQAAAA==.Caótica:BAAANQADCggIDgAAAA==.',
Ce='Celyanar:BAAANQADCgMJAgABNQAECgUICQACAAAAAA==.Ceradwyn:BAAANQAECgEIAQAAAA==.',
Ch='Charön:BAACNQAFFIEHAAIDAAMKNBPSIQD7AAADAAMKNBPSIQD7AAA1AAQKgS0AAgMACQrsIJgrAB8DAAMACQrsIJgrAB8DAAAA.Cheezewizard:BAAANQAECgYIBQAAAA==.Chentrocka:BAABNQAECoEvAAIDAAkKaSF4IQBAAwADAAkKaSF4IQBAAwAAAA==.Chillberto:BAAANQAECgMIAwAAAA==.Chiselin:BAAANQAECgUJCQAAAA==.Chktmilk:BAAANQADCgYIBgAAAA==.Chopsui:BAAANQAECgMIAwAAAA==.',
Cl='Clankss:BAAANQADCggIEwAAAA==.Clerikyns:BAAANQADCgcIBwABNQAECggIGwAMALQUAA==.Clicks:BAAANQADCgMIAwAAAA==.Clics:BAAANQADCggICAAAAA==.',
Co='Coalgrim:BAAANQAECgQJDQAAAA==.Cosmíc:BAAANQAECgMIBAAAAA==.',
Cp='Cptbyakuya:BAABNQAECoEtAAISAAkK4iOMDgB2AwASAAkK4iOMDgB2AwAAAA==.',
Cr='Craterbip:BAAANQAECgYJCwAAAA==.Crimsonk:BAAANQADCgYIBgAAAA==.',
Cu='Curoconcum:BAAANQADCgYIBwAAAA==.',
Cy='Cyrub:BAAANQADCgUICwAAAA==.',
Da='Dabrinto:BAAANQADCgYIBgAAAA==.Daedrian:BAAANQAECgYIDAAAAA==.Dailoom:BAAANQADCgEIAQAAAA==.Dallena:BAAANQAECgQIBwABNQAECgUIBAACAAAAAA==.Dankweaver:BAABNQAECoEaAAMUAAgKQRF2HgDlAQAUAAgKQRF2HgDlAQAVAAYKvBKAHgBLAQAAAA==.Daratri:BAAANQAECgIIAgAAAA==.Darktales:BAAANQADCgYIBgAAAA==.Darthxander:BAAANQADCgYIEwAAAA==.Daruma:BAAANQADCggICAAAAA==.Daywrecker:BAAANQAECgQICQAAAA==.Dayyman:BAABNQAECoEhAAITAAgKgiGHBwD5AgATAAgKgiGHBwD5AgAAAA==.Dazuk:BAAANQADCgYIBgAAAA==.',
De='Deathlysham:BAAANQAECgEIAgAAAA==.Deathshroom:BAAANQADCgcIEAABNQAECgMIAwACAAAAAA==.Deathsun:BAABNQAECoEZAAIFAAgKviOjEgAtAwAFAAgKviOjEgAtAwAAAA==.Deddonkey:BAAANQAECgIIAgABNQAECgUJBQACAAAAAA==.Deform:BAAANQAECgUIBQAAAA==.Deianaera:BAAANQADCgQIBAAAAA==.Delldestus:BAAANQAECgQIBQAAAA==.Delmonicó:BAAANQADCggIDQAAAA==.Demonics:BAAANQADCgYIBgAAAA==.Demonstix:BAAANQAECgUIDAAAAA==.Demv:BAAANQADCgIIAgAAAA==.Depressa:BAAANQADCgQIBAABNQAFFAEIAQACAAAAAA==.Dernius:BAAANQADCggIEQAAAA==.Derran:BAAANQADCgcJBwAAAA==.Despairykyns:BAAANQAECgEIAQABNQAECggIGwAMALQUAA==.Dethbringa:BAABNQAECoEVAAMLAAcKDw0QPABqAQALAAcKDw0QPABqAQAWAAMKeAe7jwB9AAAAAA==.Dewfall:BAABNQAECoEgAAIXAAkKKB2bAgAJAwAXAAkKKB2bAgAJAwAAAA==.Deylithdreyn:BAAANQAECgMIBAAAAA==.',
Dh='Dhuoth:BAABNQAECoEgAAIYAAgKaCJ9DgD/AgAYAAgKaCJ9DgD/AgAAAA==.',
Di='Diagoraz:BAAANQADCgUIBwAAAA==.Dialtone:BAAANQADCgQIBwAAAA==.Dialtonee:BAAANQADCgMIAwABNQADCgQIBwACAAAAAA==.Digitalbäth:BAAANQADCgUIBQAAAA==.Digoshadow:BAAANQAECgQIBwAAAA==.Dillonharper:BAAANQADCggICAAAAA==.Disgruntld:BAAANQAECgEJAgAAAA==.Disturbd:BAAANQAECgEIAQABNQAECgYIEwACAAAAAA==.Ditdoo:BAAANQAECgEJAQAAAA==.',
Dk='Dkmetcàlf:BAAANQADCggICAAAAA==.',
Do='Donkeyform:BAAANQAECgEIAQABNQAECgUJBQACAAAAAA==.Donkeymonk:BAAANQAECgUJBQAAAA==.Dorkyspork:BAAANQAECgEIAQAAAA==.',
Dr='Dragonis:BAAANQADCggICAAAAA==.Dravenstone:BAAANQADCgYIBwAAAA==.Dreamerzz:BAAANQADCgYIBwAAAA==.Drovac:BAAANQAECgMIBgAAAA==.Druidxd:BAAANQADCgQIBAAAAA==.Drumittz:BAAANQADCgEIAQAAAA==.Drworm:BAABNQAECoEwAAILAAkKfx1ADQD3AgALAAkKfx1ADQD3AgABNQAECgkJJgAJAEUfAA==.Drääko:BAAANQADCgMIAwAAAA==.Drêdd:BAAANQABCgIJAgAAAA==.',
Ds='Dsonic:BAAANQADCgUICAAAAA==.',
Du='Dubbies:BAAANQAECgUICQAAAA==.Durtluz:BAAANQADCgcICAAAAA==.Dustandblood:BAAANQADCgMIAgABNQADCgYIBgACAAAAAA==.',
Dy='Dyrim:BAAANQADCgUICwAAAA==.Dysthymia:BAAANQADCgEIAQABNQAECgkJJwARAJ4bAA==.',
['Dæ']='Dæmonkawlr:BAAANQADCgQIBAAAAA==.',
['Dê']='Dêformjr:BAABNQAECoEfAAMZAAgKUA3WEQBGAQADAAcKFApr2QCDAQAZAAYKqwzWEQBGAQAAAA==.Dêvarim:BAAANQABCgQIBAAAAA==.',
['Dë']='Dëformjr:BAAANQADCgYIBgAAAA==.Dëfòrmjr:BAAANQADCgUIBQAAAA==.Dëförmjr:BAAANQAECgQICAAAAA==.',
['Dú']='Dúbletap:BAAANQADCgYIBgAAAA==.',
Ed='Edennia:BAAANQADCgIIAgAAAA==.',
Eh='Ehvie:BAAANQADCggIDQABNQAECggIIQAMAE0WAA==.',
Ei='Eidric:BAAANQADCgUIBAAAAA==.',
El='Elbrujo:BAAANQADCgYIBgAAAA==.Elenii:BAABNQAECoEgAAIGAAgKaBmhPQArAgAGAAgKaBmhPQArAgAAAA==.Eleynra:BAAANQADCgIIAgAAAA==.Elionor:BAAANQADCgEIAQAAAA==.Elstinko:BAAANQADCgYICgAAAA==.Elybear:BAAANQADCgUIBQAAAA==.Elychan:BAAANQADCgYIBgAAAA==.Elygance:BAAANQAECggICAAAAA==.Elÿ:BAABNQAECoEWAAIBAAkKABNzOABFAgABAAkKABNzOABFAgAAAA==.',
Em='Emptyside:BAAANQADCggJFwAAAA==.',
En='Enchorxxi:BAAANQAECgUICwAAAA==.Enetrenazara:BAAANQAECgUIDAAAAA==.Eniar:BAAANQADCgUIBQABNQAECgMIAwACAAAAAA==.Eniaro:BAAANQAECgMIAwAAAA==.Enlonger:BAABNQAECoEhAAIaAAkKEg6eFwAIAgAaAAkKEg6eFwAIAgAAAA==.',
Ep='Epicgooner:BAAANQAECgUIDQAAAA==.',
Er='Erahm:BAAANQADCgYIEAAAAA==.Erahmm:BAAANQAECgUICgAAAA==.Ergaraskreia:BAAANQADCgIIAgAAAA==.Erielia:BAAANQADCgIIAgABNQADCgYICAACAAAAAA==.Eruneenani:BAAANQADCgYIBgAAAA==.',
Es='Esmirelda:BAAANQAECgUIDwAAAA==.Essn:BAACNQAFFIEJAAIbAAMKCSU9BwA3AQAbAAMKCSU9BwA3AQA1AAQKgTAAAhsACQpoJoQAAPMDABsACQpoJoQAAPMDAAAA.',
Eu='Eulune:BAEANQAECgMIBAABNQAECgkJGwAVACgTAA==.',
Ev='Evelynna:BAAANQADCggIFAAAAA==.',
Ex='Exsull:BAAANQAECgYIDgAAAA==.',
Fa='Faible:BAAANQADCgMIAwAAAA==.Faithwarrior:BAAANQAECgUICgAAAA==.Falk:BAAANQAECgEIAQAAAA==.Falron:BAABNQAECoFBAQITAAgKnCVgCQDMAgATAAgKnCVgCQDMAgAAAA==.Farday:BAAANQADCgEIAQAAAA==.Fathlia:BAAANQAECggIEQAAAA==.Fazrien:BAAANQADCgIIAgAAAA==.',
Fe='Fezzjin:BAAANQAECgYIDgAAAA==.',
Fi='Filbrust:BAAANQADCgIIAgAAAA==.Fishtanked:BAAANQADCgQIBgAAAA==.Fitzofrage:BAAANQADCgYIBwAAAA==.',
Fl='Flashlights:BAAANQADCgYICQABNQAECgUIDAACAAAAAA==.Fleshbiter:BAAANQADCggIFQAAAA==.Flokindruid:BAAANQADCgIIAgABNQAECgUIDQACAAAAAA==.Flowingdeath:BAAANQADCgYICQABNQAECgUIDQACAAAAAA==.Flowingrage:BAAANQADCgYIBgABNQAECgUIDQACAAAAAA==.',
Fm='Fmjserval:BAAANQAECgEIAQAAAA==.',
Fo='Fomtoolery:BAAANQABCgUIBQAAAA==.Foot:BAABNQAECoEfAAIJAAkKOR7cMwC+AgAJAAkKOR7cMwC+AgAAAA==.Forcedk:BAAANQAECgQICAAAAA==.Forcefaith:BAAANQAECgcIEwAAAA==.',
Fr='Freduardo:BAAANQADCgUIBgAAAA==.Freva:BAAANQAECggJDgAAAA==.Friarfox:BAAANQADCgYJBgABNQAECgYIEQACAAAAAA==.Fronkness:BAAANQADCgYIBgAAAA==.Frostfiree:BAAANQAECgEJAgABNQAECggIJgAQAOIVAA==.Fruitpuddle:BAAANQABCgEIAQABNQAECgkJHQAcAFoZAA==.Frøsty:BAAANQADCgEIAQAAAA==.',
Fu='Furlock:BAAANQAECgEIAQAAAA==.Furryhugger:BAAANQAECggIEgAAAA==.Furrykisser:BAAANQADCgUIBQABNQAECggIEgACAAAAAA==.Furstab:BAAANQADCgQIBwAAAA==.',
['Fì']='Fìzzypop:BAAANQADCgEIAQAAAA==.',
Ga='Galepalm:BAAANQAECgUIBwAAAA==.Gambriniss:BAAANQAECgIIBAAAAA==.Gamea:BAABNQAECoEaAAIdAAcK+wm4IQCWAQAdAAcK+wm4IQCWAQAAAA==.Garloch:BAAANQADCgcIBwAAAA==.Gatoreggs:BAAANQAECgEIAQAAAA==.',
Ge='Geladra:BAAANQADCgcIBwABNQAECggIKwAPAK4cAA==.Gemmothy:BAAANQADCgYIDQAAAA==.',
Gi='Gibbychona:BAABNQAECoEdAAMeAAkKwRo+JgBTAgAeAAkKuBk+JgBTAgALAAEKAxc/fQBBAAAAAA==.Giggaho:BAAANQADCgIIAgAAAA==.',
Gl='Glowshroom:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.',
Go='Goldlust:BAAANQAECgEJAQAAAA==.Golotak:BAAANQADCgcIBwAAAA==.Gonnagetproc:BAAANQADCggICAAAAA==.Googale:BAAANQADCgIIAgAAAA==.Gordoc:BAAANQAECgQIBwAAAA==.Gothboy:BAAANQADCggICAAAAA==.',
Gr='Graff:BAAANQAECgYIDgAAAA==.Grailed:BAAANQADCgEIAQAAAA==.Gratiana:BAAANQAECgQIBwAAAA==.Gravem:BAAANQADCgUIBQAAAA==.Gravie:BAAANQADCgIIAgAAAA==.Graystaf:BAAANQAECgQICAAAAA==.Greggorie:BAAANQAECgEIAQAAAA==.Greyowl:BAAANQADCggIGAAAAA==.Greysun:BAAANQADCgUIBQAAAA==.Grifflez:BAAANQAECgYIDgAAAA==.Grumpli:BAABNQAECoEXAAIDAAkK6gxetQDLAQADAAkK6gxetQDLAQAAAA==.',
Gu='Guytheshower:BAAANQAECgUIDwAAAA==.Guytoo:BAAANQADCgUJBQAAAA==.',
Gw='Gweilo:BAAANQAECgUIBQAAAA==.',
Ha='Habek:BAAANQADCgQIBQAAAA==.Hamadaver:BAAANQABCgUICAAAAA==.Handofblood:BAAANQAECgYIDwAAAA==.Handymandy:BAAANQAFFAIIAgAAAA==.Harderrock:BAAANQADCgEIAQABNQAECgYICwACAAAAAA==.Hardrockgirl:BAAANQAECgYICwAAAA==.Harmonechi:BAABNQAECoEgAAIfAAgK3BRECgBBAgAfAAgK3BRECgBBAgAAAA==.Haveasip:BAAANQAECgIIAgAAAA==.',
He='Healdealer:BAAANQADCgQIBAAAAA==.Healmonbello:BAABNQAECoEXAAMMAAkKogvONwDhAQAMAAkKogvONwDhAQANAAUK2gJyQwCrAAAAAA==.Healystix:BAAANQAECgIIBAABNQAECgUIDAACAAAAAA==.Hellzcrusade:BAAANQAECgcIDAAAAA==.Henchi:BAAANQADCgIJAgABNQADCgUIFQACAAAAAA==.',
Hi='Higherheal:BAAANQADCgQIBAAAAA==.',
Ho='Hodesh:BAAANQADCgMJAwAAAA==.Holypuuss:BAABNQAECoElAAMSAAkK+SXfDACBAwASAAkKLSXfDACBAwATAAIKniEHPQCyAAABNQAFFAIIAgACAAAAAA==.Honeybumms:BAAANQAECgQJCQAAAA==.Hoplitedruid:BAAANQAECgUICgABNQAECgYIBwACAAAAAA==.Hoplitescout:BAAANQAECgYIBwAAAA==.Houndoom:BAAANQADCgYICgAAAA==.',
Ht='Htiál:BAAANQADCgIIAgAAAA==.Htiâl:BAAANQADCgIIAgABNQADCgIIAgACAAAAAA==.',
Hu='Huntko:BAAANQADCggIEAAAAA==.',
Hy='Hydrokyrios:BAAANQADCgYIBgAAAA==.Hyperthymia:BAABNQAECoEnAAIRAAkKnhseHgC/AgARAAkKnhseHgC/AgAAAA==.Hyrakka:BAAANQAECgEJAQABNQADCgUIFQACAAAAAA==.',
Ic='Iceeveins:BAAANQADCggICAAAAA==.Icystyx:BAAANQAECgUICAAAAA==.',
Il='Ilyamurometz:BAABNQAECoEVAAIKAAkKlRxLBgDCAgAKAAkKlRxLBgDCAgAAAA==.',
Im='Immorta:BAABNQAECoEcAAMXAAgKUw8/EABOAQAJAAgK+Q0wfQDPAQAXAAYKWQ8/EABOAQAAAA==.',
In='Indigokiya:BAAANQAECgYIDwAAAA==.Influencer:BAAANQADCgcIBwAAAA==.Ingesteel:BAAANQADCgEIAQAAAA==.Inodoro:BAABNQAECoEaAAIgAAgK2hoYCgCdAgAgAAgK2hoYCgCdAgAAAA==.',
Io='Iordgodplaya:BAAANQAECggICwAAAA==.',
Ir='Irabmal:BAABNQAECoElAAINAAgK6SAPCgDzAgANAAgK6SAPCgDzAgAAAA==.Iriclaw:BAACNQAFFIEJAAIFAAQK2iKTBQCdAQAFAAQK2iKTBQCdAQA1AAQKgSwAAgUACQrOJl4AAAUEAAUACQrOJl4AAAUEAAAA.Ironpanda:BAAANQADCgEIAQAAAA==.',
Is='Isaama:BAAANQADCgQIBAAAAA==.Isothymia:BAABNQAECoEbAAIBAAgK5g5eZACcAQABAAgK5g5eZACcAQABNQAECgkJJwARAJ4bAA==.',
It='Itsmepip:BAAANQAECgUIDQAAAA==.',
Ja='Jackiechanda:BAAANQABCgYIDQAAAA==.Jacoby:BAAANQAECgUIBQABNQAECgkJMQAgACAmAA==.Jadefires:BAAANQAECgMIAwAAAA==.Jadelite:BAAANQADCggIGgABNQAECgMIAwACAAAAAA==.Jaderanger:BAAANQADCgMIBAABNQAECgMIAwACAAAAAA==.Janddasham:BAAANQAECgYIDQAAAA==.Janddavoker:BAABNQAECoEqAAIaAAkKTSHzBABIAwAaAAkKTSHzBABIAwAAAA==.Jarnbrez:BAAANQADCgMIAwAAAA==.Jawnwick:BAAANQADCgMIAwAAAA==.Jaxo:BAAANQAECgYICwABNQAECggIEwACAAAAAA==.',
Jd='Jdag:BAAANQADCggICAAAAA==.',
Je='Jezrien:BAAANQADCgcIBwAAAA==.',
Jh='Jherri:BAAANQAECgQIBwAAAA==.',
Ji='Jimbeamer:BAAANQAECgEIAQAAAA==.',
Jk='Jkm:BAAANQAECgQICQAAAA==.',
Jo='Joanexotic:BAABNQAECoEUAAILAAYKrgm7RQAqAQALAAYKrgm7RQAqAQAAAA==.Joetothemama:BAAANQADCgYIBgAAAA==.Johnork:BAAANQADCggIDQAAAA==.Jojolion:BAAANQAECgQICQAAAA==.',
Jr='Jrocmfka:BAAANQAECgYICwAAAA==.',
Jt='Jtama:BAAANQADCgUIBwAAAA==.',
Ju='Junefyre:BAAANQADCgEIAQABNQAECgUICQACAAAAAA==.Juntor:BAAANQADCgcIBwAAAA==.',
Ka='Kaeliin:BAAANQADCgcJDAAAAA==.Kage:BAAANQADCgQIBgAAAA==.Kaiderten:BAAANQAECgEIAQAAAA==.Kailo:BAAANQAECgEIAQAAAA==.Kal:BAAANQADCgUICwAAAA==.Kalorondir:BAAANQADCgQICAAAAA==.Kamila:BAAANQADCggIDAAAAA==.Kaorí:BAAANQAECgcIDQAAAA==.Karatekyns:BAAANQADCgIIAgABNQAECggIGwAMALQUAA==.Kaselian:BAAANQAECgUIBgAAAA==.Kashimo:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.Katherwind:BAAANQABCgcIDAAAAA==.Kattara:BAABNQAECoEbAAMhAAgK/xbYCgAbAgAhAAgKuxLYCgAbAgAOAAUKexgzGQBYAQAAAA==.Kattarwal:BAAANQAECgEIAwAAAA==.Kayalanii:BAAANQADCggICAAAAA==.Kayoti:BAAANQADCgEJAQABNQAECgYICQACAAAAAA==.Kazuhla:BAAANQAECgQIDgAAAA==.',
Ke='Keiryn:BAAANQAECgIIAwAAAA==.Kentyrakka:BAAANQAECgUICQAAAA==.Keyndian:BAAANQADCggIDgAAAA==.',
Kh='Khaoptik:BAACNQAFFIERAAIDAAYK8RCFCQDxAQADAAYK8RCFCQDxAQA1AAQKgR4AAgMACQr0GixmAIECAAMACQr0GixmAIECAAAA.Khaotikdraco:BAAANQAECgQIBAABNQAFFAYIEQADAPEQAA==.Khaotikmeta:BAAANQAECgUICAAAAA==.',
Ki='Kiffypoo:BAAANQAECgUICgAAAA==.Kil:BAABNQAECoEnAAMVAAgKLRs0DACHAgAVAAgKLRs0DACHAgAUAAYKmgeAMwAJAQAAAA==.Kiljaiden:BAAANQABCgIIAgAAAA==.Kiltree:BAAANQAECgQIBAABNQAECggIJwAVAC0bAA==.Kisho:BAAANQADCgMIAwAAAA==.Kiyoshie:BAABNQAECoEiAAIFAAgKTxNdTgA2AgAFAAgKTxNdTgA2AgAAAA==.',
Kl='Klanky:BAAANQADCggICAABNQAFFAQICwAiAA4hAA==.',
Kn='Kn:BAAANQAECgIIAgAAAA==.Kneehighjake:BAAANQADCgYJBgAAAA==.',
Ko='Kobëbeef:BAAANQADCggIDwAAAA==.Kodiakpax:BAAANQADCgQJCAAAAA==.Kontroll:BAEANQADCggIIQABNQAECgMIBgACAAAAAA==.Kookee:BAABNQAECoEkAAIjAAgKzBqxSQAyAgAjAAgKzBqxSQAyAgAAAA==.Korice:BAAANQAECgYIDAAAAA==.',
Kr='Krieghelm:BAAANQAECgIIAgAAAA==.Krypticgrip:BAABNQAECoEeAAIeAAkK1SDaCQBLAwAeAAkK1SDaCQBLAwABNQAFFAYIEQADAPEQAA==.',
Ku='Kumaa:BAAANQAECgYIDgAAAA==.Kunclebun:BAAANQADCgUIBgAAAA==.',
Ky='Kyle:BAAANQAECgEIBAAAAA==.Kylidon:BAAANQADCgYIBgAAAA==.Kynlauriana:BAAANQAECgQIBAAAAA==.',
La='Lalaind:BAAANQADCgYICAAAAA==.Larissa:BAAANQAECgYIEQAAAA==.Lathillea:BAAANQAECgUICgAAAA==.Launchpad:BAAANQADCgQIBAAAAA==.Lazzirus:BAABNQAECoEbAAIQAAgKHx3WJwCoAgAQAAgKHx3WJwCoAgAAAA==.',
Le='Leedict:BAAANQAECgUJDAAAAA==.Leerøy:BAAANQAECgYIEAAAAA==.Leilani:BAAANQADCgYIGAAAAA==.Leinalei:BAAANQADCggICAABNQAECggIGwADAFEiAA==.Lessii:BAEBNQAECoEhAAIWAAkKcBwkHQCXAgAWAAkKcBwkHQCXAgAAAA==.Leyalis:BAAANQADCgYIBgAAAA==.',
Li='Lidande:BAAANQADCgYIBgAAAA==.Lidarcis:BAABNQAECoEbAAIeAAgKDiAFFgDPAgAeAAgKDiAFFgDPAgAAAA==.Liedora:BAAANQADCgYJDAAAAA==.Lightpraiser:BAAANQAECgUIDQAAAA==.Limjahey:BAAANQADCggIGAAAAA==.Linra:BAAANQAECgcIEQAAAA==.Littlefatt:BAABNQAECoEcAAIMAAgKlxHoNgDoAQAMAAgKlxHoNgDoAQAAAA==.',
Ll='Llich:BAAANQAECgMIBQAAAA==.',
Lo='Lostdogg:BAAANQADCgMIAwABNQAECgUIDQACAAAAAA==.',
Lu='Luassei:BAAANQADCgMICgAAAA==.Lucishifts:BAABNQAECoEbAAMMAAkKQyKZCAB2AwAMAAkKQyKZCAB2AwAOAAEKDSO/NABjAAAAAA==.Lucîan:BAAANQAECgMIAwAAAA==.Lumaris:BAAANQADCgcIBwAAAA==.Lunamorr:BAAANQADCgYIBgAAAA==.Luphoe:BAAANQADCgcIDgAAAA==.',
Ly='Lyserra:BAAANQAECgEIAgAAAA==.Lyudmila:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.',
Ma='Mabell:BAAANQADCgEIAQAAAA==.Mackori:BAAANQADCggJCwAAAA==.Maddawggamin:BAAANQADCgQIBAAAAA==.Maekar:BAAANQAECgIJAgAAAA==.Mafi:BAAANQADCgMIAwAAAA==.Magenos:BAAANQAECgQJBAAAAA==.Magic:BAAANQADCgUIBwAAAA==.Magicpants:BAAANQAECgIIBAAAAA==.Magobiga:BAAANQADCgYICAAAAA==.Mahrx:BAACNQAFFIEJAAIUAAUK4iI1AwDWAQAUAAUK4iI1AwDWAQA1AAQKgSMAAhQACQp1JVcEAHYDABQACQp1JVcEAHYDAAAA.Malaricia:BAAANQADCgMIAQAAAA==.Mangangazo:BAAANQADCggICAABNQAECgEIAwACAAAAAA==.Mawaru:BAAANQAECgQIBQAAAA==.Maxanadu:BAAANQADCgcIGAAAAA==.Mayalla:BAAANQAECgIIAgAAAA==.',
Me='Meatpipe:BAAANQAECgEIAQAAAA==.Medarela:BAAANQAECgUICwAAAA==.Meeke:BAACNQAFFIELAAIiAAQKDiGiBQCAAQAiAAQKDiGiBQCAAQA1AAQKgScAAiIACQq0Iz4EAH4DACIACQq0Iz4EAH4DAAAA.Mell:BAABNQAECoEnAAISAAkKUhxbNgCxAgASAAkKUhxbNgCxAgABNQAFFAIIAgACAAAAAA==.Melmin:BAAANQAECgQICwAAAA==.Meroman:BAAANQADCgUICwAAAA==.Metamora:BAAANQAECgMIBAABNQAECgUICQACAAAAAA==.Meuria:BAAANQAECgUICgAAAA==.',
Mi='Midgetlord:BAABNQAECoEpAAISAAkK1SL9FQBKAwASAAkK1SL9FQBKAwAAAA==.Miklos:BAAANQADCgcIEgAAAA==.Minxm:BAAANQADCgcIBgAAAA==.Minxmaxed:BAAANQADCggIEAAAAA==.Misstearly:BAAANQAECgQIBAAAAA==.Mividita:BAAANQADCggICAAAAA==.',
Mo='Modicon:BAAANQADCgEIAQAAAA==.Moltonmonk:BAAANQADCgcIBwAAAA==.Moneebagz:BAAANQADCggIGwAAAA==.Montblanc:BAAANQADCggJCAAAAA==.Moonchylde:BAAANQADCgUJBQABNQAECgYIEQACAAAAAA==.Moonem:BAABNQAECoEdAAIMAAgKfyDYFgDmAgAMAAgKfyDYFgDmAgAAAA==.Moosteerious:BAEANQAECgMIBgAAAA==.Mossacre:BAABNQAECoEiAAMJAAgKQR9vNgC0AgAJAAgKQR9vNgC0AgAXAAIKkhBgHQB/AAAAAA==.Mossherder:BAAANQABCgEIAQAAAA==.',
['Mé']='Méta:BAAANQAECgUICQAAAA==.',
Na='Naanda:BAAANQABCgcJCwAAAA==.Nachopapa:BAAANQADCggJEgAAAA==.Nalorspace:BAAANQADCgYIEQAAAA==.Naniwa:BAABNQAECoEXAAIRAAkKsiAJDwAjAwARAAkKsiAJDwAjAwAAAA==.Narwail:BAAANQAECgYIDgAAAA==.Narwhall:BAAANQADCggIEQABNQAECgYIDgACAAAAAA==.Nasathen:BAAANQAECgEIAQABNQAECgUICgACAAAAAA==.Natanus:BAAANQADCgUICwAAAA==.Natsuko:BAAANQADCgMIAwAAAA==.Nazaric:BAAANQAECgcIDwAAAA==.Nazaricksm:BAAANQADCgMIAwABNQAECgcIDwACAAAAAA==.Nazgeul:BAAANQADCgYICwAAAA==.',
Nb='Nbi:BAAANQABCgQJBQABNQAECgUICgACAAAAAA==.',
Ne='Necrodik:BAAANQADCgQIBAAAAA==.Neladris:BAAANQADCgIIAgAAAA==.Nelagorn:BAAANQAECgUIBQAAAA==.Nemesís:BAAANQABCgYIBwAAAA==.Neohorn:BAAANQAECgEIAwAAAA==.Neomyk:BAAANQADCggJDgAAAA==.Neoptolemus:BAAANQADCgUICwAAAA==.Neoqled:BAAANQAECgMJAwAAAA==.Neorhon:BAAANQADCgUIBQAAAA==.Nerclopse:BAABNQAECoEmAAIQAAgK4hXGOABMAgAQAAgK4hXGOABMAgAAAA==.Nerco:BAAANQADCgYIBgABNQAECggIJgAQAOIVAA==.Neverender:BAAANQAECgUICQAAAA==.Nexian:BAAANQABCgQIBgAAAA==.',
Ni='Niarwodahs:BAAANQAECgMIBQAAAA==.Niaryci:BAAANQAECgUICgAAAA==.Nightfangz:BAAANQADCgYIDAAAAA==.Nils:BAAANQADCgYIBwAAAA==.Nims:BAAANQADCgUICwABNQAECgQICgACAAAAAA==.',
Nm='Nmoney:BAAANQAECgMIAwAAAA==.',
No='Noritotem:BAAANQAECgcIEwAAAA==.Note:BAAANQADCgUICQAAAA==.Notec:BAAANQADCggIAQAAAA==.Notics:BAAANQAECgIIAgAAAA==.Novacainê:BAAANQAECgQIBgAAAA==.',
Nu='Nuff:BAAANQADCgUICQAAAA==.Nuikai:BAAANQAECgUJDgAAAA==.Nukum:BAAANQADCgYICwAAAA==.',
Ob='Obsidiansun:BAAANQAECgQIBwAAAA==.',
Oc='Octame:BAAANQAECgQIBgAAAA==.',
Ol='Olethvia:BAAANQADCgQIBwABNQAECgUICQACAAAAAA==.',
On='Onirai:BAAANQADCgUIBQAAAA==.Onlylight:BAAANQADCggICAAAAA==.',
Oo='Oopsy:BAAANQADCgEIAQAAAA==.Ooran:BAAANQADCggICAAAAA==.Oororoe:BAAANQADCgUIBQAAAA==.',
Op='Opalescence:BAAANQADCgcIGgAAAA==.Opie:BAAANQABCgIJAgAAAA==.Optional:BAABNQAECoEgAAIPAAkKgyWLAACeAwAPAAkKgyWLAACeAwAAAA==.',
Or='Orgargo:BAAANQAECgUICgAAAA==.',
Os='Osley:BAAANQADCgMIBgAAAA==.',
Ou='Oule:BAEBNQAECoEbAAIVAAkKKBNgEAAsAgAVAAkKKBNgEAAsAgAAAA==.',
Pa='Pallorx:BAAANQADCgYIBgAAAA==.Pallyzombi:BAAANQADCgYICgABNQAECggIGgADAEsXAA==.Paluoth:BAAANQADCgEIAQAAAA==.Pandasennin:BAAANQADCgUICwAAAA==.Papachains:BAAANQADCgYIDAABNQAECggJAQACAAAAAA==.Papahammer:BAAANQAECggIBgABNQAECggJAQACAAAAAA==.Papamuffin:BAAANQAECggICAABNQAECggJAQACAAAAAA==.Papashootin:BAAANQAECggJAQAAAA==.Paperplate:BAABNQAECoEtAAMNAAgKQyJ2CAAPAwANAAgKQyJ2CAAPAwAMAAYKtxO2RgCBAQAAAA==.Paradox:BAABNQAECoElAAIhAAkKdiEgAgBxAwAhAAkKdiEgAgBxAwAAAA==.Pattyhealsu:BAACNQAFFIEKAAIRAAUKwBTKBgCiAQARAAUKwBTKBgCiAQA1AAQKgSIAAhEACQqpIRwPACMDABEACQqpIRwPACMDAAAA.Pawlyn:BAAANQADCgEIAQAAAA==.',
Pe='Peachizz:BAAANQAECgEIAQAAAA==.Pelikohjo:BAAANQAECgQICAABNQAECggIKQAPAP8YAA==.Pelivarondo:BAABNQAECoEpAAMPAAgK/xhTBQAfAgAPAAcKDRtTBQAfAgAFAAMKMg4d6AC0AAAAAA==.Pelizandeth:BAAANQADCggIHAABNQAECggIKQAPAP8YAA==.Pepegas:BAAANQADCggJHQAAAA==.Pestillia:BAABNQAECoEYAAIkAAcKNRhYBQArAgAkAAcKNRhYBQArAgAAAA==.',
Ph='Phoffynax:BAAANQAECgMIAwAAAA==.Phundip:BAAANQADCgMIBgABNQAECgQICgACAAAAAA==.',
Pi='Pistolbeat:BAAANQADCgUIBQAAAA==.',
Pk='Pkthunder:BAAANQADCgUIBQAAAA==.',
Pl='Playful:BAAANQADCggIDgAAAA==.Plopopotamus:BAABNQAECoEZAAQPAAgKYh+6AwCAAgAPAAcK9B26AwCAAgAlAAYKUxbxLgB8AQAFAAEKriaiBAFZAAAAAA==.',
Po='Poedanrin:BAAANQAECgEJAQAAAA==.Polikarp:BAAANQABCgQIBwAAAA==.Pookìe:BAAANQAECgQJBgABNQAECgUIBgACAAAAAA==.Poorsol:BAAANQAECgQICAAAAA==.',
Ps='Psychoclaw:BAAANQAECgIJAgAAAA==.Psyko:BAAANQADCgMIAwABNQADCggICAACAAAAAA==.',
Qu='Quickbrown:BAAANQAECgMIBQAAAA==.',
Ra='Raced:BAAANQADCgQIBAAAAA==.Ragenel:BAAANQAECgEIAQAAAA==.Rahxe:BAAANQAECgMIAwAAAA==.Raikz:BAAANQAECgUICwAAAA==.Raiyne:BAAANQADCggIDwAAAA==.Randolphus:BAAANQAECgUIBgAAAA==.Rateddz:BAAANQAECgEIAQAAAA==.Ratraxa:BAAANQADCgYIBgAAAA==.Rats:BAABNQAECoEyAAIbAAkK/iICBACJAwAbAAkK/iICBACJAwAAAA==.Ratshield:BAABNQAECoEZAAIKAAgKbxu1CAB3AgAKAAgKbxu1CAB3AgABNQAECgkJMgAbAP4iAA==.Ratwynne:BAAANQADCggICAAAAA==.',
Re='Regifted:BAAANQADCgYIBgAAAA==.Rendis:BAAANQADCgIIAgAAAA==.Reno:BAABNQAECoEYAAIFAAcKORIzawDjAQAFAAcKORIzawDjAQAAAA==.Renthyr:BAAANQADCgUIBQAAAA==.Reportcard:BAAANQAECgEIAQABNQAECggIDAACAAAAAA==.Reurog:BAAANQAECgUIDwAAAA==.Revanjmt:BAAANQADCgYIBAAAAA==.',
Rh='Rhakudu:BAAANQADCgYIBgABNQAECgUIDgACAAAAAA==.',
Ri='Rian:BAACNQAFFIEIAAIlAAUKkRblBgCWAQAlAAUKkRblBgCWAQA1AAQKgR8AAiUACQp/I2oFAGcDACUACQp/I2oFAGcDAAE1AAUUBwgOAAMAyRoA.Rigbee:BAAANQADCgUIBQAAAA==.Ritalia:BAAANQAECgcIDgAAAA==.',
Rm='Rmnieech:BAAANQAECgUICgAAAA==.',
Ro='Roadiee:BAAANQAECgIIAgAAAA==.Roadiex:BAAANQADCgIIAwAAAA==.Roadkyll:BAAANQAECgEIAgAAAA==.Ronynn:BAAANQADCgEIAQAAAA==.Rosamoon:BAAANQADCggJEgAAAA==.Rosilyn:BAAANQAECgUICgAAAA==.',
Ru='Rugbee:BAAANQADCgQIBAAAAA==.Rurrick:BAAANQAECgEIAQAAAA==.',
Ry='Ryzee:BAABNQAECoEUAAIRAAcKQRLrXQCfAQARAAcKQRLrXQCfAQAAAA==.',
['Rå']='Råinè:BAAANQADCgcIBwABNQAECgMIAwACAAAAAA==.',
Sa='Sahmash:BAAANQADCgIIAgAAAA==.Salara:BAAANQAECgUIEQAAAA==.Salasong:BAAANQADCgYIEgAAAA==.Saltytoast:BAAANQAECgEIAQAAAA==.Sambda:BAAANQADCgYIBwABNQAECgEIAQACAAAAAA==.Samberia:BAAANQADCgIIAgAAAA==.Sambilton:BAAANQADCgUIBQAAAA==.Sambraicho:BAAANQADCggIDAABNQAECgEIAQACAAAAAA==.Samburai:BAAANQAECgEIAQAAAA==.Samuella:BAAANQAECgcIEAAAAA==.Sandrinea:BAAANQAECgYIDQAAAA==.Sarinya:BAAANQADCggIFgAAAA==.Sauceym:BAAANQABCgcICQAAAA==.Saytens:BAAANQAECggJEAAAAA==.',
Sc='Scargiver:BAAANQADCgEJAQAAAA==.Scarllett:BAAANQAECgIIBQABNQAECggIEgACAAAAAA==.Scarykyns:BAAANQADCgYIBgABNQAECggIGwAMALQUAA==.Schatzi:BAAANQADCggICAAAAA==.Scrubmage:BAAANQAECgIIAgAAAA==.',
Se='Secondwall:BAAANQAECgQIBAAAAA==.Sedale:BAAANQAECgUICQAAAA==.Seesdeline:BAAANQADCggIBwABNQADCgYICAACAAAAAA==.Seilene:BAAANQADCgcIHQABNQAECgEIAwACAAAAAA==.Selisi:BAAANQAECgQICAABNQAECgUICgACAAAAAA==.Senddra:BAAANQABCgYICAAAAA==.Seo:BAAANQAECgUICwAAAA==.Seraf:BAABNQAECoEuAAMeAAkKyiWQAQDVAwAeAAkKqSWQAQDVAwAWAAkKqiGlDgAYAwAAAA==.Serafain:BAAANQAECggIDQABNQAECgkJLgAeAMolAA==.',
Sh='Shadowerise:BAAANQAECgMIAwAAAA==.Shaforgold:BAABNQAECoEeAAIQAAkKch5CFgAdAwAQAAkKch5CFgAdAwAAAA==.Shalaz:BAAANQADCggJCAAAAA==.Shalazard:BAAANQAECgQIBwAAAA==.Shamananana:BAAANQADCgYIBgAAAA==.Sharrina:BAAANQABCgEIAQAAAA==.Shawtyschit:BAAANQAECggIDAAAAA==.Shibal:BAABNQAECoEYAAMBAAcK9hVPYgCjAQABAAYK+hRPYgCjAQASAAMKMwhnCAGaAAAAAA==.Shinerbock:BAAANQADCgUIBQAAAA==.Shinystepdad:BAAANQADCgUIBQAAAA==.Shotorock:BAAANQAECgIIAgAAAA==.Shreckfive:BAAANQAECgQIBwAAAA==.Shrekismydad:BAAANQADCgQIBAAAAA==.Shroompie:BAAANQADCgcIDQABNQAECgMIAwACAAAAAA==.Shroomshock:BAAANQAECgMIAwAAAA==.Shushumen:BAAANQAECgYIEQAAAA==.Shänk:BAAANQADCgcIDgAAAA==.',
Si='Sicknezz:BAAANQADCgYJCwABNQAECggIEAACAAAAAA==.Sidewinder:BAAANQAECgQIBQABNQAECgkJIAAPAIMlAA==.Siinyster:BAAANQADCgMIAwAAAA==.Sikmode:BAAANQAECgQICgAAAA==.Sildrusil:BAAANQADCgEIAQAAAA==.Silverstarz:BAAANQABCggIFQABNQAECgkJJwAMAG4hAA==.Sindari:BAAANQAECgcIEgAAAA==.Sinturio:BAAANQAECgUICgAAAA==.Sipsy:BAAANQAECgQICQAAAA==.',
Sk='Skarg:BAAANQAECgMICQAAAA==.Skyeashe:BAAANQADCgYIGAAAAA==.',
Sl='Sleezytease:BAAANQADCgcIBwAAAA==.Slimdusty:BAAANQADCgQICAAAAA==.Slingblades:BAAANQAECggIEAAAAA==.Slobbrknckr:BAAANQADCgcIBwABNQAFFAIIAgACAAAAAA==.Slowmo:BAAANQAECggJDAAAAA==.',
Sm='Smittles:BAAANQAECgYICQAAAA==.',
Sn='Sneakystix:BAAANQADCgYIBgABNQAECgUIDAACAAAAAA==.Snowtigerr:BAAANQABCgIJAgAAAA==.',
So='Solarflare:BAAANQADCgQIBAAAAA==.Sootclaw:BAAANQADCgYICQAAAA==.Sophus:BAAANQAECgQIBwAAAA==.Soren:BAAANQADCgYICAAAAA==.Sorenko:BAAANQAECgQIBQABNQADCgYICAACAAAAAA==.',
Sp='Spagooter:BAABNQAECoEhAAMjAAkKKB7cJQC3AgAjAAgK/h7cJQC3AgAfAAEKdRf2YwBCAAAAAA==.Sparklepants:BAABNQAECoEhAAIDAAkKbCADIwA7AwADAAkKbCADIwA7AwAAAA==.Spencerz:BAAANQADCgEIAQAAAA==.Speyesee:BAAANQAECgUIDQAAAA==.Splashydank:BAAANQAECgEIAQAAAA==.Spookyish:BAAANQAECgUJCgAAAA==.',
Sq='Squidstens:BAAANQABCgMIAwAAAA==.',
St='Stabbydank:BAAANQAECgIIAgAAAA==.Stackss:BAAANQAECgEIAQAAAA==.Staypuff:BAAANQABCgMIAwAAAA==.Stnkychz:BAAANQADCggIDwAAAA==.Stonedninja:BAAANQADCgIIAQAAAA==.Stonemason:BAAANQAECgUIBgAAAA==.Stoneskin:BAAANQADCgUJCQAAAA==.Strawberymik:BAAANQADCgEIAQAAAA==.',
Su='Submisive:BAAANQAECgEJAQAAAA==.Supe:BAAANQAECgQICAAAAA==.Superstar:BAAANQADCggICAAAAA==.',
Sw='Swagruid:BAAANQAECgYIEQAAAA==.Swampslinger:BAAANQAECgUICwAAAA==.Swordlady:BAAANQAECgUIEQABNQAECggIIAAGAGgZAA==.',
Sy='Syncxx:BAAANQADCgIIAgAAAA==.Syntari:BAAANQAECgQIBgAAAA==.Syntyr:BAAANQADCgMIAwAAAA==.Synyra:BAAANQADCgcIBwAAAA==.Synìk:BAAANQADCgUICgAAAA==.',
['Sö']='Söma:BAAANQAECgYICQAAAA==.',
Ta='Taktixxloxx:BAAANQABCgMIAwAAAA==.Talenalat:BAAANQAECggIBAAAAA==.Tankerbelle:BAAANQADCgEIAQAAAA==.Tannarisse:BAAANQADCgQIBQAAAA==.Taymatt:BAAANQAECgQICQAAAA==.Tazstinko:BAABNQAECoEmAAIJAAkKRR+4GgAvAwAJAAkKRR+4GgAvAwAAAA==.',
Te='Teaveen:BAAANQAECgIIAgAAAA==.Tectonic:BAAANQAECgYIDAABNQAFFAMIBgAEAOgTAA==.Tejasgeek:BAAANQAECgQICAAAAA==.Tenleron:BAAANQABCgIIAgAAAA==.Tenntoes:BAAANQADCgYIBgAAAA==.Tewiyakichkn:BAAANQAECgcICAAAAA==.',
Th='Thegoob:BAAANQABCgMIAwAAAA==.Theiceflare:BAAANQADCgcIFwAAAA==.Themuffinman:BAAANQAECgIIAwAAAA==.Theworrirawr:BAABNQAECoEeAAMOAAkKHyZ9AADtAwAOAAkKHyZ9AADtAwAhAAMKZR+6FgAaAQAAAA==.Thour:BAAANQABCgIIAgAAAA==.Thur:BAAANQAECgcIEwAAAA==.Thänatos:BAAANQAECgIIAgAAAA==.',
Ti='Tiesci:BAABNQAECoEbAAIDAAgKUSJmOwDxAgADAAgKUSJmOwDxAgAAAA==.Tinyclash:BAAANQADCgQIBAAAAA==.Tinypap:BAAANQADCggIFwAAAA==.Tippe:BAAANQADCggIGAAAAA==.',
Tl='Tlálocx:BAAANQAECgQIBwAAAA==.',
To='Toastedblade:BAAANQAECgQJBwAAAA==.Toldyousoul:BAAANQAECgEIAQAAAA==.Tomatomage:BAAANQADCgUIBQAAAA==.Tonytots:BAAANQAECgQIBAAAAA==.Tottemakk:BAAANQADCgEIAQAAAA==.Toughshots:BAAANQADCgEIAQAAAA==.Toxenima:BAAANQAECgUIDAAAAA==.Toxiciti:BAAANQAECgUICQAAAA==.',
Tr='Tramlaw:BAAANQADCgIIAgAAAA==.Trashedara:BAAANQADCgUIBQAAAA==.Treebirth:BAABNQAECoEmAAINAAkKLCLZAwBuAwANAAkKLCLZAwBuAwAAAA==.Treyu:BAAANQADCgYIBgAAAA==.Triegh:BAAANQAECgMIAwAAAA==.Trolljones:BAAANQADCgYIBgAAAA==.Troyano:BAAANQADCgQIBAAAAA==.Trunder:BAAANQAECgYIDgAAAA==.Trush:BAAANQADCgIIAgAAAA==.',
Ts='Tsaindorcus:BAABNQAECoEbAAIeAAYKMwlPaQADAQAeAAYKMwlPaQADAQAAAA==.Tsunamyz:BAAANQAECgEIAQAAAA==.',
Tu='Tuskgwel:BAAANQADCgIIAQAAAA==.',
Ty='Tyfoon:BAAANQABCgIIAgAAAA==.',
Ud='Uders:BAAANQAECgYIDAAAAA==.',
Uh='Uhlvar:BAAANQAECgcICwAAAA==.Uhm:BAABNQAECoEaAAIJAAkKlyNnDwBvAwAJAAkKlyNnDwBvAwAAAA==.',
Ui='Uil:BAEANQAECgIIAgABNQAECgkJGwAVACgTAA==.',
Ul='Ultramad:BAAANQAECgcJDQAAAA==.Ultramellow:BAAANQAECgEIAQABNQAECgcJDQACAAAAAA==.',
Un='Unclesquid:BAAANQADCggIEwAAAA==.Unholydubzzy:BAAANQADCgEIAQAAAA==.',
Up='Upngo:BAABNQAECoEkAAIJAAkKHyIgEABqAwAJAAkKHyIgEABqAwAAAA==.',
Ur='Urotherdaddy:BAAANQADCgEIAQABNQAECgEIAQACAAAAAA==.',
Us='Uskthyr:BAAANQAECgEIAQAAAA==.',
Va='Vanakin:BAAANQAECgQIBAABNQAFFAcIFwAYAIEcAA==.Vandredor:BAACNQAFFIEXAAIYAAcKgRz2AACXAgAYAAcKgRz2AACXAgA1AAQKgSEAAxgACQrmITwQAOsCABgACQq4ITwQAOsCABwABgpaHOAKAMcBAAAA.Varntrah:BAAANQADCgQIBAAAAA==.Vastatio:BAAANQADCgEIAQAAAA==.Vasträ:BAAANQADCgUICwAAAA==.',
Ve='Velicelia:BAABNQAECoEbAAMLAAgKUQo2PwBVAQALAAcKSwo2PwBVAQAWAAEKdQrQsAAxAAAAAA==.Vesroth:BAAANQAECgUIDQAAAA==.',
Vi='Viborge:BAAANQADCggIEAAAAA==.View:BAABNQAECoEhAAIPAAkKnyOUAACaAwAPAAkKnyOUAACaAwAAAA==.Vince:BAAANQAECgIIAgAAAA==.Vissra:BAAANQAECgQIBAABNQAECggIKwASAIwXAA==.',
Vo='Vojak:BAAANQAECgUIBQAAAA==.',
Vu='Vulpermon:BAAANQADCgMIBAAAAA==.Vuly:BAAANQADCgEIAQAAAA==.',
['Vä']='Vääko:BAAANQAECgIIBAAAAA==.',
['Ví']='Vínce:BAAANQADCgIIAgAAAA==.',
Wa='Waluigi:BAAANQADCggJCAABNQAECgQIBQACAAAAAA==.Warbaby:BAAANQADCggIDwAAAA==.Warlarren:BAAANQADCgEIAQAAAA==.',
We='Weatherr:BAABNQAFFIEIAAMjAAQKWhMPDABGAQAjAAQKWhMPDABGAQAfAAEKcQlrGgBKAAAAAA==.Weki:BAAANQADCggIDAAAAA==.Wetshrimp:BAAANQAECgUIBgABNQAECgkJJgADAOMdAA==.',
Wh='Whippoorwill:BAABNQAECoEhAAMMAAgKTRYsLwAgAgAMAAgKDBQsLwAgAgAhAAIKsBITIgCLAAAAAA==.Whiskyslayer:BAAANQAECggIEAAAAA==.Whosmofunky:BAAANQADCgcJBwAAAA==.',
Wi='Wickeda:BAAANQAECgQIBwAAAA==.Williamp:BAAANQADCgYICgAAAA==.',
Wn='Wntlmd:BAAANQAECgMIBQAAAA==.',
Wo='Wolfnacht:BAAANQAECgQICAAAAA==.',
Wu='Wukangmei:BAAANQADCgMIAwAAAA==.',
['Wà']='Wàrødør:BAAANQAECgQIBQAAAA==.',
Xe='Xene:BAABNQAECoEYAAIQAAUKnSDdWgDAAQAQAAUKnSDdWgDAAQAAAA==.',
Xh='Xhade:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.',
Xr='Xriss:BAAANQADCggIFgAAAA==.Xrs:BAAANQADCgQIBQABNQAECgQICgACAAAAAA==.',
Ya='Yanedin:BAABNQAECoEiAAImAAkKJAYzEwBqAQAmAAkKJAYzEwBqAQAAAA==.Yathrr:BAAANQADCgYICwAAAA==.',
Yi='Yippeezippee:BAAANQABCgMIBQAAAA==.',
Yo='Yorforger:BAAANQAECgQIBAABNQAECggIEwACAAAAAA==.Youngbj:BAAANQAECgcICAABNQAECgcICwACAAAAAA==.Younger:BAAANQAECgEIAgAAAA==.Youngerxx:BAAANQADCgYIBgAAAA==.Youngerxz:BAAANQAECgIIAgAAAA==.',
Ys='Yserene:BAAANQADCgcJDAAAAA==.',
Yu='Yukonícus:BAAANQAECgYIBgABNQAECgkJKwAYAJghAA==.Yukonïcus:BAABNQAECoErAAMYAAkKmCGpBgBtAwAYAAkKmCGpBgBtAwAcAAUKuxcDDwBlAQAAAA==.Yumm:BAAANQADCgcIBwAAAA==.Yuridemo:BAAANQAECgcIDAAAAA==.',
['Yè']='Yènnefer:BAAANQADCggIGAAAAA==.',
Za='Zaldrena:BAAANQADCgYIBgAAAA==.Zanotgaming:BAAANQADCgcIBwAAAA==.Zaraydorine:BAAANQADCgUIBQAAAA==.',
Zb='Zbrickashaw:BAAANQAECgUIDAAAAA==.',
Ze='Zelrin:BAACNQAFFIENAAIDAAUKYxvlDQC7AQADAAUKYxvlDQC7AQA1AAQKgSIAAgMACQpKGRdgAJECAAMACQpKGRdgAJECAAAA.Zenthalion:BAAANQAECgEIAQAAAA==.',
Zi='Zippee:BAAANQADCgQIBAAAAA==.',
Zo='Zobi:BAAANQADCgMIAwAAAA==.Zoomhunt:BAABNQAFFIEJAAMlAAUKMByMCQBaAQAlAAQKHh6MCQBaAQAFAAEKeBS2JABRAAAAAA==.Zoommage:BAABNQAECoEbAAIDAAkKKSA+MgALAwADAAkKKSA+MgALAwABNQAFFAUICQAlADAcAA==.',
Zu='Zuluugargorg:BAAANQAECgUICgAAAA==.',
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
