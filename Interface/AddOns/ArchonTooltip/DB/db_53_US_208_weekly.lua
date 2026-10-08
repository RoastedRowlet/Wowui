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

local lookup = {'Rogue-Assassination','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Hunter-Marksmanship','Rogue-Subtlety','Warrior-Arms','Warrior-Protection','Mage-Arcane','Priest-Holy','Priest-Shadow','Monk-Windwalker','Druid-Feral','Druid-Balance','Hunter-BeastMastery','DeathKnight-Frost','Paladin-Protection','DemonHunter-Devourer','Mage-Fire','Priest-Discipline','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Druid-Restoration','Shaman-Enhancement','Evoker-Augmentation','Warrior-Fury','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abor:BAAANQAECgcICgAAAA==.Abuela:BAABNQAECoEhAAIBAAkKDiATCQAwAwABAAkKDiATCQAwAwAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ae='Aegla:BAABNQAECoEeAAICAAgK5RbKPAAHAgACAAgK5RbKPAAHAgAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgkJIQADANwXAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFIEKAAIEAAMKKBfWDQDxAAAEAAMKKBfWDQDxAAA1AAQKgSkAAgQACQrTHFsLAN8CAAQACQrTHFsLAN8CAAAA.Alerath:BAAANQADCgYIDgAAAA==.Alliar:BAABNQAECoEjAAMFAAgK8R3qMwBqAgAFAAgK8R3qMwBqAgAGAAYKJAmulgA8AQAAAA==.Allynstraza:BAAANQAECgUICwAAAA==.',
Am='Amgems:BAAANQAECgQIBQAAAA==.Amordred:BAAANQAECgQIBwAAAA==.',
An='Anasterion:BAABNQAECoEVAAIHAAgKziBMUwByAgAHAAgKziBMUwByAgAAAA==.Andarus:BAAANQAECgUIDQABNQAECgkJJwAIAE4YAA==.Ankles:BAABNQAECoElAAMJAAgKriOODgApAwAJAAgKriOODgApAwACAAIKYAegvABQAAAAAA==.Ansley:BAAANQADCgUICAABNQAECgYIEgAKAAAAAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgEIAQABNQAECggIJgALADAgAA==.',
As='Ashli:BAAANQAECgYIEgAAAA==.',
At='Atlasbär:BAAANQAECgQIBAABNQADCgYIDwAKAAAAAA==.Atlasdark:BAAANQAECgYIDQABNQADCgYIDwAKAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQAECgIIAwAAAA==.Balthromaw:BAAANQAECgUIEAAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQAKAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgQIBAABNQAECgkJLQAMABsiAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belstab:BAABNQAECoEtAAMNAAgKpxBZGAAIAgANAAgK3w9ZGAAIAgABAAcKggp7PgCRAQAAAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAABNQAECoESAAMOAAgK/hECiADiAQAOAAgK/hECiADiAQAPAAEKAAAAAAAAAAAAAA==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgMJAwAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAUIDgAQAIkfAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECoEdAAMDAAkKZgyjVgD1AQADAAkKZgyjVgD1AQAHAAUKpQaiBAHfAAAAAA==.Bloodemongar:BAAANQAECgcIEwAAAA==.Bloodhoundss:BAAANQAECgcIDwAAAA==.Blössöm:BAAANQAECgQICgAAAA==.',
Bo='Bobdk:BAACNQAFFIEWAAMCAAYKoRjqAgD0AQACAAYKoRjqAgD0AQAJAAEK1AkSMQAlAAA1AAQKgSgAAgIACQrlIvcSAAoDAAIACQrlIvcSAAoDAAAA.Bomboklaat:BAAANQADCgEIAQAAAA==.Boomfrin:BAAANQAECgQIBAAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECoEjAAMRAAgKTxLtWQDlAQARAAgKTxLtWQDlAQASAAEKXAVsbQAzAAAAAA==.',
Br='Braegen:BAAANQAECgUICAABNQAECgkJJwAIAE4YAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQADCggICAAAAA==.Bruceleett:BAABNQAECoEaAAITAAcK4w21LgBuAQATAAcK4w21LgBuAQABNQADCgcIFQAKAAAAAA==.',
Bu='Buffmeister:BAAANQADCgUICQAAAA==.Bullioss:BAAANQAECgIIBAABNQAECggIEgAOAP4RAA==.',
['Bè']='Bètrayèr:BAAANQABCgMIAgAAAA==.',
['Bö']='Böbbyboucher:BAABNQAECoEZAAIGAAcKhh1SPABcAgAGAAcKhh1SPABcAgAAAA==.',
Ca='Cainn:BAAANQADCggIEwABNQAECggIHAAHAJ4VAA==.Calfurion:BAABNQAECoEVAAMUAAgK3h35DQD/AQAVAAcKNBncNgAMAgAUAAYKuR75DQD/AQAAAA==.Calvary:BAAANQAECggIAwABNQAECggIFQAUAN4dAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAABNQAECoEoAAIGAAgKeyHMHQD9AgAGAAgKeyHMHQD9AgAAAA==.',
Ce='Cessatio:BAAANQAECgQIDwAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAAANQAECgUIDwABNQAECgkJLgANAP0dAA==.Chrisbrewn:BAABNQAECoEiAAIOAAgKmBTDcQAeAgAOAAgKmBTDcQAeAgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAABNQAECoEtAAMMAAkKGyJvDQD3AgAMAAkKZyBvDQD3AgAWAAUKKhzkigDEAQAAAA==.',
Co='Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAAANQAECggIEwAAAA==.Condemnation:BAABNQAECoEnAAIRAAgKUROWVQD1AQARAAgKUROWVQD1AQAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQAKAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQAKAAAAAA==.Coriantumr:BAAANQADCgYIBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQABCgcJCwAAAA==.Curbstomped:BAAANQAECgcIEQAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgMIBAABNQAFFAYIDAAQADMgAA==.Darkvizzy:BAABNQAECoEkAAQJAAgKwBTyWABtAQAJAAcKCxDyWABtAQACAAUKoxYnbQA6AQAXAAIK3gqQfgBqAAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgUIBgAAAA==.Demiplo:BAABNQAECoEbAAIWAAgKzxIfZgAdAgAWAAgKzxIfZgAdAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQAKAAAAAA==.Denelak:BAAANQAFFAEIAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAAANQAECgMIAwABNQAECgkJIQABAA4gAA==.',
Di='Dirtycasual:BAAANQAECggICAABNQAECgkJIQABAA4gAA==.Discipline:BAABNQAECoEcAAIYAAgKIx58DgCPAgAYAAgKIx58DgCPAgAAAA==.',
Do='Doggo:BAAANQADCgUICwAAAA==.',
Dr='Dratr:BAAANQAECgYIEQAAAA==.Draxyl:BAABNQAECoEiAAMCAAkKiBSuUACoAQACAAkK9QuuUACoAQAJAAcKphJVUgCJAQAAAA==.Drekhan:BAAANQAECgQIBAABNQAECgkJJwAIAE4YAA==.Drham:BAABNQAECoEiAAIZAAgKyA0LKQDbAQAZAAgKyA0LKQDbAQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECggIHAATAJwTAA==.Drokos:BAAANQAECgUIBQABNQAECggIEgAOAP4RAA==.Drtree:BAAANQADCgcIBwAAAA==.',
Du='Dunhambones:BAABNQAECoEfAAICAAgK0CPCDQA1AwACAAgK0CPCDQA1AwAAAA==.Duo:BAABNQAECoEaAAIaAAgKvRTbAQBBAgAaAAgKvRTbAQBBAgABNQAECgcICgAKAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgUIBQAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECoEnAAQRAAkKww+4UgD/AQARAAkKww+4UgD/AQASAAIK6QGzawA2AAAbAAEK/gVUJgAyAAAAAA==.Elèctra:BAAANQAECgYIBQAAAA==.',
En='Enochs:BAAANQADCgIIAgAAAA==.Enyô:BAAANQADCgQIBAABNQAECgcIGQAGAIYdAA==.',
Er='Erada:BAAANQAECggIEgAAAA==.',
Ev='Evoklando:BAAANQADCgUICgABNQAECgkJLQAMABsiAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgcIDgAAAA==.Expectpriest:BAAANQABCgQIBAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECgcICgAKAAAAAA==.',
Fe='Felad:BAABNQAECoEaAAMcAAcKMSZJBwAEAwAcAAcKMSZJBwAEAwATAAEKyRYMWwBBAAABNQAECgQICAAKAAAAAA==.Felwen:BAAANQAECgcIDAAAAA==.',
Fh='Fhalanx:BAAANQABCggICAAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgcICgABNQABCgQIBAAKAAAAAA==.Flappyy:BAAANQAECgUIDQAAAA==.Flowdinstuna:BAAANQAECgUICgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECoEiAAIWAAgKPxB3cwD8AQAWAAgKPxB3cwD8AQAAAA==.Frierenpally:BAAANQADCgQJBAAAAA==.',
Fu='Furrybait:BAEANQAECgQIBQAAAA==.Furyiosa:BAAANQAECggIEQAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgAKAAAAAA==.Gaiseric:BAABNQAECoEeAAICAAgK+BhpPgD/AQACAAgK+BhpPgD/AQAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECoEbAAQdAAkKtR+9JQA8AQALAAcK2BySYQARAgAdAAQKCh+9JQA8AQAeAAEKtCTjJABHAAAAAA==.Getoverhere:BAAANQADCgcIBwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQABCgIIAgAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gotboned:BAAANQAECgcIDAABNQAECgkJHQAfAMYlAA==.Gotfleas:BAABNQAECoEdAAMfAAkKxiX0AADaAwAfAAkKxiX0AADaAwAUAAEKZAAAAAAAAAAAAA==.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECoEiAAIZAAcK6xhWJAAEAgAZAAcK6xhWJAAEAgAAAA==.Greyfax:BAAANQAECggIEgAAAA==.Grimthruul:BAABNQAECoEfAAIGAAgKpQg9eQCGAQAGAAgKpQg9eQCGAQAAAA==.Grommkar:BAABNQAECoEdAAIOAAgK8gu2kQDIAQAOAAgK8gu2kQDIAQAAAA==.Grumpig:BAAANQADCgQIBAAAAA==.',
Ha='Halucination:BAABNQAECoEaAAMSAAgKcg1ZKAC/AQASAAgKcg1ZKAC/AQARAAEKHgb04wAuAAAAAA==.Harthan:BAAANQAECgYICwAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayden:BAAANQAECgYIBgAAAA==.Hayleigh:BAAANQADCgUIBQAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwAKAAAAAA==.Helya:BAAANQADCgMIAwAAAA==.Henchman:BAAANQABCgQICAABNQAECggIEgAOAP4RAA==.Hetzák:BAABNQAECoEiAAIVAAgKCRDoPwDRAQAVAAgKCRDoPwDRAQAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBQAAAA==.Hintolisu:BAABNQAECoEkAAIUAAkKLR16BQD6AgAUAAkKLR16BQD6AgAAAA==.',
Ho='Hobbess:BAAANQAECgcIEAABNQAFFAcIHwAVACcjAA==.Holybaloney:BAABNQAECoEZAAMYAAgKyBw7EwBKAgAYAAcK9x47EwBKAgAHAAEKgw2jdQEzAAAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Hongis:BAAANQADCgUIBQAAAA==.Hoofinit:BAABNQAECoEYAAIOAAgKLyKVJQATAwAOAAgKLyKVJQATAwAAAA==.',
Hu='Huatarm:BAABNQAECoEgAAIPAAcKqRerEgDNAQAPAAcKqRerEgDNAQAAAA==.',
Ia='Iadygaga:BAAANQAECggIEgAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECggIHgACAOUWAA==.',
Ir='Ironspin:BAAANQAECgQIBQAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Ja='Jaark:BAACNQAFFIEGAAILAAMKxAdTHwDOAAALAAMKxAdTHwDOAAA1AAQKgSQAAwsACQqwHMMiAOECAAsACQqwHMMiAOECAB4AAQpHHhEhAFoAAAAA.Jabalru:BAAANQADCgMIAwAAAA==.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgEIAgABNQAECgYIEgAKAAAAAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jen:BAABNQAECoEoAAIRAAgKdhdKUgABAgARAAgKdhdKUgABAgAAAA==.',
Jo='Jocon:BAAANQADCggIGwAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECoEZAAMgAAYKYxmBDQC2AQAgAAYKYxmBDQC2AQAhAAQKfguqXQDUAAABNQAECggIIQAiAOwXAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECoEcAAIGAAgKERt4NgB3AgAGAAgKERt4NgB3AgABNQAECgQIBAAKAAAAAA==.Kanami:BAAANQAECgUICwAAAA==.Kaynyx:BAABNQAECoEkAAINAAgK8x7fCQDLAgANAAgK8x7fCQDLAgAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECoEcAAIHAAgKnhVqbQAoAgAHAAgKnhVqbQAoAgAAAA==.Kerb:BAAANQAECgYIDQAAAA==.Kery:BAAANQADCgMIAwAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECoEaAAMZAAgKmBrJIAAoAgAZAAgKkBfJIAAoAgAhAAQKzhbhVAAAAQAAAA==.',
Ki='Kikiko:BAAANQADCgUIBQAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECoEVAAIhAAcKJRjUMADyAQAhAAcKJRjUMADyAQAAAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQAHAM4gAA==.',
Kn='Knewtoomuch:BAAANQADCgcJBwAAAA==.',
Ko='Konjur:BAACNQAFFIEOAAIQAAUKiR81EADOAQAQAAUKiR81EADOAQA1AAQKgR4AAhAACQrCJBwqADIDABAACQrCJBwqADIDAAAA.',
Kr='Krelock:BAAANQAECgYJCgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgIIBAABNQAECggIKQAPAC0ZAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBAAAAA==.',
['Kä']='Kämo:BAAANQAECgEIAQABNQAECgQIBAAKAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgUICwABNQAECgkJKgAjAJAlAA==.Lakeyy:BAABNQAECoEqAAMjAAkKkCXjAQCrAwAjAAkKkCXjAQCrAwAVAAMKMx4PaAAAAQAAAA==.Lakeyys:BAAANQAECgEIAQABNQAECgkJKgAjAJAlAA==.Lanuor:BAAANQADCgEIAQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAABNQAECoEiAAMFAAkKAx49JQCxAgAFAAkKAx49JQCxAgAGAAMKiRhS0QDAAAAAAA==.',
Le='Lesaeria:BAAANQAECgUICQABNQAECggIIAAkAPUeAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgEIAQAAAA==.Lightsardine:BAAANQADCgEJAQAAAA==.Lilikoii:BAAANQAECgIIAgABNQAECgkJKgAjAJAlAA==.Liljit:BAAANQAECgEIAQABNQAECgkJIQADANwXAA==.Lilslaver:BAAANQAECgUICQAAAA==.Lisex:BAACNQAFFIELAAMXAAUK/w0hCAAgAQAXAAQK7w0hCAAgAQAJAAEKPQ5BLgArAAA1AAQKgSIAAxcACQqKITMQAPACABcACQqKITMQAPACAAkAAQoiFne1AD4AAAAA.Lithe:BAABNQAECoEpAAIHAAkKPxzcMgDgAgAHAAkKPxzcMgDgAgAAAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECoEjAAIHAAgKixLMggDxAQAHAAgKixLMggDxAQAAAA==.Logic:BAACNQAFFIEXAAQaAAYKyRQUAAAcAgAaAAYKKhMUAAAcAgAQAAYKNw/XDgDdAQAIAAIKyhtSBQCmAAA1AAQKgSkAAxAACQokIiBGAOgCABAACQr+ISBGAOgCABoAAwqjIOYEACYBAAAA.Lola:BAAANQAECgIIAgABNQAECgkJKgAjAJAlAA==.',
Lu='Lunaria:BAAANQAECgUIBgABNQAECgkJKgAjAJAlAA==.Lusty:BAABNQAECoEhAAIiAAgK7BfaDgBRAgAiAAgK7BfaDgBRAgAAAA==.Luxe:BAAANQAECgIIAgABNQAECgkJKgAjAJAlAA==.',
Ma='Macediin:BAAANQAECgYIEgAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECoEaAAIZAAkKVR0mFgCZAgAZAAkKVR0mFgCZAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECggIIwAMAPwZAA==.Magnolìa:BAAANQAECgQIBQAAAA==.Malthael:BAABNQAECoEdAAMCAAgKlhcVOQAbAgACAAgKGhcVOQAbAgAXAAcKwQuJRgBdAQAAAA==.Mamageek:BAAANQAECgcIEgAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECggIGwAGAFMfAA==.Manix:BAAANQAECgIIBQAAAA==.Mareo:BAAANQADCgUIBQAAAA==.Marksterique:BAABNQAECoEjAAIMAAgK/BndGwBZAgAMAAgK/BndGwBZAgAAAA==.Masochist:BAAANQADCgQIBAAAAA==.',
Me='Meeko:BAACNQAFFIEOAAIEAAcKuBbyAgBEAgAEAAcKuBbyAgBEAgA1AAQKgUAAAgQACQpyIqsFAEQDAAQACQpyIqsFAEQDAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgMIAwAAAA==.Metalbound:BAAANQAECgQICgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECoEYAAIkAAgK1yToBAA3AwAkAAgK1yToBAA3AwAAAA==.Misslobster:BAAANQAECgUIEAAAAA==.',
Mo='Mokoko:BAABNQAECoErAAIiAAkKphyhCgCqAgAiAAkKphyhCgCqAgAAAA==.Mokolock:BAAANQAECgUJCAABNQAECgkJKwAiAKYcAA==.Moomoo:BAABNQAECoElAAIVAAgKzh1zHwCzAgAVAAgKzh1zHwCzAgAAAA==.Moorlin:BAAANQADCggICAAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgkJKwAiAKYcAA==.',
My='Mysticphatty:BAAANQADCggJCAABNQAECgIIAgAKAAAAAA==.Myyst:BAAANQAECgMIAwAAAA==.',
Na='Nawtalhere:BAAANQADCgQIBAABNQAECggIIwAJALgjAA==.',
Ne='Necro:BAABNQAECoEdAAICAAgKfh2dJwB8AgACAAgKfh2dJwB8AgAAAA==.Necrota:BAABNQAECoEXAAMJAAgKiRxpKgBWAgAJAAgKBBtpKgBWAgACAAEKOiHHswBhAAABNQAFFAUIDgAQAIkfAA==.Nekronomicon:BAAANQADCggICgABNQAECggIJwARAFETAA==.Neuron:BAACNQAFFIEKAAMjAAUKAhIWBQCnAQAjAAUKAhIWBQCnAQAVAAQKVQZeEwD0AAA1AAQKgSAAAyMACQq3GjAPAMQCACMACQq3GjAPAMQCABUABgrKErhNAIABAAAA.Nexborn:BAAANQABCggJCAAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECoEgAAIfAAgKpx6LCAC/AgAfAAgKpx6LCAC/AgAAAA==.Nightflame:BAAANQAECgQJCAAAAA==.Ninjavc:BAAANQAECgUICwAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAAANQAECgEIAQAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQADCgcICQAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgMIAwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgQICgAAAA==.Oreyn:BAAANQAECgQIBgAAAA==.Organ:BAAANQAECgUIBgAAAA==.',
Pa='Paladín:BAABNQAECoEgAAIYAAgKqBU5GwDqAQAYAAgKqBU5GwDqAQAAAA==.Palazar:BAABNQAECoEmAAIHAAkK7h5HJwAOAwAHAAkK7h5HJwAOAwAAAA==.Paoka:BAAANQADCgQIBwABNQADCgcIEAAKAAAAAA==.Pargonz:BAABNQAECoEuAAMNAAkK/R3RBQAgAwANAAkK/R3RBQAgAwABAAIKlw54eAB1AAAAAA==.Patoko:BAABNQAECoEeAAIkAAgKRBvpCgCuAgAkAAgKRBvpCgCuAgAAAA==.Payn:BAAANQAECgQICAAAAA==.Paypay:BAABNQAECoEuAAIjAAkKBh0xCgAKAwAjAAkKBh0xCgAKAwAAAA==.',
Ph='Phalannx:BAAANQAECgIIAwAAAA==.Philipx:BAAANQAECgEIAQAAAA==.',
Pi='Piglittle:BAAANQAECgYICgAAAA==.Pindad:BAAANQAECgcIDAABNQAECggIEgAOAP4RAA==.',
Pl='Plzdispelme:BAABNQAECoEhAAMDAAkK3BdaKQCqAgADAAkK3BdaKQCqAgAHAAEKFg/7dAE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECoEZAAIdAAcKGRLTEwDJAQAdAAcKGRLTEwDJAQAAAA==.',
Pr='Priesticles:BAAANQAECgUIBQABNQADCgcIFQAKAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECgEIAQABNQAECgkJIQADANwXAA==.Ragingmonkx:BAABNQAECoEcAAITAAgKnBMVJADXAQATAAgKnBMVJADXAQAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Raventer:BAAANQAECggIDwAAAA==.Razdrood:BAAANQADCgUIAwABNQAECgQIBAAKAAAAAA==.Razlock:BAAANQAECgQIBAAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAAANQAECgUIEQAAAA==.',
Ro='Roguesucks:BAAANQADCgQIBQAAAA==.Rollos:BAABNQAECoEXAAILAAYKchslcQDjAQALAAYKchslcQDjAQAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAABNQAFFIEMAAIQAAYKMyAeBgA6AgAQAAYKMyAeBgA6AgAAAA==.Ryujinsimp:BAACNQAFFIEMAAMiAAUKKhcDBACJAQAiAAUKKhcDBACJAQAlAAQKYhUCBQAkAQA1AAQKgSIAAyUACQoJJVQDAOYCACIACQruIjIHAPoCACUACAqEJFQDAOYCAAE1AAUUBggMABAAMyAA.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwAKAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAMICAARAC8YAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECoEhAAIEAAgKbg3KHwC5AQAEAAgKbg3KHwC5AQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFIENAAQeAAUKrBGoAwCgAAAeAAIKmBGoAwCgAAALAAIKLhT8KQCVAAAdAAEK0AxoGgBOAAA1AAQKgawABB4ACQpfJu0AAGADAAsACAr/JX0KAGYDAB4ACAo/Je0AAGADAB0ABQq6JR4MACsCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAECgkJLQAMABsiAA==.Shangzha:BAABNQAECoEgAAIkAAgK9R7bCADZAgAkAAgK9R7bCADZAgAAAA==.Shareholder:BAEANQAECgUIBwABNQAFFAQIBwAQALkaAA==.Shiivera:BAABNQAECoEgAAIFAAgKKxxtNgBeAgAFAAgKKxxtNgBeAgAAAA==.Shimada:BAABNQAECoEbAAIWAAgKyByxOwCTAgAWAAgKyByxOwCTAgAAAA==.Shotsyll:BAAANQAFFAIIAwAAAA==.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECoEUAAMBAAcK0Rt2JwAiAgABAAcK+xh2JwAiAgANAAcK+BY0GgD1AQAAAA==.Skynomad:BAAANQAECgUIDQAAAA==.',
Sl='Slyde:BAABNQAECoEZAAICAAcKWCIjIQCkAgACAAcKWCIjIQCkAgAAAA==.',
Sm='Smalldk:BAAANQAFFAEIAwABNQAFFAUIEQAHALEVAA==.Smallrichard:BAAANQAECgEIAQABNQAECgYIEwAKAAAAAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAAANQAECgUIEAAAAA==.Smiteytash:BAAANQADCgUICAABNQAECggIHwAgABAbAA==.',
Sn='Snek:BAAANQAECgEIAwAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Solborne:BAAANQABCgQIBAAAAA==.Solfreid:BAAANQAECgQICQABNQAECgUIBQAKAAAAAA==.Sophism:BAAANQAECgYIBgABNQAFFAYIFwAaAMkUAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAJAHkmAA==.Soulfang:BAABNQAECoEYAAImAAcK4BN0DADPAQAmAAcK4BN0DADPAQAAAA==.Soulfox:BAAANQADCgQIBAABNQAECgYIBQAKAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQADCgUIBQABNQAECgkJGwANAEsWAA==.Sprocketrot:BAAANQAECgQIBQAAAA==.',
Sq='Squidmonk:BAABNQAECoEYAAIcAAkKqA0gGADLAQAcAAkKqA0gGADLAQAAAA==.',
St='Stardrive:BAABNQAECoEhAAIOAAkKrw5idgARAgAOAAkKrw5idgARAgAAAA==.Steelwhacka:BAAANQAECgYIEAAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFIEOAAITAAUKqBlmBQCUAQATAAUKqBlmBQCUAQA1AAQKgSEAAhMACQpjIL0QAL8CABMACQpjIL0QAL8CAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQAECggIBwAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQADCgcIBwABNQAECgUIDQAKAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgQICgAAAA==.Surtur:BAABNQAECoEtAAIOAAkKrxtEQACxAgAOAAkKrxtEQACxAgAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECggIIAAYAKgVAA==.',
Sy='Sygismund:BAAANQAECgYIDAAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAABNQAECoEiAAIWAAkKkh2NIAD4AgAWAAkKkh2NIAD4AgAAAA==.Taotien:BAAANQAECgcICQAAAA==.Tashbringer:BAAANQADCgYIBgABNQAECggIHwAgABAbAA==.',
Tc='Tchaik:BAABNQAECoEjAAMRAAgK0SLsHQDfAgARAAgK0SLsHQDfAgASAAEKlhK0awA2AAAAAA==.',
Te='Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgQICQAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQADCggICAAAAA==.Theios:BAAANQAECgYIDQABNQAECggIHgACAOUWAA==.Thickthang:BAABNQAECoEvAAMkAAgKfCXrAwBSAwAkAAgKfCXrAwBSAwAGAAQKAhXexADaAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECoEuAAIgAAkKdCKwAQByAwAgAAkKdCKwAQByAwAAAA==.Tinytea:BAABNQAECoEuAAMTAAkK/Rv3EQCuAgATAAkKYBv3EQCuAgAnAAEKUB77KABTAAAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgMIBgAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECoEZAAILAAcK7Aj0nQBrAQALAAcK7Aj0nQBrAQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAAKAAAAAA==.',
Tr='Trusinner:BAABNQAECoEbAAIOAAgK/Br+WQBhAgAOAAgK/Br+WQBhAgAAAA==.',
Ts='Tsusha:BAEANQAECgUICwAAAA==.',
Tu='Turkeyleg:BAAANQADCggJHwAAAA==.',
Tw='Twippy:BAABNQAECoEiAAIGAAkK1BU/PwBOAgAGAAkK1BU/PwBOAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgMJAwAKAAAAAA==.Tyriam:BAABNQAECoEeAAIHAAgK0h4vRwCZAgAHAAgK0h4vRwCZAgAAAA==.',
Ud='Udderchaos:BAAANQAECgEIAQAAAA==.',
Un='Unifey:BAAANQADCgYIBgAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAABNQAECoEqAAIiAAkKmh8OBwD9AgAiAAkKmh8OBwD9AgAAAA==.Verso:BAAANQAECgcIDgAAAA==.',
Vi='Viberaider:BAAANQAECgcIDgABNQAECgkJLQAJAGYiAA==.Vitalithry:BAABNQAECoEZAAIlAAcKMRj9BwD1AQAlAAcKMRj9BwD1AQAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQADCggICAABNQAECggIJAAJAMAUAA==.',
Vo='Voden:BAAANQABCgIIAwAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECoEqAAMXAAgKBBf8KQAWAgAXAAgKBBf8KQAWAgAJAAUK+gvFfwDUAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECoEbAAMGAAgKUx+XIQDlAgAGAAgKUx+XIQDlAgAFAAMKqxRmxQCzAAAAAA==.',
Wi='Wiiska:BAABNQAECoEmAAMSAAkK6hz9EQDBAgASAAkK6hz9EQDBAgARAAIKSAKP1gBSAAAAAA==.Windoelicker:BAAANQADCgcIFQAAAA==.',
Wo='Worgya:BAAANQADCgUIBQABNQAECgYIBQAKAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECggIEgAOAP4RAA==.Wrlccywhefr:BAABNQAECoEkAAQBAAkK6iHrHgBfAgABAAcKHR/rHgBfAgAoAAYKkx3LCADyAQANAAIKZB3JPQCgAAAAAA==.',
Wu='Wuggles:BAABNQAECoEeAAIjAAkKOReiFQB0AgAjAAkKOReiFQB0AgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECoEZAAIWAAcKchgqYAAtAgAWAAcKchgqYAAtAgAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAOAPwaAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgQIBgAAAA==.',
Ye='Yetil:BAAANQAECgYIDwAAAA==.',
Yn='Ynotraw:BAABNQAECoElAAIOAAkK8CCrGQBFAwAOAAkK8CCrGQBFAwAAAA==.',
Yo='Yourephired:BAAANQAECgUIEQAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQADCggICAABNQAECgkJJwAIAE4YAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgAGAAUfAA==.Zaydream:BAAANQADCgcIBwABNQAECggIHgAGAAUfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgAGAAUfAA==.Zayseer:BAABNQAECoEeAAIGAAgKBR9ELACpAgAGAAgKBR9ELACpAgAAAA==.',
Ze='Zello:BAAANQAECgUICwAAAA==.',
Zh='Zhengy:BAAANQAECgQIBwABNQAECgkJJwAIAE4YAA==.',
Zi='Ziggybeast:BAABNQAECoEdAAQVAAkKuh56LwA/AgAVAAcKqR96LwA/AgAjAAcKqhjMHgANAgAfAAEKaAw0UAAtAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQICgAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggIHgAGAAUfAA==.',
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
