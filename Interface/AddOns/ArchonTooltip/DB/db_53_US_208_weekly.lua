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

local lookup = {'Rogue-Assassination','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Mage-Frost','DeathKnight-Blood','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Rogue-Subtlety','Hunter-BeastMastery','Mage-Arcane','Warrior-Arms','Priest-Holy','Priest-Shadow','Monk-Windwalker','Druid-Feral','Druid-Balance','Paladin-Protection','DeathKnight-Frost','Shaman-Enhancement','DemonHunter-Devourer','Mage-Fire','Priest-Discipline','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Druid-Guardian','Warrior-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Druid-Restoration','Evoker-Augmentation','Warrior-Fury','Monk-Brewmaster','Rogue-Outlaw',}
local provider = {region='US',realm='Stormscale',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aanna:BAAANQADCgUIBQAAAA==.',
Ab='Abor:BAAANQAECgcIDQAAAA==.Abuela:BAABNQAECn8lAAIBAAkK1B4jDQAYAwABAAkK1B4jDQAYAwAAAA==.',
Ac='Achild:BAAANQADCgUIBQAAAA==.',
Ad='Adaela:BAAANQADCgIIAgABNQAECggIGwABAN8bAA==.',
Ae='Aegla:BAABNQAECn8lAAICAAgKQRfRPgAgAgACAAgKQRfRPgAgAgAAAA==.Aegrus:BAAANQADCgYIDAAAAA==.',
Ag='Aghlath:BAAANQAECgIIAgAAAA==.',
Ak='Akiko:BAAANQAECgYIDQABNQAECgkJIwADACYZAA==.',
Al='Alastina:BAAANQADCgQIBAAAAA==.Albesuri:BAAANQAECgIIAgAAAA==.Alcmenegems:BAAANQAECgQIBAAAAA==.Alcmeneinen:BAACNQAFFH8NAAIEAAMKKBdMEADjAAAEAAMKKBdMEADjAAA1AAQKfykAAgQACQrTHA8NANMCAAQACQrTHA8NANMCAAAA.Alerath:BAAANQADCgYIDwAAAA==.Alliar:BAABNQAECn8lAAMFAAkK8B2TKgC2AgAFAAkK8B2TKgC2AgAGAAYKPwlYqgA7AQAAAA==.Allynstraza:BAAANQAECgYIEQAAAA==.',
Am='Amgems:BAAANQAECgQIBQAAAA==.Amordred:BAAANQAECgQICgAAAA==.',
An='Anasterion:BAABNQAECn8VAAIHAAgK8CBmbABVAgAHAAgK8CBmbABVAgAAAA==.Andarus:BAAANQAECgUIEQABNQAECgkJLwAIAC8aAA==.Ankles:BAABNQAECn8nAAMJAAkKfiO7BwB/AwAJAAkKfiO7BwB/AwACAAIK+gkIzQBPAAAAAA==.Ansley:BAAANQADCgUICAABNQAECggIGwABAN8bAA==.',
Ar='Arnaldo:BAAANQADCggIDwAAAA==.Artimisia:BAAANQAECgEIAQABNQAECggILQAKAHYfAA==.',
As='Ashli:BAABNQAECn8bAAIBAAgK3xvtFwC5AgABAAgK3xvtFwC5AgAAAA==.',
At='Atlasbär:BAAANQAECgQIBAABNQADCgYIDwALAAAAAA==.Atlasdark:BAAANQAECgYIDQABNQADCgYIDwALAAAAAA==.Atlasfallen:BAAANQADCgYIDwAAAA==.',
Ba='Balrock:BAAANQAECgIIAwAAAA==.Balthromaw:BAABNQAECn8aAAIKAAYKjRG/oACPAQAKAAYKjRG/oACPAQAAAA==.',
Be='Beacon:BAAANQADCgYIBgAAAA==.Beardsham:BAAANQADCgYIBgABNQAECgQIBQALAAAAAA==.Beardwaffle:BAAANQAECgQIBQAAAA==.Bearlando:BAAANQAECgQIBAABNQAFFAMIBQAMAIoKAA==.Bearnabus:BAAANQADCgEIAQAAAA==.Beecheeks:BAAANQAECgUIDgAAAA==.Belstab:BAABNQAECn8tAAMNAAgK/g+AGwD3AQANAAgKhw+AGwD3AQABAAcKcwnATACHAQABNQAFFAQIBwACAD4DAA==.Bethevangel:BAAANQADCgEIAQAAAA==.Betrayer:BAAANQAECgcIEAABNQAECgkJFwAOAD8iAQ==.',
Bg='Bgbalkoth:BAAANQADCgYIDAAAAA==.',
Bi='Bifurthegrey:BAAANQAECgQIAwAAAA==.Bigblammy:BAAANQADCggICAABNQAFFAYIEwAPAMobAA==.Biophage:BAAANQAECgQICAAAAA==.Birdman:BAAANQAECgIIAgAAAA==.',
Bl='Blackfreid:BAAANQAECgUIBQABNQAECgYIDgALAAAAAA==.Blaxdevoured:BAAANQADCgQIBAAAAA==.Blinkss:BAAANQAECgYIBgAAAA==.Bloodavenger:BAABNQAECn8dAAMDAAkKZgxHZQDlAQADAAkKZgxHZQDlAQAHAAUK9waqJgHZAAAAAA==.Bloodemongar:BAAANQAECgcIEwAAAA==.Bloodhoundss:BAABNQAECn8ZAAIQAAgKvBNsjwDxAQAQAAgKvBNsjwDxAQAAAA==.Blössöm:BAAANQAECgQICgAAAA==.',
Bo='Bobdk:BAACNQAFFH8cAAMCAAYKlR3qAwD0AQACAAYKlR3qAwD0AQAJAAEKAAAfOAAgAAA1AAQKfyoAAgIACQo7JPgVAAkDAAIACQo7JPgVAAkDAAAA.Bomboklaat:BAAANQADCgEIAQAAAA==.Boomfrin:BAAANQAECgQIBwAAAA==.Boomshield:BAAANQAECgUJBAAAAA==.Boxbeater:BAABNQAECn8lAAMRAAkK6BD7VwAWAgARAAkK6BD7VwAWAgASAAEKXAUEegAxAAAAAA==.',
Br='Braegen:BAAANQAECgYIDgABNQAECgkJLwAIAC8aAA==.Brewslee:BAAANQADCggICAAAAA==.Brewsleê:BAAANQAECgQIBAAAAA==.Bruceleett:BAABNQAECn8hAAITAAcKxhOiLACwAQATAAcKxhOiLACwAQABNQADCgcIFQALAAAAAA==.',
Bu='Buffmeister:BAAANQADCgUICQAAAA==.Bullioss:BAAANQAECgIIBgABNQAECgkJFwAOAD8iAA==.',
['Bè']='Bètrayèr:BAAANQABCgMIAgAAAA==.',
['Bö']='Böbbyboucher:BAABNQAECn8eAAIGAAcKhR7XPgB3AgAGAAcKhR7XPgB3AgAAAA==.',
Ca='Cainn:BAAANQADCggIEwABNQAECggIIAAHAOMTAA==.Calfurion:BAABNQAECn8VAAMUAAgKqB3LEAD4AQAVAAcKShyXPgABAgAUAAYK1B7LEAD4AQAAAA==.Calvary:BAAANQAECggICwABNQAECggIFQAUAKgdAA==.Capncrunch:BAAANQADCgUIBQAAAA==.Cazleah:BAABNQAECn8pAAIGAAkKuh+xGAAzAwAGAAkKuh+xGAAzAwAAAA==.',
Ce='Cessatio:BAAANQAECgQIEwAAAA==.',
Ch='Chattanooga:BAAANQAECgYIDwAAAA==.Chemotherapy:BAABNQAECn8YAAIHAAgKAxlfaQBcAgAHAAgKAxlfaQBcAgABNQAECgkJNAANAEYfAA==.Chrisbrewn:BAABNQAECn8kAAIQAAkKzhO3cAA+AgAQAAkKzhO3cAA+AgAAAA==.Chunkymonkie:BAAANQAECgIIAgAAAA==.',
Cl='Clevelandoe:BAACNQAFFH8FAAIMAAMKigqTGAC5AAAMAAMKigqTGAC5AAA1AAQKfzAAAwwACQpUIygOAP0CAAwACQpSISgOAP0CAA4ABQocG3qlALYBAAAA.',
Co='Cocobear:BAAANQAECgEIAQAAAA==.Coeurdeleon:BAABNQAECn8ZAAMHAAkKvxTuggAeAgAHAAkKvxTuggAeAgAWAAEKAAB1ZQBIAAAAAA==.Condemnation:BAABNQAECn8tAAIRAAkKExbpNwCGAgARAAkKExbpNwCGAgAAAA==.Corban:BAAANQADCggIDQAAAA==.Corebahn:BAAANQADCgYICgABNQADCggIDQALAAAAAA==.Corebin:BAAANQADCgcIEQABNQADCggIDQALAAAAAA==.Coriantumr:BAAANQADCgYIBgAAAA==.',
Cr='Creampuff:BAAANQABCggIDAAAAA==.Critneyfear:BAAANQAECgQIBQAAAA==.Crossctrl:BAAANQAECgEIAQAAAA==.',
Cu='Curbazar:BAAANQABCgcJCwAAAA==.Curbstomped:BAABNQAECn8ZAAMOAAgKzhWLbQA0AgAOAAgKzhWLbQA0AgAMAAMK7gMEbQB2AAAAAA==.',
Cy='Cyllex:BAAANQAECgEIAgAAAA==.',
Da='Darbins:BAAANQAECgMIBAABNQAFFAcIEwAPABQiAA==.Darkvizzy:BAABNQAECn8mAAQJAAgKkBVYYwBiAQAJAAcKag9YYwBiAQACAAUK7Bd+dgA7AQAXAAIK3gp5lABlAAAAAA==.Daymån:BAAANQAECgIIAgAAAA==.',
De='Deathreaper:BAAANQAECgIIAgAAAA==.Delix:BAAANQAECgUIBgAAAA==.Demiplo:BAABNQAECn8gAAIOAAgK6xKJeAAaAgAOAAgK6xKJeAAaAgAAAA==.Demonbeard:BAAANQADCggIDQABNQAECgQIBQALAAAAAA==.Denelak:BAABNQAECn8fAAMOAAkKQB6aEQBaAwAOAAkKfByaEQBaAwAMAAkKcxfGGACPAgAAAA==.Denethorian:BAAANQABCgQIBgAAAA==.',
Dg='Dgaf:BAAANQAECggICwABNQAECgkJJQABANQeAA==.',
Di='Dirtycasual:BAAANQAECggICQABNQAECgkJJQABANQeAA==.Discipline:BAABNQAECn8jAAMWAAgKyRxhEgB5AgAWAAgKyRxhEgB5AgAHAAcKCxW6lgDxAQAAAA==.',
Do='Doggo:BAAANQAECgEIAQAAAA==.Dotsurdead:BAAANQAECggICAAAAA==.',
Dr='Dratr:BAABNQAECn8YAAIYAAgKOwxaFwDuAQAYAAgKOwxaFwDuAQAAAA==.Draxyl:BAABNQAECn8nAAMCAAkKNBY/SgDpAQACAAkKJA8/SgDpAQAJAAcKohRqXAB+AQAAAA==.Drekhan:BAAANQAECgQIBAABNQAECgkJLwAIAC8aAA==.Drham:BAABNQAECn8kAAIZAAkKJQ62KAD6AQAZAAkKJQ62KAD6AQAAAA==.Drogbar:BAAANQAECgEIAQABNQAECgkJIwATAO4VAA==.Drokos:BAAANQAECgUIBgABNQAECgkJFwAOAD8iAA==.Drtree:BAAANQADCgcIBwAAAA==.Druni:BAAANQADCgEIAQAAAA==.',
Du='Dunhambones:BAABNQAECn8lAAICAAgKbyP5EAAuAwACAAgKbyP5EAAuAwAAAA==.Duo:BAABNQAECn8jAAIaAAkKxRPMAQBwAgAaAAkKxRPMAQBwAgABNQAECgcIDQALAAAAAA==.',
['Dä']='Därkside:BAAANQADCgYIBwAAAA==.',
Eg='Eggwuhh:BAAANQAECgYIDwAAAA==.',
El='Electora:BAAANQAECgYJBgAAAA==.Eleidon:BAAANQAECgUIBQAAAA==.Elminstr:BAAANQADCgYIBgAAAA==.Elowynn:BAABNQAECn8qAAQRAAkKww+IYgD1AQARAAkKww+IYgD1AQASAAIK6QH/dwA1AAAbAAEK/gWgKAAyAAAAAA==.Elèctra:BAAANQAECgcICwAAAA==.',
En='Engraver:BAAANQADCggICAAAAA==.Enochs:BAAANQADCgIIAgAAAA==.Enyô:BAAANQADCgQIBAABNQAECgcIHgAGAIUeAA==.',
Er='Erada:BAABNQAECn8dAAMIAAkKhRV/DgDAAQAPAAgKjRUJigBrAgAIAAYK6hh/DgDAAQAAAA==.',
Ev='Evesong:BAAANQABCgYIBwAAAA==.Evoklando:BAAANQADCgUICgABNQAFFAMIBQAMAIoKAA==.',
Ex='Exinquisitor:BAAANQADCgIIAgAAAA==.Exorcism:BAAANQADCgcIDAAAAA==.Extrava:BAAANQADCgIIAgAAAA==.',
Ez='Ezith:BAAANQAECgMIAwABNQAECgcIDQALAAAAAA==.',
Fe='Felad:BAABNQAECn8gAAMcAAcKMSbkCAD7AgAcAAcKMSbkCAD7AgATAAEKAADZZQBAAAABNQAECgYICQALAAAAAA==.Felwen:BAAANQAFFAEIAQAAAA==.',
Fh='Fhalanx:BAAANQABCggICAAAAA==.',
Fi='Fireblast:BAAANQADCggIGAAAAA==.',
Fl='Flamingfists:BAAANQAECgUIEQAAAA==.Flapp:BAAANQAECgcIDgABNQAECgUIEQALAAAAAA==.Flappyy:BAAANQAECgUIEQAAAA==.Flowdinstuna:BAAANQAECggIEgAAAA==.Flynnrider:BAAANQADCggICAAAAA==.',
Fm='Fmliplaydots:BAAANQADCgMIAwAAAA==.',
Fr='Framistina:BAABNQAECn8qAAIOAAkKbRq4QwCeAgAOAAkKbRq4QwCeAgAAAA==.Frierenpally:BAAANQADCgQIBAAAAA==.',
Fu='Furrybait:BAAANQAECgQIBwAAAA==.Furyiosa:BAABNQAECn8XAAIQAAkKExW1aQBQAgAQAAkKExW1aQBQAgAAAA==.',
Ga='Gahiji:BAAANQADCgcIDQABNQAECgQJBgALAAAAAA==.Gaiseric:BAABNQAECn8hAAICAAgK0hoxPwAeAgACAAgK0hoxPwAeAgAAAA==.Gamago:BAAANQAECggIBAAAAA==.Garrosh:BAAANQAECggIAQAAAA==.',
Ge='Geraniho:BAABNQAECn8cAAQdAAkKix4MKAA3AQAKAAcKWBqgbwAMAgAdAAQKCh8MKAA3AQAeAAEKAABfKQBFAAAAAA==.Getoverhere:BAAANQADCggICwAAAA==.',
Gi='Girltank:BAAANQAECgIIBAAAAA==.',
Gn='Gnarlak:BAAANQAECgEIAQAAAA==.',
Go='Goldenhero:BAAANQAECgIIAgAAAA==.Gotboned:BAAANQAECgcIDAABNQAFFAYIBgAfAGMeAA==.Gotfleas:BAACNQAFFH8GAAIfAAYKYx6QAAA6AgAfAAYKYx6QAAA6AgA1AAQKfyAAAx8ACQr1JSABANsDAB8ACQr1JSABANsDABQAAQpkAAAAAAAAAAAA.',
Gr='Graxis:BAAANQABCgIIBAAAAA==.Grendaldh:BAABNQAECn8mAAIZAAcKmhnKKAD6AQAZAAcKmhnKKAD6AQAAAA==.Greyfax:BAABNQAECn8aAAIDAAkKSx3iGAAUAwADAAkKSx3iGAAUAwAAAA==.Grimthruul:BAABNQAECn8iAAIGAAgK2QcgjACCAQAGAAgK2QcgjACCAQAAAA==.Grommkar:BAABNQAECn8jAAIQAAkKDg4BjwDyAQAQAAkKDg4BjwDyAQAAAA==.Grumpig:BAAANQADCgQICAAAAA==.Grèggory:BAAANQAECgIIAgAAAA==.',
Gu='Gusari:BAEANQAECgEIAQABNQAECggIDAALAAAAAA==.',
Ha='Hadmeathello:BAAANQAECgEIAQAAAA==.Halucination:BAABNQAECn8dAAMSAAkK7wwKJAAOAgASAAkK7wwKJAAOAgARAAIKlwQe6gBcAAAAAA==.Harthan:BAAANQAECgYIEQAAAA==.Hatchep:BAAANQADCgYIBgAAAA==.Hayden:BAAANQAECggIDgAAAA==.Hayleigh:BAAANQADCgYIBwAAAA==.',
He='Healsham:BAAANQADCgcIBwABNQADCgcIBwALAAAAAA==.Helya:BAAANQADCgMIBAAAAA==.Henchman:BAAANQABCgQICAABNQAECgkJFwAOAD8iAA==.Hetzák:BAABNQAECn8qAAIVAAkKsxLSOQAfAgAVAAkKsxLSOQAfAgAAAA==.',
Hi='Hikarisan:BAAANQAECgUIBQAAAA==.Hintolisu:BAABNQAECn8qAAIUAAkKAx0iBgAMAwAUAAkKAx0iBgAMAwAAAA==.',
Ho='Hobbess:BAAANQAECgcIEAABNQAFFAgIJgAVAO8lAA==.Holybaloney:BAABNQAECn8bAAMWAAkKFx+NEQCEAgAWAAgKFx+NEQCEAgAHAAEKAADDmgE3AAAAAA==.Holycrit:BAAANQADCgMIAwAAAA==.Holysmite:BAAANQAECgcIEAAAAA==.Holyvaj:BAAANQAECgIIAgABNQAECgQIBAALAAAAAA==.Hongis:BAAANQAECgEIAQAAAA==.Hoofinit:BAABNQAECn8eAAIQAAgKsyGHKQASAwAQAAgKsyGHKQASAwAAAA==.',
Hu='Huatarm:BAABNQAECn8oAAIgAAgKThvdDABiAgAgAAgKThvdDABiAgAAAA==.',
Ia='Iadygaga:BAAANQAECggIEgAAAA==.',
Ic='Iceblossom:BAAANQAECgQIBAAAAA==.Icenips:BAAANQAECgUICwAAAA==.',
Im='Immunè:BAAANQAECgIIAgABNQAECggIJQACAEEXAA==.',
Ir='Ironspin:BAAANQAECgQIBgAAAA==.Irønwølf:BAAANQABCgIIAgAAAA==.',
Ja='Jaark:BAACNQAFFH8JAAIKAAQK4A3AGgAjAQAKAAQK4A3AGgAjAQA1AAQKfycAAwoACQqYHj4lAOwCAAoACQqYHj4lAOwCAB4AAQoAAOgkAFkAAAAA.Jabalru:BAAANQADCgMIAwAAAA==.Jake:BAAANQAECgYIDQAAAA==.Jaliyah:BAAANQAECgIIBAABNQAECggIGwABAN8bAA==.Jasparr:BAAANQABCgQIBAAAAA==.Jaymaldy:BAAANQADCgMIAwAAAA==.',
Je='Jehanne:BAAANQADCgQIBQAAAA==.Jen:BAABNQAECn8tAAIRAAkKSRbSTQA4AgARAAkKSRbSTQA4AgAAAA==.',
Ju='Jugulator:BAAANQADCggIEAAAAA==.Jumpey:BAABNQAECn8ZAAMhAAYKnhgnEACrAQAhAAYKnhgnEACrAQAiAAQKYwtUaADSAAABNQAECggIIQAjAC4YAA==.',
Ka='Kalio:BAAANQAECgUIBQAAAA==.Kamo:BAABNQAECn8fAAIGAAkKDRqZMAC2AgAGAAkKDRqZMAC2AgABNQAECgQIBgALAAAAAA==.Kanami:BAAANQAECgYIEQAAAA==.Kaynyx:BAABNQAECn8sAAINAAkKzx7SBgAQAwANAAkKzx7SBgAQAwAAAA==.Kazimer:BAAANQAECgEIAQAAAA==.',
Ke='Kedrik:BAABNQAECn8gAAIHAAgK4xM6egAyAgAHAAgK4xM6egAyAgAAAA==.Kenzie:BAAANQAECgMIAwAAAA==.Kerb:BAAANQAECgYIEwAAAA==.Kery:BAAANQADCgMIAwAAAA==.Kethalin:BAAANQADCgQIBAAAAA==.Keyalimath:BAABNQAECn8aAAMZAAgK7hheJwAGAgAZAAgK4xReJwAGAgAiAAQKtBf5XgD8AAAAAA==.',
Ki='Kikiko:BAAANQADCgUIBQAAAA==.Killinflak:BAAANQAECgQIBgAAAA==.Kissyboots:BAABNQAECn8WAAIiAAgKDxccMQAcAgAiAAgKDxccMQAcAgAAAA==.Kiyo:BAAANQAECgUICwABNQAECggIFQAHAPAgAA==.',
Kl='Klaris:BAAANQAECgQIBAAAAA==.',
Kn='Knewtoomuch:BAAANQADCgcIBwAAAA==.',
Ko='Konjur:BAACNQAFFH8TAAIPAAYKyhvfCgAeAgAPAAYKyhvfCgAeAgA1AAQKfx4AAg8ACQrQJI03ABkDAA8ACQrQJI03ABkDAAAA.',
Kr='Krelock:BAAANQAECgYICgAAAA==.Krog:BAAANQADCgYICAAAAA==.Krymzendeath:BAAANQAECgIIBAABNQAECgkJOAAgADobAA==.',
Ku='Kuya:BAAANQADCggICAAAAA==.',
Ky='Kytheon:BAAANQADCgIIAgAAAA==.',
['Kâ']='Kâmø:BAAANQAECgQIBgAAAA==.',
['Kä']='Kämo:BAAANQAECgIIAwABNQAECgQIBgALAAAAAA==.',
La='Laelada:BAAANQADCgUIBQAAAA==.Lagertha:BAAANQADCgcIBwAAAA==.Lakey:BAAANQAECgUICwABNQAFFAQICAAkACciAA==.Lakeyy:BAACNQAFFH8IAAIkAAQKJyIPBwCKAQAkAAQKJyIPBwCKAQA1AAQKfy0AAyQACQqQJYQCAKQDACQACQqQJYQCAKQDABUAAwqdHrNyAPsAAAAA.Lakeyys:BAAANQAECgEIAQABNQAFFAQICAAkACciAA==.Lanuor:BAAANQADCgEIAQAAAA==.Lavagobrr:BAAANQAECgQIBAAAAA==.Lawrence:BAACNQAFFH8IAAIFAAQKDgo9FAANAQAFAAQKDgo9FAANAQA1AAQKfyUAAwUACQoUHjstAKsCAAUACQoUHjstAKsCAAYAAwo9GCjpAL8AAAAA.',
Le='Lesaeria:BAAANQAECgcIEQABNQAECgkJJQAYAOUfAA==.Leykeirra:BAAANQADCgYIBgAAAA==.',
Li='Lideria:BAAANQADCgUIBQAAAA==.Lightquanta:BAAANQAECgEIAQAAAA==.Lightsardine:BAAANQADCgIIAgAAAA==.Lilikoii:BAAANQAECgIIAgABNQAFFAQICAAkACciAA==.Liljit:BAAANQAECgEIAgABNQAECgkJIwADACYZAA==.Lilslaver:BAAANQAECgYIDwAAAA==.Lisex:BAACNQAFFH8LAAMXAAUKTwx6DAAPAQAXAAQKTwx6DAAPAQAJAAEKAAC2NAApAAA1AAQKfyIAAxcACQpNIcYXAMkCABcACQpNIcYXAMkCAAkAAQoiFjbEADwAAAAA.Lithe:BAABNQAECn8wAAIHAAkKBx6YKwAXAwAHAAkKBx6YKwAXAwABNQAECgkJOwAGAIkgAA==.',
Lo='Lockjhaw:BAAANQAFFAEIAQAAAA==.Locklear:BAABNQAECn8qAAIHAAgKxBR9mQDrAQAHAAgKxBR9mQDrAQAAAA==.Logic:BAACNQAFFH8eAAQaAAcK1RYZAAAKAgAaAAYK8hYZAAAKAgAPAAYKYhOUEgDdAQAIAAMKIRjeAgD3AAA1AAQKfysAAw8ACQr0Ii1ZAM4CAA8ACQrDIi1ZAM4CABoAAwqjIJUFAB8BAAAA.Lola:BAAANQAECgMIAgABNQAFFAQICAAkACciAA==.Lolbrez:BAAANQAECggIBAAAAA==.',
Lu='Lunaria:BAAANQAECgUIBgABNQAFFAQICAAkACciAA==.Lusty:BAABNQAECn8hAAIjAAgKLhjgEABGAgAjAAgKLhjgEABGAgAAAA==.Luxe:BAAANQAECgIIAgABNQAFFAQICAAkACciAA==.',
Ma='Macediin:BAABNQAECn8VAAICAAcK6hnaTADeAQACAAcK6hnaTADeAQAAAA==.Mackenna:BAAANQADCgcJBwAAAA==.Madderhunter:BAABNQAECn8aAAIZAAkKiBw/HABxAgAZAAkKiBw/HABxAgAAAA==.Magesterique:BAAANQAECgEIAQABNQAECgkJJQAMAM8ZAA==.Magnolìa:BAAANQAECgUICQAAAA==.Malthael:BAABNQAECn8lAAMCAAgKZRjyPAApAgACAAgKvxfyPAApAgAXAAcKwA+aUQBjAQAAAA==.Mamageek:BAAANQAECggIEwAAAA==.Mami:BAAANQAECgEIAQAAAA==.Manhorde:BAAANQAECgQICwABNQAECggIIgAGANseAA==.Manix:BAAANQAECgIIBQAAAA==.Mareo:BAAANQAECgIIAgAAAA==.Marksterique:BAABNQAECn8lAAIMAAkKzxlCGQCKAgAMAAkKzxlCGQCKAgAAAA==.Masochist:BAAANQAECgIIAgAAAA==.',
Me='Meeko:BAACNQAFFH8PAAIEAAcKuBYHBAA5AgAEAAcKuBYHBAA5AgA1AAQKf0cAAgQACQqtIv8FAEkDAAQACQqtIv8FAEkDAAAA.Meleeman:BAAANQADCgIIAgAAAA==.Meliadus:BAAANQADCgcIDgAAAA==.Mereoleona:BAAANQAECgMIAwAAAA==.Metalbound:BAAANQAECgQICgAAAA==.Metalmagus:BAAANQADCgcIBwAAAA==.',
Mi='Mikyla:BAAANQADCgUIBQAAAA==.Millican:BAABNQAECn8bAAIYAAgKqSSJBgAbAwAYAAgKqSSJBgAbAwAAAA==.Misslobster:BAAANQAECgYIEwAAAA==.',
Mo='Mokoko:BAABNQAECn8uAAIjAAkKbBwYCwC0AgAjAAkKbBwYCwC0AgAAAA==.Mokolock:BAAANQAECgUICAABNQAECgkJLgAjAGwcAA==.Moomoo:BAABNQAECn8oAAIVAAkKFh40GQD8AgAVAAkKFh40GQD8AgAAAA==.Moorlin:BAAANQAECgUIBQAAAA==.Motwoko:BAAANQAECgIIAgABNQAECgkJLgAjAGwcAA==.',
My='Myka:BAAANQAECgEIAQABNQAECgIIBQALAAAAAA==.Mysticphatty:BAAANQADCggJCAABNQAECgIIAgALAAAAAA==.Myyst:BAAANQAECgMIAwAAAA==.',
Na='Nawtalhere:BAAANQADCgQIBAABNQAECgkJKwAJAJUjAA==.',
Ne='Necro:BAABNQAECn8fAAICAAkKix2CIwCzAgACAAkKix2CIwCzAgAAAA==.Necrota:BAABNQAECn8YAAMJAAgKvxyCMgBCAgAJAAgKAxuCMgBCAgACAAEKOiGawgBiAAABNQAFFAYIEwAPAMobAA==.Nekronomicon:BAAANQADCggICgABNQAECgkJLQARABMWAA==.Neuron:BAACNQAFFH8PAAMkAAYKYBemAwAAAgAkAAYKYBemAwAAAgAVAAQKUAcPFwDyAAA1AAQKfyEAAyQACQoVG8URAMACACQACQoVG8URAMACABUABgpGEHlWAHkBAAAA.Nexdorei:BAAANQABCggICAAAAA==.Nexxos:BAAANQAECgIIAgAAAA==.',
Ni='Nickadeath:BAAANQADCgUICAAAAA==.Nigdruu:BAABNQAECn8nAAIfAAgK2R+nCADsAgAfAAgK2R+nCADsAgAAAA==.Nightflame:BAAANQAECgQJCAAAAA==.Ninjavc:BAAANQAECgYIEQAAAA==.',
No='Noelle:BAAANQAECgQJBgAAAA==.Noora:BAAANQAECgUIBQAAAA==.Notham:BAAANQAECgUIBwAAAA==.Notlucid:BAAANQAECgEIAQAAAA==.',
Og='Ogran:BAAANQADCgUIBwAAAA==.',
Ol='Olpheux:BAAANQAECgMIAwAAAA==.',
On='Onayro:BAAANQABCgIIAgAAAA==.',
Op='Oprahwinfrey:BAAANQADCggIBwAAAA==.',
Or='Oralys:BAAANQAECgQICgAAAA==.Oreyn:BAAANQAECgQIBgAAAA==.Organ:BAAANQAECgcIBwAAAA==.',
Pa='Padle:BAAANQAECgYIBgAAAA==.Paladín:BAABNQAECn8pAAMWAAkKRBViGgAbAgAWAAgKUhdiGgAbAgAHAAIKjwrodQFgAAAAAA==.Palazar:BAABNQAECn8pAAIHAAkKriDeMQABAwAHAAkKriDeMQABAwAAAA==.Paoka:BAAANQADCgQIBwABNQADCggIEQALAAAAAA==.Pargonz:BAABNQAECn80AAMNAAkKRh8IBgAjAwANAAkKRh8IBgAjAwABAAIKlw6yjABzAAAAAA==.Patoko:BAABNQAECn8kAAIYAAgKCR1YDQCVAgAYAAgKCR1YDQCVAgAAAA==.Paxwet:BAAANQAECgIIAgAAAA==.Payn:BAAANQAECgYICQAAAA==.Paypay:BAABNQAECn82AAIkAAkKFx9xCQAsAwAkAAkKFx9xCQAsAwAAAA==.',
Ph='Phalannx:BAAANQAECgIIAwAAAA==.Philipx:BAAANQAECgEIAQAAAA==.Phinks:BAAANQADCgIIAgABNQAECgkJOAAYAJokAA==.',
Pi='Piglittle:BAAANQAECgYIDQAAAA==.Pindad:BAABNQAECn8XAAIOAAkKPyLYDAB3AwAOAAkKPyLYDAB3AwAAAA==.',
Pl='Plzdispelme:BAABNQAECn8jAAMDAAkKJhm4LgCpAgADAAkKJhm4LgCpAgAHAAEKAABuoAE0AAAAAA==.',
Po='Polyphemus:BAAANQAECgEIAQAAAA==.Poplocks:BAABNQAECn8eAAIdAAgKIREbDwAJAgAdAAgKIREbDwAJAgAAAA==.',
Pr='Priesticles:BAAANQAECgUIBQABNQADCgcIFQALAAAAAA==.Proshvam:BAAANQAECgEIAQAAAA==.',
Pu='Purrzac:BAAANQAECgUIBQABNQAECgkJIwADACYZAA==.',
Py='Pyrobyrth:BAAANQADCgYIBgAAAA==.',
Ra='Racialskill:BAAANQAECggICQABNQAECgkJIwADACYZAA==.Ragingmonkx:BAABNQAECn8jAAITAAkK7hV5IAAlAgATAAkK7hV5IAAlAgAAAA==.Ragnur:BAAANQADCgQIBAAAAA==.Rareley:BAAANQAECgUICAAAAA==.Raventer:BAAANQAECggIEgAAAA==.Razdrood:BAAANQADCgUIAwABNQAECgQIBwALAAAAAA==.Razlock:BAAANQAECgQIBwAAAA==.Razorclaws:BAAANQAECgQIBwAAAA==.Razpuutinn:BAAANQABCgYICwAAAA==.',
Re='Reeps:BAAANQADCgMIAwAAAA==.Reverb:BAAANQADCgYJCQAAAA==.',
Ri='Riggamortie:BAABNQAECn8WAAICAAYKZho4VAC+AQACAAYKZho4VAC+AQAAAA==.',
Ro='Roguesucks:BAAANQADCggIDQAAAA==.Rollos:BAABNQAECn8aAAIKAAgKUBgbVABWAgAKAAgKUBgbVABWAgAAAA==.Roysmom:BAAANQADCgUICQAAAA==.',
Ry='Ryujinshin:BAABNQAFFH8TAAMPAAcKFCJjBQBnAgAPAAYKqiJjBQBnAgAIAAEKux9DCwBfAAAAAA==.Ryujinsimp:BAACNQAFFH8MAAMjAAUKURrsBAB6AQAjAAUKURrsBAB6AQAlAAQKrxRMBgAbAQA1AAQKfyIAAyUACQq/JOADANwCACMACQo1IpwIAOsCACUACAo9JOADANwCAAE1AAUUBwgTAA8AFCIA.',
['Rä']='Rävylock:BAAANQABCgIIAgABNQAECgMIAwALAAAAAA==.',
Sa='Saeli:BAAANQABCgQIBgAAAA==.Saelius:BAAANQAECgQIBAABNQAFFAQICgARAKsWAA==.Saintnick:BAAANQAECgIIAwAAAA==.Samtarkras:BAABNQAECn8jAAIEAAkKggzYHgDjAQAEAAkKggzYHgDjAQAAAA==.Sandmann:BAAANQADCgUICQAAAA==.Satonodiamon:BAAANQADCgMIAgAAAA==.',
Se='Seer:BAACNQAFFH8OAAQeAAUK0BZ8BAClAAAeAAIKGhR8BAClAAAKAAIKhiNEMgCTAAAdAAEK0AygHgBLAAA1AAQKf7IABB4ACQo5JkEBAFMDAAoACAr6JUEPAFUDAB4ACAr6JEEBAFMDAB0ABwoDJCwEAOwCAAAA.Sehkreht:BAAANQADCggIDQAAAA==.',
Sh='Shadowzugger:BAAANQAECgEIAQABNQAFFAMIBQAMAIoKAA==.Shamanigans:BAAANQADCgUICQAAAA==.Shangzha:BAABNQAECn8lAAIYAAkK5R+5BQAsAwAYAAkK5R+5BQAsAwAAAA==.Shareholder:BAEANQAECggIEAABNQAFFAQIBwAPAMcYAA==.Shiivera:BAABNQAECn8oAAIFAAkKPhoTMQCaAgAFAAkKPhoTMQCaAgAAAA==.Shimada:BAABNQAECn8iAAIOAAkKwh3+JwD2AgAOAAkKwh3+JwD2AgAAAA==.Shotsyll:BAABNQAFFH8GAAIOAAMKfRRMFgADAQAOAAMKfRRMFgADAQAAAA==.',
Sk='Skellybear:BAAANQADCgEIAQAAAA==.Skillshank:BAABNQAECn8bAAMBAAcKyxplLAAxAgABAAcKLBplLAAxAgANAAcKBhXcHADpAQAAAA==.Skynomad:BAAANQAECgYIEAAAAA==.',
Sl='Slyde:BAABNQAECn8dAAICAAcKWyNAJQCoAgACAAcKWyNAJQCoAgAAAA==.',
Sm='Smalldk:BAAANQAFFAEIAwABNQAFFAYIEgAHALEVAA==.Smallrichard:BAAANQAECgEIAQABNQAECgcIGQAPAAkYAA==.Smashytash:BAAANQAECgUIBQABNQAECggIJQAhAOkbAA==.Smerkabewl:BAAANQADCgEIAQAAAA==.Smick:BAABNQAECn8WAAIDAAcK+A6shQCGAQADAAcK+A6shQCGAQAAAA==.Smiteytash:BAAANQADCgUICAABNQAECggIJQAhAOkbAA==.',
Sn='Snek:BAAANQAECgEIBAAAAA==.Snowing:BAAANQAECgYIBgABNQAECggIEgALAAAAAA==.Snugglybear:BAABNQAECn8UAAIfAAcKfx5gDgB5AgAfAAcKfx5gDgB5AgAAAA==.Snuggyboo:BAAANQABCgEIAQAAAA==.',
So='Sodlid:BAAANQAECgIIAgABNQAECgQIBQALAAAAAA==.Solariaa:BAAANQAECgIIAwABNQAFFAQICAAkACciAA==.Solborne:BAAANQABCgQIBgAAAA==.Solfreid:BAAANQAECgYIDgAAAA==.Sophism:BAAANQAECgcICgABNQAFFAcIHgAaANUWAA==.Sotadruid:BAAANQADCgcIBwABNQAECggIFwAJAFAmAA==.Soulfang:BAABNQAECn8fAAImAAcKiBRwDQDdAQAmAAcKiBRwDQDdAQAAAA==.Soulfox:BAAANQADCgQIBAABNQAECgcICwALAAAAAA==.Soullost:BAAANQAECgUICwAAAA==.Soulréaver:BAAANQADCgEIAQAAAA==.',
Sp='Spakals:BAAANQADCgYICwAAAA==.Sparcs:BAAANQAECgEIAQAAAA==.Speknawz:BAAANQAECgUIBQABNQAFFAQIBQANAOwFAA==.Sprocketrot:BAAANQAECgUICgAAAA==.',
Sq='Squidmonk:BAABNQAECn8aAAIcAAkKoQ4nGwDKAQAcAAkKoQ4nGwDKAQAAAA==.',
St='Stardrive:BAACNQAFFH8IAAIQAAQK0wQSIAD6AAAQAAQK0wQSIAD6AAA1AAQKfyMAAhAACQpgE+J9AB0CABAACQpgE+J9AB0CAAAA.Steelwhacka:BAAANQAECgcIEQAAAA==.Stepashka:BAAANQAECggICAAAAA==.Steven:BAACNQAFFH8TAAITAAYKfBtyBAD3AQATAAYKfBtyBAD3AQA1AAQKfyQAAhMACQoYItQTALYCABMACQoYItQTALYCAAAA.Stormstyle:BAAANQAECgQIDAAAAA==.Stormsurge:BAAANQADCgUIBQAAAA==.Straxxus:BAAANQAECggIDQAAAA==.',
Su='Suddensavior:BAAANQADCgQIBAAAAA==.Suddenshift:BAAANQADCgQIAwAAAA==.Supatrollsky:BAAANQADCgcIBwABNQAECgYIEAALAAAAAA==.Superpowers:BAAANQADCgcICwAAAA==.Supersaiyan:BAAANQAECgQICgAAAA==.Surtur:BAABNQAECn81AAIQAAkKBh3NPwDIAgAQAAkKBh3NPwDIAgAAAA==.Sus:BAAANQAECgYICAAAAA==.',
Sw='Swifter:BAAANQADCgIIAgABNQAECgkJKQAWAEQVAA==.',
Sy='Sygismund:BAAANQAECgYIEgAAAA==.Synvarc:BAAANQAECgIIAgAAAA==.',
Ta='Tagbone:BAABNQAECn8nAAIOAAkKrx1PIwAIAwAOAAkKrx1PIwAIAwAAAA==.Taotien:BAAANQAECgcICgAAAA==.Tashbringer:BAAANQAECgEIAQABNQAECggIJQAhAOkbAA==.',
Tc='Tchaik:BAABNQAECn8rAAMRAAkKkiDLFAAnAwARAAkKkiDLFAAnAwASAAEKAACkdwA1AAAAAA==.',
Te='Tecknicaliti:BAAANQADCgIIAgAAAA==.Terrance:BAAANQADCgYICwAAAA==.',
Th='Thanah:BAAANQAECgUIDgAAAA==.Thaynes:BAAANQAECgUIBQAAAA==.Thayos:BAAANQAECgMIBgAAAA==.Theios:BAABNQAECn8UAAIQAAcKPAlowgBxAQAQAAcKPAlowgBxAQABNQAECggIJQACAEEXAA==.Thickthang:BAABNQAECn8xAAMYAAkKTSRaAgCGAwAYAAkKTSRaAgCGAwAGAAQKrhZm2wDaAAAAAA==.Thyrin:BAAANQADCgYIBgAAAA==.',
Ti='Tigerugly:BAABNQAECn82AAIhAAkKySOBAQCPAwAhAAkKySOBAQCPAwAAAA==.Tinytea:BAABNQAECn82AAMTAAkKCR2VEQDQAgATAAkKCR2VEQDQAgAnAAEKAADULABSAAAAAA==.Tito:BAAANQAECgEIAQAAAA==.',
To='Togepi:BAAANQADCgUICgAAAA==.Tolivan:BAAANQAECgcIEQAAAA==.Tonali:BAABNQAECn8hAAIKAAgK2wrdlACtAQAKAAgK2wrdlACtAQAAAA==.Toodawoo:BAAANQAECgIIAgAAAA==.Toranora:BAAANQADCgcIBgABNQAECgUICAALAAAAAA==.',
Tr='Trusinner:BAABNQAECn8bAAIQAAgKRxg9bQBHAgAQAAgKRxg9bQBHAgAAAA==.',
Ts='Tsusha:BAEANQAECgUIDwAAAA==.',
Tu='Turkeyleg:BAAANQADCggIHwAAAA==.',
Tw='Twippy:BAABNQAECn8kAAIGAAkKNRXuSwBDAgAGAAkKNRXuSwBDAgAAAA==.Twobeers:BAAANQADCgYICQAAAA==.',
Ty='Tyanis:BAAANQADCgcIEgABNQAECgQIAwALAAAAAA==.Tyriam:BAABNQAECn8mAAIHAAkKJB7gQwDGAgAHAAkKJB7gQwDGAgAAAA==.',
Ud='Udderchaos:BAAANQAECgEIAgAAAA==.',
Un='Unifey:BAAANQADCgYIBgAAAA==.',
Va='Valess:BAAANQAECgEIAQAAAA==.Valikbagul:BAAANQAECgEIAQAAAA==.Vandeia:BAAANQADCgYIBgAAAA==.Varrae:BAAANQADCgIIAgAAAA==.',
Ve='Vectore:BAAANQAECgQICAAAAA==.Ventres:BAAANQADCgYIBgAAAA==.Veronique:BAACNQAFFH8IAAIjAAQKsRncBgApAQAjAAQKsRncBgApAQA1AAQKfy0AAiMACQpBIEMHAA0DACMACQpBIEMHAA0DAAAA.Verso:BAABNQAECn8XAAIoAAgKZhjGBgBYAgAoAAgKZhjGBgBYAgAAAA==.',
Vi='Vitalithry:BAABNQAECn8gAAIlAAgKtBguBgBrAgAlAAgKtBguBgBrAgAAAA==.Vivii:BAAANQAECgcICwAAAA==.Vizzysmash:BAAANQADCggICAABNQAECggIJgAJAJAVAA==.',
Vo='Voden:BAAANQABCgIIBAAAAA==.Volle:BAAANQADCgEIAQAAAA==.',
Vy='Vyinn:BAAANQADCgQJBAAAAA==.Vyndra:BAAANQADCgYIBQAAAA==.',
Wa='Warchicken:BAAANQAECgUIBwAAAA==.',
We='Weituvoidy:BAAANQADCgcIBwAAAA==.Wetpax:BAABNQAECn8yAAMXAAkKLxg/KABRAgAXAAkKLxg/KABRAgAJAAUKuww7iwDQAAAAAA==.',
Wh='Whatchawant:BAAANQADCggIEQAAAA==.Whiskeybeer:BAABNQAECn8iAAMGAAgK2x6fJgDmAgAGAAgK2x6fJgDmAgAFAAMKqxR62QCwAAAAAA==.',
Wi='Wiiska:BAACNQAFFH8IAAISAAQK/hQ2CwA3AQASAAQK/hQ2CwA3AQA1AAQKfygAAxIACQqGHJQUALwCABIACQqGHJQUALwCABEAAgpIAtTtAFAAAAAA.Wildling:BAAANQADCgIIAwAAAA==.Windoelicker:BAAANQADCgcIFQAAAA==.',
Wo='Worgya:BAAANQADCgUIBQABNQAECgcICwALAAAAAA==.',
Wr='Wrecker:BAAANQAECgEIAQABNQAECgkJFwAOAD8iAA==.Wrlccywhefr:BAABNQAECn8oAAQBAAkK6yI5IgBwAgABAAcKwiM5IgBwAgAoAAYKph+5CQDnAQANAAIKZB1lQgCeAAAAAA==.',
Wu='Wuggles:BAABNQAECn8eAAIkAAkKORcIGgBmAgAkAAkKORcIGgBmAgAAAA==.',
Xa='Xalatoes:BAAANQAECgQIAwAAAA==.',
Xb='Xbalanque:BAABNQAECn8bAAIOAAcK2RdLdQAiAgAOAAcK2RdLdQAiAgAAAA==.',
Xu='Xu:BAAANQADCgUIBQABNQAECggIGwAQAEcYAA==.',
Xy='Xyklon:BAAANQADCgIIAgAAAA==.',
Ya='Yahmon:BAAANQAECgQIBgAAAA==.',
Ye='Yetil:BAAANQAECgcIEQAAAA==.',
Yn='Ynotraw:BAABNQAECn8sAAIQAAkKoSI6HQBBAwAQAAkKoSI6HQBBAwAAAA==.Ynotstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yourephired:BAABNQAECn8aAAMIAAcKtA4tEgCBAQAIAAcKtA4tEgCBAQAPAAEKAADe1QEoAAAAAA==.',
Za='Zaerix:BAAANQADCgYICQAAAA==.Zaknafein:BAAANQAECgEIAQABNQAECgkJLwAIAC8aAA==.Zarah:BAAANQAECgEIAQAAAA==.Zaycursed:BAAANQAECgQICgABNQAECggIHgAGABQfAA==.Zaydream:BAAANQADCgcIBwABNQAECggIHgAGABQfAA==.Zaylight:BAAANQADCggICAABNQAECggIHgAGABQfAA==.Zayseer:BAABNQAECn8eAAIGAAgKFB+1NwCVAgAGAAgKFB+1NwCVAgAAAA==.',
Ze='Zello:BAAANQAECgYIEAAAAA==.',
Zh='Zhengy:BAAANQAECgQICAABNQAECgkJLwAIAC8aAA==.',
Zi='Ziggybeast:BAABNQAECn8fAAQVAAkK1B2/NgAyAgAVAAcKxx6/NgAyAgAkAAcKqhi/IwAEAgAfAAEKAAA3YgArAAAAAA==.Zignag:BAAANQAECgEIAQAAAA==.',
Zu='Zuljeet:BAAANQADCggICwAAAA==.',
Zy='Zydia:BAAANQAECgQIDQAAAA==.',
['Zå']='Zåythyr:BAAANQADCgcIBwABNQAECggIHgAGABQfAA==.',
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
