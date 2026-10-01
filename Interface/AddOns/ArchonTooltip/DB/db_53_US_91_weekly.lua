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

local lookup = {'Druid-Balance','Shaman-Elemental','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Rogue-Assassination','Druid-Restoration','Warlock-Destruction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Paladin-Holy','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','DeathKnight-Blood',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-09-29',data={Al='Alodiar:BAAANQADCgIIBAAAAA==.',
Am='Amadellaves:BAAANQADCgQIBAAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECoEcAAIBAAgKvRHgMgAEAgABAAgKvRHgMgAEAgAAAA==.Annde:BAABNQAECoEdAAICAAkKRRTiNABfAgACAAkKRRTiNABfAgAAAA==.Anyana:BAAANQADCgQIBAABNQAECgQJBAADAAAAAA==.',
Ar='Artemus:BAACNQAFFIEIAAMEAAUK1gPUAwBHAQAEAAUK1gPUAwBHAQAFAAEKlwJ9EAA1AAA1AAQKgScAAwQACQqFGxoJAMwCAAQACQqFGxoJAMwCAAUABgqoDf4tADwBAAE1AAMKBAgEAAMAAAAA.Arïel:BAAANQAECgMIBAAAAA==.',
Be='Beeftoteeth:BAAANQAECgMIAwAAAA==.Ber:BAAANQAECgQIBgABNQAECgkJIwAGAAwWAA==.Bexxy:BAAANQADCggIDQAAAA==.',
Bi='Bibicrits:BAAANQABCggICQABNQAECggIHwAHADoZAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgUICAAAAA==.',
Br='Broadfang:BAACNQAFFIEPAAMIAAUKqBTaBwCCAQAIAAUKqBTaBwCCAQAJAAEK/wJHKwA+AAA1AAQKgSwAAwgACQr6HXYQAL4CAAgACQr6HXYQAL4CAAkAAQrHDGAPAUMAAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICAAAAA==.Bullorly:BAACNQAFFIEGAAIKAAUKxhkLAwCzAQAKAAUKxhkLAwCzAQA1AAQKgSUAAgoACQoLJeoCALMDAAoACQoLJeoCALMDAAAA.',
Ca='Catirus:BAAANQADCgYIBgAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECggIIgAEABoWAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAAANQAECgUIDgAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQADCgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgIJAwAAAA==.',
Cr='Crispicrits:BAAANQAECgEJAQABNQAECgkJGgALAJMXAA==.',
Cy='Cynîc:BAAANQAECgMJBgAAAA==.',
Da='Dalaran:BAABNQAECoEjAAIHAAgK+QrkJwDHAQAHAAgK+QrkJwDHAQAAAA==.Darenas:BAABNQAECoEtAAIMAAkKrR2GCgATAwAMAAkKrR2GCgATAwAAAA==.Darkwing:BAAANQABCgIIAQABNQAECgQIBAADAAAAAA==.',
De='Deathbooze:BAABNQAECoEfAAIKAAgKnCIBFQDcAgAKAAgKnCIBFQDcAgAAAA==.Deathmikee:BAABNQAECoEZAAIKAAkK8yBmCwA6AwAKAAkK8yBmCwA6AwAAAA==.Delilah:BAAANQAECgUIBQAAAA==.Delita:BAAANQADCgcIDwAAAA==.Demonea:BAAANQADCgYIBgAAAA==.Derek:BAAANQAECgUIBwAAAA==.',
Dr='Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECoEfAAMNAAgKZx6TAwDQAgANAAgKZx6TAwDQAgAOAAEKDwcYGAE2AAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECgcIBAAAAA==.',
El='Elderdorje:BAABNQAECoEiAAMEAAgKGhY6EQAcAgAEAAgKGhY6EQAcAgAFAAcKvAUfNgDzAAAAAA==.Elixe:BAAANQADCggICAAAAA==.Elmersglue:BAAANQADCgEIAQAAAA==.Elondre:BAABNQAECoEfAAIPAAgKlhtiMABdAgAPAAgKlhtiMABdAgAAAA==.',
Ev='Evangeliné:BAAANQADCggICAABNQAECgYIDgADAAAAAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECoEfAAIHAAgKOhlvGABmAgAHAAgKOhlvGABmAgAAAA==.',
Fi='Firecracker:BAAANQAECgEIAQAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgEIAQABNQAECgkJJAAEAKwcAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQADCgQIBQABNQAECgkJIwAGAAwWAA==.Galatea:BAABNQAECoEnAAIQAAkKzh1fIAASAwAQAAkKzh1fIAASAwAAAA==.Galifen:BAABNQAECoEkAAIBAAkKeyQTAgDRAwABAAkKeyQTAgDRAwAAAA==.Gank:BAABNQAECoEXAAIRAAkKMxu0DgDQAgARAAkKMxu0DgDQAgAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICAAAAA==.',
Gi='Gilgahmesh:BAAANQAECgQIBAAAAA==.',
Gn='Gnomegrown:BAAANQAECgQIBQAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAQAAAA==.',
Ha='Halyer:BAAANQADCgYIDwAAAA==.Hamalainen:BAAANQAECgYICgABNQAECgkJJAAEAKwcAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQADCggIAwAAAA==.',
He='Helioboops:BAAANQADCgUICQAAAA==.',
Ho='Hobbz:BAACNQAFFIEHAAIQAAUKfQ11BwB4AQAQAAUKfQ11BwB4AQA1AAQKgR8AAhAACQqiHkouANICABAACQqiHkouANICAAAA.',
Il='Illandros:BAAANQAECgQICwAAAA==.',
In='Inspire:BAACNQAFFIELAAISAAQK1BfiBQBBAQASAAQK1BfiBQBBAQA1AAQKgSgAAhIACQpOImAFAEwDABIACQpOImAFAEwDAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgEIAQAAAA==.',
Ja='Jaína:BAAANQAECgIIAgABNQAECgUICgADAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAECgkJJAAEAKwcAA==.',
Je='Jelina:BAAANQADCgcICgAAAA==.',
Ji='Jiren:BAABNQAECoEkAAIEAAkKrBz+BgD5AgAEAAkKrBz+BgD5AgAAAA==.',
Jo='Johnson:BAAANQAECgcIDAAAAA==.Joran:BAAANQAECgUICAAAAA==.',
Kr='Kro:BAAANQADCgEIAQAAAA==.',
Le='Leanea:BAAANQAECgIIAgAAAA==.',
Li='Liera:BAAANQAECgUIBAAAAA==.Lightsac:BAAANQADCgYIBgAAAA==.Limmywinks:BAAANQADCgQJBAAAAA==.',
Ll='Lloydlei:BAAANQAECgcIDwAAAA==.',
Lu='Luminå:BAABNQAECoEbAAITAAgKehwWBQC7AgATAAgKehwWBQC7AgAAAA==.',
Ma='Maibisan:BAABNQAECoE0AAMUAAkKuyVGAQDhAwAUAAkKuyVGAQDhAwAHAAcKYyIUFQCPAgAAAA==.Malificent:BAAANQAECgMIAwAAAA==.',
Me='Metaevoker:BAABNQAECoEjAAIVAAkK8BQNDgBHAgAVAAkK8BQNDgBHAgAAAA==.',
Mo='Monawah:BAAANQAECgQICwAAAA==.Mookong:BAAANQADCgYIBwAAAA==.Moonsliver:BAAANQAECgEIAwAAAA==.Moorf:BAAANQADCgUIBQAAAA==.Morff:BAAANQAECgYIDwAAAA==.Motleychew:BAAANQADCggICAAAAA==.',
My='Mystwolf:BAAANQAECgUJBwAAAA==.',
Ni='Nightski:BAAANQAECgYIBwAAAA==.Nizzari:BAAANQAECgEIAwABNQAECgkJIwAGAAwWAA==.',
No='Nobuseri:BAAANQABCgYIBgAAAA==.Nothalyer:BAABNQAECoEcAAIWAAcK3QanJQBEAQAWAAcK3QanJQBEAQAAAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgIIBAAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQADCggIHwADAAAAAA==.Orwasitme:BAAANQADCggIHwAAAA==.Orwasitmii:BAAANQADCgMJAwABNQADCggIHwADAAAAAA==.',
Pa='Paladinii:BAAANQADCgQICgAAAA==.',
Ph='Philonk:BAAANQAECgcICwAAAA==.',
Pj='Pjxyo:BAAANQAECgUIDwAAAA==.',
Po='Polytots:BAACNQAFFIEIAAMPAAUKpgtqCAB6AQAPAAUKpgtqCAB6AQACAAIKYAbIGwCKAAA1AAQKgSkAAg8ACQpZIvsFAHwDAA8ACQpZIvsFAHwDAAAA.',
Ps='Psycototem:BAAANQAECgIIAgAAAA==.',
Ra='Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAAANQAECgMIBQAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAAANQAECgEJAgABNQAECgkJJAAEAKwcAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ry='Ryzenther:BAAANQAECgIJAwAAAA==.',
['Rà']='Ràgñar:BAAANQADCgYIEQAAAA==.',
Sc='Scathclipe:BAABNQAECoEhAAMRAAgKORd2IQAaAgAXAAgKLBUjBwAfAgARAAgKEhJ2IQAaAgAAAA==.',
Se='Seancodi:BAAANQAECgEIAQABNQAFFAYIEQAHAFkXAA==.Senomage:BAABNQAECoEZAAMYAAgKTiOVOwDxAgAYAAgKTiOVOwDxAgAZAAMK/R3TFgACAQAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAABNQAECoEWAAIaAAcKYh8YCQB4AgAaAAcKYh8YCQB4AgAAAA==.Shockss:BAAANQAECgUIBQAAAA==.',
Si='Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECoEaAAILAAkK7QkLUQDZAQALAAkK7QkLUQDZAQAAAA==.',
Sk='Skyepic:BAACNQAFFIEaAAIbAAcKARpaAQB3AgAbAAcKARpaAQB3AgA1AAQKgSYAAhsACQp+JnUAAO8DABsACQp+JnUAAO8DAAAA.Skylight:BAAANQAECggICAAAAA==.',
Sn='Sneakfu:BAABNQAECoEbAAMcAAcK8hdxFwD/AQAcAAcKNRZxFwD/AQARAAcKuhDQLQC7AQAAAA==.Snugwalnut:BAACNQAFFIELAAIPAAUKDhM0BwCZAQAPAAUKDhM0BwCZAQA1AAQKgSQAAg8ACQr0HtMhAKoCAA8ACQr0HtMhAKoCAAAA.',
So='Soejoedi:BAABNQAECoEbAAIBAAcK7RbQNAD3AQABAAcK7RbQNAD3AQAAAA==.',
St='Stitchzpls:BAAANQAECgIJAgAAAA==.',
Ta='Taintedrush:BAABNQAECoEfAAIdAAkKvxbaAgCsAgAdAAkKvxbaAgCsAgAAAA==.Tarhostamir:BAAANQADCgEIAQAAAA==.Taurup:BAAANQADCgYIEAABNQAECgkJIwAGAAwWAA==.Tazz:BAAANQAECgQICgAAAA==.',
Th='Thanossnap:BAAANQABCgQIBgABNQAECggIIgAEABoWAA==.Thaysinga:BAAANQAECgYIEQAAAA==.Thelandlord:BAAANQAECgIIAgAAAA==.Thunderblast:BAAANQAECgIIAwAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQADCgcIFAAAAA==.',
Tr='Trollor:BAAANQADCggIHQAAAA==.',
Ut='Utzon:BAAANQADCgQJBAABNQAECgcIGwABAO0WAA==.',
Va='Vaedan:BAAANQADCgQIBAAAAA==.Valkyrrie:BAAANQADCgUIBQABNQADCgYIDwADAAAAAA==.Vander:BAAANQAECgMIBgAAAA==.Vannder:BAAANQAECgEJAQABNQAECgMIBgADAAAAAA==.Vayper:BAABNQAECoElAAIMAAkKhx9DCAA4AwAMAAkKhx9DCAA4AwAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgkJJQAMAIcfAA==.',
Ve='Veins:BAAANQADCgEIAQAAAA==.',
['Vë']='Vënöm:BAAANQAECgEIAQABNQAECggIGwATAHocAA==.',
Wa='Waggo:BAAANQAECgYIEQAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgUIBQABNQADCgUIBgADAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAQAAAA==.',
Wi='Wildfire:BAACNQAFFIEHAAIeAAUKcBo7AADtAQAeAAUKcBo7AADtAQA1AAQKgSAAAh4ACQpSJkkAAM0DAB4ACQpSJkkAAM0DAAAA.',
Wo='Wolfhammer:BAAANQAECgcIEwAAAA==.',
Wr='Wreckadin:BAAANQAECgYJCgAAAA==.',
Ya='Yaztraz:BAABNQAECoEeAAMPAAgK9xwqLwBjAgAPAAgK9xwqLwBjAgACAAMKaAU2ywCVAAAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAcIFgAfAJsgAA==.',
Za='Zarturion:BAAANQAECgEIAQAAAA==.',
Zo='Zod:BAABNQAECoEjAAMGAAkKDBbDBQAzAgAGAAkKDBbDBQAzAgAVAAMKLQoMKQCXAAAAAA==.',
['Às']='Àsh:BAAANQAECgYICgAAAA==.',
['Év']='Évangeline:BAAANQADCgcIHgABNQAECgYIDgADAAAAAA==.',
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
