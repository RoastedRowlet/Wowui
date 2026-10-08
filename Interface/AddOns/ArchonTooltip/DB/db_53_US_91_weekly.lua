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

local lookup = {'Druid-Balance','Shaman-Elemental','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Rogue-Assassination','Druid-Restoration','Warlock-Destruction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Warlock-Affliction','Hunter-Survival','Warrior-Protection','DeathKnight-Blood',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-10-06',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
Am='Amadellaves:BAAANQADCgQIBAAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECoEjAAIBAAkKsBGvLwA+AgABAAkKsBGvLwA+AgAAAA==.Annde:BAABNQAECoEjAAICAAkKSRaDOABtAgACAAkKSRaDOABtAgAAAA==.Anyana:BAAANQADCgQIBAABNQAECgQJBAADAAAAAA==.',
Ar='Artemus:BAACNQAFFIEKAAMEAAUK1gP7BABDAQAEAAUK1gP7BABDAQAFAAMK8gIDDACgAAA1AAQKgTAAAwQACQqrHrkHAPsCAAQACQqrHrkHAPsCAAUABwqfDz0tAHwBAAE1AAQKAQgBAAMAAAAA.Arïel:BAAANQAECgQICAAAAA==.',
Be='Beeftoteeth:BAAANQAECgMIAwAAAA==.Ber:BAAANQAECgQICAABNQAECgkJKQAGAAwWAA==.Bexxy:BAAANQAECgEIAQAAAA==.',
Bi='Bibicrits:BAAANQABCggICgABNQAECgkJJwAHAFEcAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIDQAAAA==.',
Br='Broadfang:BAACNQAFFIEVAAMIAAYKyxZZCQCHAQAIAAUKNxdZCQCHAQAJAAIK1wuLHwCfAAA1AAQKgS8AAwgACQogIEcTALICAAgACQp/HkcTALICAAkAAQofJNwdAWoAAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICAAAAA==.Bullorly:BAACNQAFFIEGAAIKAAUKxhksBgCdAQAKAAUKxhksBgCdAQA1AAQKgSgAAgoACQqGJbgEAJ8DAAoACQqGJbgEAJ8DAAAA.',
Ca='Catirus:BAAANQADCgYIBwAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgkJKwAEAG0WAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAAANQAECgUIEwAAAA==.Clipe:BAAANQAECgcIBwAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQADCgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgIIAwAAAA==.',
Cr='Crispicrits:BAAANQAECgMIAwABNQAECgkJHAALAEEZAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECoEsAAIHAAkKTgslJQD+AQAHAAkKTgslJQD+AQAAAA==.Darenas:BAACNQAFFIEHAAIMAAUKDQhgCABPAQAMAAUKDQhgCABPAQA1AAQKgS8AAgwACQqtHe0NAPcCAAwACQqtHe0NAPcCAAAA.Darkwing:BAAANQABCgIIAQABNQAECgUIBwADAAAAAA==.',
De='Deathbooze:BAABNQAECoEjAAIKAAkKgSG5FAD8AgAKAAkKgSG5FAD8AgAAAA==.Deathmikee:BAABNQAECoEhAAIKAAkKDyGVEAAdAwAKAAkKDyGVEAAdAwAAAA==.Delilah:BAAANQAECgUIBwAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQADCgYIBgAAAA==.Derek:BAAANQAECgUIBwAAAA==.',
Dr='Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECoEmAAMNAAgKrx/oAwDmAgANAAgKrx/oAwDmAgAOAAIKKAokFQF1AAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECgcIBQAAAA==.',
El='Elderdorje:BAABNQAECoErAAMEAAkKbRaLDwBgAgAEAAkKbRaLDwBgAgAFAAcKvAVKPgDqAAAAAA==.Elixe:BAAANQADCggICAAAAA==.Elmersglue:BAAANQADCgEIAQAAAA==.Elondre:BAABNQAECoEoAAIPAAkK4BrqJACyAgAPAAkK4BrqJACyAgAAAA==.',
Ev='Evangeliné:BAAANQADCggICAABNQAECgcIGQALAKsMAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECoEnAAIHAAkKURzsDgDsAgAHAAkKURzsDgDsAgAAAA==.',
Fi='Firecracker:BAAANQAECgYIBwAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgIIAwABNQAECgkJKAAEAMcdAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQADCgQIBQABNQAECgkJKQAGAAwWAA==.Galatea:BAABNQAECoE3AAIQAAkKtB9sIAAqAwAQAAkKtB9sIAAqAwAAAA==.Galifen:BAABNQAECoEtAAIBAAkKcSW3AQDcAwABAAkKcSW3AQDcAwAAAA==.Gank:BAABNQAECoEgAAIRAAkK9iEuBACCAwARAAkK9iEuBACCAwAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICAAAAA==.',
Gi='Gilgahmesh:BAAANQAECgUIBwAAAA==.',
Gn='Gnomegrown:BAAANQAECgQICQAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAQAAAA==.',
Gy='Gyrux:BAAANQADCgUIBwAAAA==.',
Ha='Halyer:BAAANQADCgcIFgAAAA==.Hamalainen:BAAANQAECgYIEAABNQAECgkJKAAEAMcdAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQAECgMIAwAAAA==.',
He='Helioboops:BAAANQADCgcIEAAAAA==.',
Ho='Hobbz:BAACNQAFFIELAAIQAAUK5xHLCQCAAQAQAAUK5xHLCQCAAQA1AAQKgSIAAhAACQqiHuk8ALoCABAACQqiHuk8ALoCAAAA.',
Il='Illandros:BAAANQAECgUIDgAAAA==.',
In='Inspire:BAACNQAFFIELAAISAAQK1BcYCAA5AQASAAQK1BcYCAA5AQA1AAQKgSkAAhIACQpOIiMHADwDABIACQpOIiMHADwDAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgQIBQAAAA==.',
Ja='Jaína:BAAANQAECgIIAgABNQAECgUIDgADAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAECgkJKAAEAMcdAA==.',
Je='Jelina:BAAANQAECgIIAgAAAA==.',
Ji='Jiren:BAABNQAECoEoAAIEAAkKxx29CADnAgAEAAkKxx29CADnAgAAAA==.',
Jo='Johnson:BAAANQAECgcIEwAAAA==.Joran:BAAANQAECgUIDAAAAA==.',
Kr='Kro:BAAANQADCgEIAQAAAA==.',
Le='Leanea:BAAANQAECgIIAgAAAA==.',
Li='Liera:BAAANQAECgYICgAAAA==.Lightsac:BAAANQADCgYIBgAAAA==.Limmywinks:BAAANQADCgQIBAAAAA==.',
Ll='Lloydlei:BAAANQAECgcIDwAAAA==.',
Lu='Luminå:BAABNQAECoEbAAITAAgKehzLBQCsAgATAAgKehzLBQCsAgAAAA==.',
Ma='Maibisan:BAABNQAECoE+AAMUAAkKDCYgAQDoAwAUAAkKDCYgAQDoAwAHAAcKYyKVGAB9AgAAAA==.Malificent:BAAANQAECgMIAwAAAA==.',
Me='Metaevoker:BAABNQAECoEqAAIVAAkKTBjnCwCPAgAVAAkKTBjnCwCPAgAAAA==.',
Mo='Monawah:BAAANQAECgcIEgAAAA==.Mookong:BAAANQADCgYIBwAAAA==.Moonsliver:BAAANQAECgEIAwAAAA==.Moorf:BAAANQAECgQIBAAAAA==.Morff:BAABNQAECoEWAAIVAAcKdwlOHQBdAQAVAAcKdwlOHQBdAQAAAA==.Motleychew:BAAANQADCggIDwAAAA==.',
My='Mystwolf:BAAANQAECgUJBwAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgQICAADAAAAAA==.',
Ni='Nightember:BAAANQADCgIIAgABNQAECgkJKwAEAG0WAA==.Nightski:BAAANQAECgYIDQAAAA==.Nizzari:BAAANQAECgEIBAABNQAECgkJKQAGAAwWAA==.',
No='Nobuseri:BAAANQABCgcICwAAAA==.Nothalyer:BAABNQAECoEkAAIWAAgKMAguJACAAQAWAAgKMAguJACAAQAAAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgQICAAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Orwasitme:BAAANQAECgEIAQAAAA==.Orwasitmii:BAAANQADCgMJAwABNQAECgEIAQADAAAAAA==.',
Pa='Paladinii:BAAANQADCgQICgAAAA==.',
Ph='Philonk:BAAANQAECggIEwAAAA==.',
Pj='Pjxyo:BAAANQAECgYIEAAAAA==.',
Po='Polytots:BAACNQAFFIEMAAMPAAUKugxdCwBzAQAPAAUKugxdCwBzAQACAAIKhgbSIQCKAAA1AAQKgTEAAg8ACQqbJDcCALcDAA8ACQqbJDcCALcDAAAA.',
Ps='Psycototem:BAAANQAECgIIBAAAAA==.',
Ra='Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAAANQAECgQICQAAAA==.Recoiless:BAAANQADCgYIBgAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAAANQAECgEIAgABNQAECgkJKAAEAMcdAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ry='Ryzenther:BAAANQAECgIJAwAAAA==.',
['Rà']='Ràgnar:BAAANQAECgEIAQAAAA==.Ràgñar:BAAANQADCgYIEQAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgcIJQABADkYAA==.Scathclipe:BAABNQAECoElAAMRAAkK6BWxIwA9AgARAAkKKBKxIwA9AgAXAAgKLBUDCAAQAgAAAA==.',
Se='Seancodi:BAAANQAECgEIAQABNQAFFAYIFQAHAAQaAA==.Senomage:BAABNQAECoEaAAMYAAkKmiLJKwAtAwAYAAkKmiLJKwAtAwAZAAMK/R3CGgD0AAAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAABNQAECoEYAAIaAAgKRx3vCQCbAgAaAAgKRx3vCQCbAgAAAA==.Shazrast:BAAANQADCgQIBAAAAA==.Shockss:BAAANQAECgUICgAAAA==.',
Si='Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECoEgAAILAAkK1guIWADqAQALAAkK1guIWADqAQAAAA==.',
Sk='Skyepic:BAACNQAFFIEhAAMbAAcKUh2fAQCKAgAbAAcKUh2fAQCKAgAcAAEKTgXpDQBEAAA1AAQKgSYAAhsACQp+JqUAAOoDABsACQp+JqUAAOoDAAAA.Skylight:BAAANQAECggICwAAAA==.',
Sn='Sneakfu:BAABNQAECoEhAAMdAAcK8hdgGgDzAQAdAAcKNRZgGgDzAQARAAcKjRHUNQDEAQAAAA==.Snugwalnut:BAACNQAFFIEPAAIPAAUKIhO7CQCSAQAPAAUKIhO7CQCSAQA1AAQKgSYAAg8ACQr0HvcpAJkCAA8ACQr0HvcpAJkCAAAA.',
So='Soejoedi:BAABNQAECoElAAIBAAcKORhGNwAJAgABAAcKORhGNwAJAgAAAA==.Sorrowin:BAAANQABCgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBAAAAA==.',
Ta='Taintedrush:BAABNQAECoEkAAIeAAkKbRinAgDQAgAeAAkKbRinAgDQAgAAAA==.Tarhostamir:BAAANQAECgMIAwAAAA==.Taurup:BAAANQADCgYIEAABNQAECgkJKQAGAAwWAA==.Tazz:BAAANQAECgUIDwAAAA==.',
Th='Thaluus:BAAANQADCgIIAgAAAA==.Thanossnap:BAAANQABCgQIBgABNQAECgkJKwAEAG0WAA==.Thaysinga:BAABNQAECoEZAAIKAAcKLBRSVQCUAQAKAAcKLBRSVQCUAQAAAA==.Thelandlord:BAAANQAECgIIAgAAAA==.Thunderblast:BAAANQAECgIIBQAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQADCgcIFAAAAA==.',
Tr='Trollor:BAAANQADCggIHQAAAA==.',
Ut='Utzon:BAAANQADCgQJBAABNQAECgcIJQABADkYAA==.',
Va='Vaedan:BAAANQADCgUIBgAAAA==.Valkyrrie:BAAANQADCgUIBQABNQADCgcIFgADAAAAAA==.Vander:BAAANQAECgQICgAAAA==.Vannder:BAAANQAECgEIAgABNQAECgQICgADAAAAAA==.Vayper:BAABNQAECoEuAAIMAAkKhSKTBACBAwAMAAkKhSKTBACBAwAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgkJLgAMAIUiAA==.',
Ve='Veins:BAAANQADCgEIAQAAAA==.',
['Vë']='Vënöm:BAAANQAECgEIAQABNQAECggIGwATAHocAA==.',
Wa='Waggo:BAABNQAECoEbAAICAAcKBg4TdwCMAQACAAcKBg4TdwCMAQAAAA==.Waken:BAAANQAECgQIBAAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgUIBQABNQADCgUIBgADAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAQAAAA==.',
Wi='Wildfire:BAACNQAFFIEJAAIfAAYKYRgsAABPAgAfAAYKYRgsAABPAgA1AAQKgSMAAh8ACQpSJlsAAMYDAB8ACQpSJlsAAMYDAAAA.',
Wo='Wolfhammer:BAABNQAECoEfAAIgAAgKQBm+CwBRAgAgAAgKQBm+CwBRAgAAAA==.',
Wr='Wreckadin:BAAANQAECgcIEQAAAA==.',
Ya='Yaztraz:BAABNQAECoEgAAMPAAgK9xwiOABXAgAPAAgK9xwiOABXAgACAAMKaQXh5ACPAAAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAcIHQAhAKUhAA==.',
Za='Zarturion:BAAANQAECgEIAQAAAA==.',
Zo='Zod:BAABNQAECoEpAAMGAAkKDBbXBgAoAgAGAAkKDBbXBgAoAgAVAAQKEAtiKADLAAAAAA==.',
['Às']='Àsh:BAAANQAECggIEgAAAA==.',
['Év']='Évangeline:BAAANQAECgQIBAABNQAECgcIGQALAKsMAA==.',
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
