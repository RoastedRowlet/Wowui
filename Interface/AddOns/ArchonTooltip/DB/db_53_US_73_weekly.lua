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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Paladin-Retribution','Druid-Guardian','Paladin-Holy','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','Mage-Frost','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Rogue-Assassination','Shaman-Restoration','Evoker-Devastation','Hunter-BeastMastery','Druid-Balance','Hunter-Marksmanship','DeathKnight-Frost','Shaman-Enhancement','Druid-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Protection','Hunter-Survival','DemonHunter-Devourer','Evoker-Augmentation','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-09-22',data={Ah='Ahpuch:BAAANQAECgcIEQAAAA==.',
Ai='Aidasul:BAAANQAECgQJBQAAAA==.',
Al='Aldesca:BAAANQAECgQJBQAAAA==.',
An='Ancile:BAAANQAECgMJAwAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgYIBwAAAA==.',
Ar='Armstrõng:BAAANQAECgIJAgAAAA==.',
As='Ashaxxi:BAAANQAFFAEJAQAAAA==.Ashpaw:BAAANQAECgcIEwABNQAFFAEJAQABAAAAAA==.Aspen:BAAANQAECgEIAQAAAA==.',
At='Atcjedi:BAAANQAECgQIBgAAAA==.Atmospherewr:BAAANQAECggICgABNQAFFAYIDgACAO8gAA==.Atmospherez:BAACNQAFFIEOAAICAAYK7yCfAQByAgACAAYK7yCfAQByAgA1AAQKgR8AAgIACQqyJSoRAHcDAAIACQqyJSoRAHcDAAAA.',
Av='Avaniah:BAAANQAECgUIEAAAAA==.',
Az='Azmodan:BAAANQADCgcIBwAAAA==.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQAECgQIBAAAAA==.Baep:BAAANQAECgQJBAAAAA==.Bandrago:BAAANQAECgYJCwAAAA==.Batmeng:BAAANQAECgIJAgAAAA==.',
Be='Beaulioh:BAAANQAECgcJCwAAAA==.Bekzarn:BAAANQAECgEIAQABNQAECgYIDgABAAAAAA==.Benfrank:BAAANQAECgYJDwAAAA==.Bernthul:BAAANQAECgQIBwAAAA==.Bethan:BAAANQAECgYJCwAAAA==.',
Bl='Blaart:BAABNQAECoEaAAQDAAgKRRdlRgAEAgADAAcK5BZlRgAEAgAEAAIKDhYqRwCFAAAFAAEK4QcfJAAwAAAAAA==.Blackwaters:BAAANQAECgUJDgAAAA==.Blax:BAAANQAECgYJCgAAAA==.Blindcow:BAABNQAECoEdAAIGAAkKbx47JwDTAgAGAAkKbx47JwDTAgAAAA==.Blindhugs:BAAANQAECgcIDwAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgYIBQAAAA==.Blùey:BAAANQADCgYIBgABNQAECgkJHQAHAAMeAA==.',
Bo='Bodytypebig:BAABNQAECoEkAAIIAAgK6BORCwDrAQAIAAgK6BORCwDrAQAAAA==.Boicrystian:BAAANQAECgIJAgAAAA==.Bolillo:BAAANQADCgcIDAABNQAECgcJCwABAAAAAA==.Bomie:BAAANQADCgUIBQAAAA==.Bookitty:BAAANQADCggIGAAAAA==.Boosty:BAABNQAECoEUAAIGAAYKNh8rVgAUAgAGAAYKNh8rVgAUAgAAAA==.Bossladie:BAAANQADCgEJAQAAAA==.Bossladìe:BAABNQAECoEaAAIJAAkKSxBSLgBIAgAJAAkKSxBSLgBIAgAAAA==.Boston:BAAANQADCgUIBQAAAA==.',
Br='Brewholic:BAAANQAECgUJBwAAAA==.Bristle:BAABNQAECoEYAAIKAAgKvx7dHQC/AgAKAAgKvx7dHQC/AgAAAA==.Brommix:BAAANQADCgMIBgAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDgAAAA==.Bullshiitake:BAABNQAECoEWAAIJAAgK+w6fRQDdAQAJAAgK+w6fRQDdAQAAAA==.',
Ca='Calaglin:BAAANQAECgcJEAAAAA==.Calelorian:BAAANQADCgQIBAAAAA==.Catstack:BAAANQADCggJHAAAAA==.',
Ce='Celdiirn:BAAANQADCgYJCwAAAA==.Celesti:BAAANQAECgUIEQAAAA==.',
Ch='Chiky:BAAANQAECgIIAwAAAA==.Choom:BAAANQAECgMIAwAAAA==.Chubsy:BAAANQAECggICQAAAA==.Chuckkyd:BAAANQAECgYJDwAAAA==.',
Cl='Claugh:BAAANQAECggIEAAAAA==.Cleb:BAAANQAFFAIIAgAAAA==.Clocker:BAAANQAECgUICQAAAA==.Clumbsykoala:BAAANQAECgQJBwAAAA==.',
Co='Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAACNQAFFIEOAAILAAYKhxK3AgABAgALAAYKhxK3AgABAgA1AAQKgR0AAgsACQovEooQAE4CAAsACQovEooQAE4CAAAA.Combatcow:BAABNQAECoEdAAIMAAgK7CKrAQAdAwAMAAgK7CKrAQAdAwAAAA==.Contagion:BAAANQAECggJCAAAAA==.Cozmic:BAABNQAECoEYAAMCAAgKgiLmUQCWAgACAAcK1yHmUQCWAgANAAMKzSL3EAAdAQAAAA==.',
Cr='Craftymidget:BAAANQADCggJCAAAAA==.Crucifixd:BAAANQAECgEIAQAAAA==.Cryptonic:BAAANQAECggICAAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAAANQAECgcIEgAAAA==.',
Cu='Curandero:BAAANQAECgQIEgAAAA==.Curie:BAAANQAECgEIAQABNQAECgcIGgAOAOwZAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUIBQAAAA==.Dameck:BAABNQAECoEXAAIGAAgK8w/nYADvAQAGAAgK8w/nYADvAQAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCggICgABNQAECgYJDQABAAAAAA==.Dasdots:BAAANQADCggIFwAAAA==.Dasmuro:BAAANQADCgEJAQABNQAECgUIDAABAAAAAA==.Dazzeler:BAAANQAECgYJDQAAAA==.',
De='Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAAANQAECgUJDgAAAA==.Delver:BAAANQAECgQICQAAAA==.Demongirly:BAAANQABCgQIBAAAAA==.Demonsue:BAAANQABCgIJAgAAAA==.Denathria:BAAANQAECgYJDAAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAACNQAFFIEPAAMPAAUKsBrvAQDlAQAPAAUKsBrvAQDlAQAQAAEKmwawGQBZAAA1AAQKgR4AAg8ACQoRI8wEAHEDAA8ACQoRI8wEAHEDAAAA.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.Difflect:BAAANQADCgYIBgABNQADCgYIDAABAAAAAA==.',
Do='Doak:BAABNQAECoEaAAMOAAcK7BlkEQA0AgAOAAcK7BlkEQA0AgARAAEKmwhPXQA+AAAAAA==.Doonfist:BAAANQABCggIEAAAAA==.Dottie:BAAANQADCggIGAAAAA==.Dotz:BAABNQAECoEeAAMDAAkKox1sPAArAgADAAcKSR1sPAArAgAEAAYKdA5NHQBjAQAAAA==.Douchec:BAAANQADCgIIAgAAAA==.',
Dr='Draconius:BAAANQADCgUIDwAAAA==.Draenor:BAAANQAECgEJAgAAAA==.Dragonforce:BAAANQAECgQICAAAAA==.Dragonhaze:BAAANQAECgUJCgAAAA==.Dragonskull:BAAANQAECgYJBgAAAA==.Drazentar:BAAANQAECgUIDAAAAA==.Dream:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Drevox:BAAANQAECgYJDwAAAA==.Druiddruid:BAAANQADCgYICQAAAA==.',
Du='Dulgar:BAABNQAECoEYAAISAAgKABlsLgBCAgASAAgKABlsLgBCAgAAAA==.Dumami:BAAANQAECgEJAQABNQAECgIJAgABAAAAAA==.',
['Dë']='Dëlilah:BAAANQAECgIIAgAAAA==.',
Ea='Eaglewarrior:BAAANQADCggIDgAAAA==.',
El='Elind:BAAANQADCgQIBAAAAA==.Elleduff:BAAANQAECgQJCQAAAA==.Eloragon:BAAANQABCgMIAwAAAA==.Elyssabeta:BAAANQADCgQJBAAAAA==.Elysstaa:BAABNQAECoEYAAMQAAgKkhkYMAA2AgAQAAgKkhkYMAA2AgAPAAEKXxUtTwBCAAAAAA==.',
En='Entïty:BAAANQADCgcJDgABNQAECgMIBAABAAAAAA==.',
Eo='Eogden:BAAANQAECgYICgAAAA==.',
Eq='Equilibria:BAAANQAECgQJBQAAAA==.',
Er='Erida:BAAANQAECgIJAgAAAA==.Ers:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.',
Et='Etík:BAAANQAECgQIBgAAAA==.',
Ev='Evocative:BAACNQAFFIEFAAITAAIKwhcEBwCiAAATAAIKwhcEBwCiAAA1AAQKgRwAAhMACQrCHssFAAEDABMACQrCHssFAAEDAAAA.',
Ex='Exaltso:BAAANQADCgYIDwAAAA==.',
Ey='Eyebright:BAAANQAECgEJAQAAAA==.Eyye:BAAANQADCgQIBgABNQAECgIIBAABAAAAAA==.',
Fa='Farns:BAACNQAFFIELAAMNAAQK+iAUAgCwAAACAAMKEyPJEwArAQANAAIKQRsUAgCwAAA1AAQKgR0AAwIACQoYJdsJAKADAAIACQryJNsJAKADAA0ABAobJjcMAHMBAAAA.Fawndolynn:BAAANQAECgQJBwAAAA==.',
Fe='Felinepriest:BAAANQAECgQICgAAAA==.Felovan:BAAANQADCgYIBwAAAA==.Felsoaked:BAAANQAECgEIAQAAAA==.Felstehr:BAAANQAECgUJCgAAAA==.Feltotes:BAAANQAECgQIBAAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAABNQAECoEZAAISAAkKFCCdCwAwAwASAAkKFCCdCwAwAwAAAA==.Firebäne:BAAANQAECgcJEQAAAA==.Fistnor:BAAANQAECgEIAQAAAA==.',
Fl='Flaminghawk:BAACNQAFFIEJAAICAAQKchTtDwBgAQACAAQKchTtDwBgAQA1AAQKgRoAAgIABwo2ISJbAHsCAAIABwo2ISJbAHsCAAAA.',
Fr='Franklin:BAAANQAECgYICAAAAA==.Frankotronic:BAABNQAECoEYAAICAAcKQBQumgDXAQACAAcKQBQumgDXAQAAAA==.Freakies:BAAANQADCgQIBgAAAA==.Freyin:BAABNQAECoEYAAIUAAgKixQWNQBgAgAUAAgKixQWNQBgAgAAAA==.Frolgar:BAAANQADCgYICAAAAA==.Frostyflakez:BAAANQAECgEJAQAAAA==.',
Fu='Fullclangg:BAABNQAECoEXAAIJAAgKdx2AHACwAgAJAAgKdx2AHACwAgABNQAFFAcJGgALAJ4eAA==.Fulldracarys:BAACNQAFFIEaAAILAAcKnh6SAACpAgALAAcKnh6SAACpAgA1AAQKgR8AAgsACQrPIq0EAD4DAAsACQrPIq0EAD4DAAAA.Fullgabagool:BAABNQAECoEeAAIQAAkKeB0zDwAFAwAQAAkKeB0zDwAFAwABNQAFFAcJGgALAJ4eAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAcJGgALAJ4eAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCggIFwAAAA==.Ganster:BAAANQAECgEIAQAAAA==.Gaya:BAAANQADCgQJBgAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAAANQAFFAIIAwAAAA==.',
Gl='Glimpse:BAAANQAECgYJBgAAAA==.',
Gn='Gnomebody:BAAANQAECgIIAwAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBgAAAA==.',
Gr='Grimknight:BAABNQAECoEhAAIHAAkKPyYqBQC5AwAHAAkKPyYqBQC5AwAAAA==.Groovi:BAAANQADCgUIBQAAAA==.',
Gu='Guycow:BAABNQAECoEcAAIJAAkK9R4eDgAdAwAJAAkK9R4eDgAdAwAAAA==.',
Ha='Hambonë:BAACNQAFFIETAAIVAAYKdiDYAQBRAgAVAAYKdiDYAQBRAgA1AAQKgR8AAhUACQpnJhIBAOMDABUACQpnJhIBAOMDAAAA.Hardballs:BAAANQADCgUIBgAAAA==.Hashbrowns:BAABNQAECoEWAAIHAAkKlh/+FwAdAwAHAAkKlh/+FwAdAwAAAA==.Havdk:BAEANQAECgIIAwAAAA==.Haxxorwyn:BAAANQAECgcIDQAAAA==.Hazreil:BAABNQAECoEYAAIIAAgKhhNIDADaAQAIAAgKhhNIDADaAQAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIDgAAAA==.Heavenlee:BAAANQAECgUJCgABNQADCggIDgABAAAAAA==.Hecklefish:BAABNQAECoEhAAMUAAkKiCZ8AAD9AwAUAAkKiCZ8AAD9AwAWAAIKkhwMQgClAAAAAA==.Hellik:BAAANQABCgMIAwAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAAANQAECgcIEAAAAA==.Highdegrees:BAAANQAECgIIAgAAAA==.Hinatta:BAAANQADCggICAABNQAECgQJDQABAAAAAA==.Hitagi:BAAANQAECgMICwAAAA==.',
Ho='Hole:BAAANQAECgEIAQAAAA==.Hollo:BAAANQAECgIIAwAAAA==.Holyblasts:BAAANQAECgYJDAAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQABCgMJBAABNQADCgYJBwABAAAAAA==.Horsey:BAAANQAECgYIBwABNQAECggIFwAXAOQeAA==.Hownow:BAAANQADCgIIAgAAAA==.',
Hu='Hummingbird:BAAANQADCgYIDgABNQAECgYJDAABAAAAAA==.Hungus:BAAANQAECgQJBgAAAA==.Hurtszick:BAAANQAECgQIBgAAAA==.',
Hy='Hydrotiger:BAAANQAECgMJAwABNQAECggIHQAYALccAA==.',
['Hä']='Härasou:BAAANQADCgYJCAAAAA==.',
Il='Illiturtle:BAAANQAECgcIDQAAAA==.',
Im='Imnotthtgood:BAAANQADCgYJDAAAAA==.',
In='Indigolemon:BAABNQAECoEUAAMVAAcK+RPOLwDpAQAVAAcK+RPOLwDpAQAZAAEKxwdhUQApAAABNQAECggJCQABAAAAAA==.Inkenhancer:BAAANQAECgUICgAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Iy='Iyari:BAAANQADCgUJBQAAAA==.',
Ja='Jamie:BAAANQAECgcJDQAAAA==.',
Je='Jeynsa:BAAANQADCgUIBwABNQAECgcIEAABAAAAAA==.',
Ji='Jingadingado:BAAANQADCgYIBgAAAA==.',
Jo='Jollyollie:BAAANQADCgQIBQAAAA==.Joppy:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQAECgQIBgAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jë']='Jëf:BAAANQADCgIIAgAAAA==.',
['Jô']='Jôker:BAAANQAECgMIBQAAAA==.',
Ka='Kacho:BAAANQAECgEJAQAAAA==.Kaelara:BAAANQAECggJBgAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kaorii:BAAANQADCgYIBgAAAA==.Kappo:BAAANQAECgYJCgAAAA==.Kathorall:BAAANQAECgUJEAAAAA==.Kawaiihealer:BAAANQAECgQJDQAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIAwAAAA==.Kemper:BAAANQAECgQJCAAAAA==.Kerrs:BAAANQAECgEJBAAAAA==.',
Ki='Kiddyl:BAAANQADCgUICQAAAA==.Kidneypopper:BAAANQADCgcJCAABNQAECggIGAACAIIiAA==.Kievit:BAAANQAECgYIBwAAAA==.Kir:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.Kittana:BAAANQAECgYIDwAAAA==.Kittyhawke:BAAANQAECggJCQAAAA==.',
Kk='Kkelhus:BAAANQAECgIJAwAAAA==.Kkrantuq:BAABNQAECoEXAAIOAAkKzg/dDgBYAgAOAAkKzg/dDgBYAgAAAA==.Kkylar:BAAANQADCgYICgAAAA==.',
Kl='Klariityy:BAAANQAECggIDgAAAA==.Klarity:BAAANQADCgYIBgAAAA==.Klarityx:BAABNQAECoEZAAICAAkK2xVOVQCMAgACAAkK2xVOVQCMAgAAAA==.',
Kn='Knownentity:BAAANQAECgMIBAAAAA==.',
Ko='Koma:BAAANQADCggJCAABNQAFFAUICwAKACojAA==.Komatos:BAACNQAFFIELAAIKAAUKKiM2AgADAgAKAAUKKiM2AgADAgA1AAQKgSQAAgoACQqDJkIBAOkDAAoACQqDJkIBAOkDAAAA.Koreantacos:BAAANQADCgcIDQAAAA==.Koronus:BAAANQADCgcJFgAAAA==.',
Kr='Kracklin:BAAANQADCgYIBgAAAA==.',
Ks='Ks:BAAANQADCgMIBgABNQAECgQIBgABAAAAAA==.',
Ku='Kurisutina:BAAANQAECgQICAAAAA==.',
['Kâ']='Kânamë:BAAANQADCggICAABNQAECgcIGAAaALYSAA==.',
['Kê']='Kênsêi:BAABNQAECoEYAAIaAAcKthKpNgDIAQAaAAcKthKpNgDIAQAAAA==.',
['Kô']='Kôan:BAAANQAECgMJAwAAAA==.',
La='Lanatec:BAAANQAECgEJAgAAAA==.',
Le='Leafyjoe:BAAANQAECgYIDwAAAA==.Lechencaja:BAAANQADCgYJBgABNQAECgMIBQABAAAAAA==.Legendarybob:BAAANQADCgYJBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAABNQAECoEXAAQaAAcKwAdASABoAQAaAAcK/wZASABoAQAbAAYKlQTFYwDgAAAXAAMK2wIcXgBnAAAAAA==.Legö:BAAANQAECgUIBQABNQAECgcJFwAaAMAHAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECgcJEwABAAAAAA==.',
Li='Lido:BAAANQAECggJCAAAAA==.Lilcowdk:BAAANQADCgEIAQABNQAECgYJEgABAAAAAA==.Lildeemon:BAAANQAECgYJEgAAAA==.Lilspyro:BAAANQAECgQJBAAAAA==.Livathian:BAAANQAECgcJEwAAAA==.Lizwiz:BAAANQADCgQIBAAAAA==.',
Lo='Lokrah:BAAANQABCgMIBAAAAA==.',
Lu='Lucerubis:BAAANQADCggICAAAAA==.Lucifiux:BAAANQAECgcJCgAAAA==.Lunavel:BAABNQAECoEaAAMHAAcKSRVicQCpAQAHAAYKlhdicQCpAQAcAAUKtQ4eKQADAQAAAA==.',
Ly='Lydo:BAAANQAECggICwAAAA==.',
Ma='Magicdan:BAAANQADCgYIBwAAAA==.Malnorr:BAAANQAECgYJDgAAAA==.Mandragon:BAAANQADCgUIBQABNQAECgkJHAAJAPUeAA==.Mangol:BAAANQAECgcJCAAAAA==.Manudei:BAAANQADCgcICQAAAA==.Maryillo:BAACNQAFFIEOAAIVAAYKSh1FAgAxAgAVAAYKSh1FAgAxAgA1AAQKgR8AAhUACQr8JDEIAGsDABUACQr8JDEIAGsDAAAA.Mattdaemon:BAAANQAECgUIBQAAAA==.',
Mc='Mcmannis:BAAANQAECgcIBwAAAA==.Mcpoltrain:BAAANQAECgIIAgAAAA==.',
Me='Mennil:BAAANQAECgIJAgAAAA==.Meolater:BAAANQAECgYIEQAAAA==.Mesmerise:BAAANQAECgQJBAAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECgcJEwABAAAAAA==.Mindgoblinn:BAAANQAECgUJCAAAAA==.Minicookie:BAAANQADCgEIAQAAAA==.Minyaw:BAAANQAECgIJAgABNQAECgcIGgAOAOwZAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQAECgQJBwAAAA==.',
Mm='Mmchocolat:BAAANQAECgIJAgAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEBNQAECoEYAAIdAAgKTxwkAgDHAgAdAAgKTxwkAgDHAgAAAA==.Moolissa:BAAANQAECgQIDAAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgMIBgAAAA==.Morbidchaos:BAACNQAFFIENAAIeAAYK0iDsAABrAgAeAAYK0iDsAABrAgA1AAQKgSEAAh4ACQpAIiMGAFgDAB4ACQpAIiMGAFgDAAAA.Morkels:BAAANQAECgcIDAABNQAFFAcIFwAfAD0fAA==.',
Mu='Muddyshark:BAAANQAECgUICgAAAA==.Mukatsuku:BAAANQAECgQICAAAAA==.Muscida:BAAANQAECgEIAQAAAA==.',
My='Mykhawk:BAAANQADCgUICAAAAA==.',
Na='Naeth:BAAANQAECgYIEwAAAA==.Nalrot:BAAANQADCggIDwABNQAECgQJBAABAAAAAA==.Narcine:BAAANQAECgcJDQAAAA==.',
Ne='Neciecakes:BAABNQAECoEYAAMJAAgK4BCRPQAAAgAJAAgK4BCRPQAAAgAHAAEK4BC5EQE+AAAAAA==.Nee:BAABNQAECoEdAAMSAAkKpBGXNAAiAgASAAkKpBGXNAAiAgAKAAUKuBCicABCAQAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nekus:BAAANQADCgcIBwAAAA==.Nelor:BAAANQAECgUJDAAAAA==.Neverheal:BAAANQADCgEIAQAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ng='Ngàymai:BAAANQADCgQIBAAAAA==.',
Ni='Nightwatchr:BAAANQAECgYJCAAAAA==.Nisona:BAAANQAECgMJAwAAAA==.Nitashal:BAABNQAECoEfAAMLAAkKch01CADuAgALAAkKch01CADuAgATAAEKoA4xLgA2AAAAAA==.',
No='Nokthro:BAAANQADCgYJBgABNQAECgkJIgATAKQeAA==.Noremac:BAAANQADCgYIDAAAAA==.',
Nu='Nubsaiboot:BAAANQAECgUJBQABNQAECgUICQABAAAAAA==.',
Ny='Nythariel:BAAANQADCggJFwAAAA==.',
Od='Odi:BAAANQADCggJIQAAAA==.',
Ok='Okiaat:BAAANQAECgMJAwAAAA==.',
Ol='Oliviawildè:BAAANQAECggIEAAAAA==.',
On='Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAAANQAECgYIDgAAAA==.Pallyforhire:BAAANQADCgcJFwAAAA==.Panfriedrice:BAAANQAECggIAQAAAA==.Pantyblossom:BAAANQAECgUJBgABNQAECgUJDAABAAAAAA==.',
Pe='Peaches:BAAANQAECgQIBgAAAA==.Peewees:BAAANQADCgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAAANQAECgYIEgAAAA==.Peladin:BAAANQABCgcJDAAAAA==.Pelado:BAAANQABCgIJAgAAAA==.Pelito:BAAANQADCgUJBQAAAA==.Pell:BAAANQADCgEJAQAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQADCgYIFgABNQAECggIGAAGAMMLAA==.',
Ph='Phaeddrus:BAAANQAECgQIBQAAAA==.Phobos:BAAANQAECgUJBQAAAA==.Phrix:BAAANQADCgYIBgABNQAECgkJIgATAKQeAA==.',
Pi='Pinecone:BAABNQAECoEbAAIVAAkKbSO2DAA3AwAVAAkKbSO2DAA3AwAAAA==.',
Pl='Ploppster:BAAANQADCggIDQAAAA==.Plot:BAAANQAECggJDAAAAA==.',
Po='Poekimaw:BAAANQAECgEIAQAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAABNQAECoEcAAIHAAkKiyV7BQC2AwAHAAkKiyV7BQC2AwAAAA==.Poppinin:BAAANQAECgUJCgAAAA==.Potaters:BAAANQADCgQIBAAAAA==.Potshotbot:BAAANQADCgYJBgAAAA==.Powerwordhug:BAAANQAECgQIBgABNQAECgcIDwABAAAAAA==.',
Pr='Praedo:BAAANQADCgYJBgAAAA==.Prevaleon:BAAANQADCgMIAgAAAA==.',
Ps='Psychaos:BAAANQADCgUIBQAAAA==.Psychostorm:BAAANQAECgEIAQAAAA==.Psychritic:BAAANQAECgcJEwAAAA==.Psyence:BAAANQADCgcIDgAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purrsnikitty:BAAANQADCggIDgAAAA==.Pus:BAAANQADCgYIBgAAAA==.',
Qu='Quillmane:BAAANQADCggIFgABNQAECgkJIgATAKQeAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAABNQAECoEaAAIeAAgKoRoZFACCAgAeAAgKoRoZFACCAgAAAA==.Ragingdeath:BAAANQADCgYJBwAAAA==.Rainakamugi:BAAANQAECgQJBwABNQAECgkJHAAQAOwTAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQAECgIJAgAAAA==.Ralphanir:BAAANQAECgUJCgAAAA==.Raskreia:BAAANQADCggICQAAAA==.Raygyu:BAAANQADCgQIBAABNQAFFAEIAQABAAAAAA==.Rayvoker:BAAANQADCgYJDAABNQAFFAEIAQABAAAAAA==.',
Re='Reek:BAAANQAECgQIDAAAAA==.Rexari:BAAANQAECgQIDQAAAA==.Rezmae:BAAANQAECgEIAgAAAA==.',
Ri='Riniedaze:BAAANQADCgUICgAAAA==.',
Ro='Rockandstone:BAABNQAECoEoAAIJAAkK0BT2IQCNAgAJAAkK0BT2IQCNAgAAAA==.Rocki:BAAANQAECgEJAQABNQAECgkJHgADAKMdAA==.Rooty:BAAANQAECgMIBAAAAA==.Roron:BAAANQAECgMIAwAAAA==.',
Sa='Safetyspork:BAAANQAECgIIBAAAAA==.Sagë:BAAANQAECgUJBwAAAA==.Sakonutz:BAAANQAECgYJDQAAAA==.Salsa:BAAANQADCgcJDQAAAA==.Saresh:BAAANQAFFAEJAQAAAA==.Sathariel:BAAANQABCgIJAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.',
Sc='Schlee:BAAANQABCgYJCAAAAA==.Screeps:BAAANQABCgcJDgABNQADCgYJBwABAAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAAANQAECgUJDAAAAA==.Sendh:BAAANQAECgUJCQAAAA==.Sermet:BAAANQAECgIIBAABNQAECgYJCgABAAAAAA==.Sermonn:BAAANQAECgEIAQAAAA==.Serous:BAAANQAECgQJBgAAAA==.Serwellmet:BAAANQADCgMJAwABNQAECgYJCgABAAAAAA==.Seshin:BAAANQAECggJIgAAAQ==.Setal:BAABNQAECoEiAAITAAkKpB7lAwA9AwATAAkKpB7lAwA9AwAAAA==.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgcIGgAOAOwZAA==.Shammoo:BAAANQAECgIJAgAAAA==.Shcho:BAAANQADCgMIAwAAAA==.Sheepe:BAAANQAECgQJBgAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgQIBAAAAA==.Shinyscalp:BAAANQAECgcJDAAAAA==.Shogunz:BAAANQAECgUJBgAAAA==.',
Si='Simaria:BAAANQADCgYIEgAAAA==.Sinapaladin:BAAANQAECgUICQAAAA==.Siomara:BAAANQAECgUICwAAAA==.Sivanya:BAAANQADCgYJBgAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgYJBwAAAA==.Skrepz:BAAANQABCgIJAgABNQADCgYJBwABAAAAAA==.Skypri:BAAANQADCgYIBgAAAA==.',
Sl='Slabbster:BAAANQAECgQIBgAAAA==.',
Sm='Smooshednewt:BAABNQAECoEdAAIYAAgKtxxrBwC7AgAYAAgKtxxrBwC7AgAAAA==.',
Sn='Sne:BAAANQAECgQJBQAAAA==.Snoop:BAAANQAECgMIBAAAAA==.',
So='Soloa:BAAANQAECgIIAgAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAAANQAECgYIEgABNQAECgcIEAABAAAAAA==.Sosneaky:BAAANQADCgMICAAAAA==.Soulfuria:BAAANQAECggIBwAAAA==.',
Sp='Spekk:BAAANQADCgYICgAAAA==.Speknawz:BAAANQAECggJEwAAAA==.Splatzill:BAAANQADCgIIAgABNQAECggIHgAGADEaAA==.Spoiledangel:BAAANQAECgUJCgAAAA==.Spoonhat:BAAANQADCgYICgABNQAECgIIBAABAAAAAA==.Springz:BAAANQAECgUICAAAAA==.',
St='Staggering:BAAANQAECgYICgAAAA==.Starryniight:BAAANQAECgMJAwAAAA==.Stephsux:BAAANQAECgUIDAAAAA==.Stickers:BAAANQAECgMJBAAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgYIBwAAAA==.Suika:BAAANQAECgQIBAAAAA==.Supanova:BAAANQAECgYIDAABNQAECggIHQAYALccAA==.Surwick:BAAANQAECgUJBQAAAA==.',
Sv='Svelus:BAACNQAFFIEJAAIHAAQKWCIMBACTAQAHAAQKWCIMBACTAQA1AAQKgSAAAgcACQqIJcUGAKcDAAcACQqIJcUGAKcDAAAA.',
Sw='Swingin:BAAANQAECgUJDgAAAA==.',
Sy='Sycophancy:BAAANQADCgQIBAAAAA==.Synaptichole:BAAANQAECgIJAgAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tachealz:BAAANQAECgYIBgAAAA==.Tanurhide:BAAANQADCgQIBAAAAA==.Tartan:BAAANQAFFAEJAQAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.Taylorswif:BAAANQADCgEIAQABNQAECgkJGgACAB4fAA==.',
Te='Techi:BAAANQADCgIIAgAAAA==.Teewat:BAAANQADCgUIBQAAAA==.Temres:BAAANQAECgYJCgAAAA==.Tendermulva:BAAANQAECgYIDwAAAA==.Terekk:BAAANQADCgUJDAAAAA==.Teshtara:BAAANQADCgYJBgABNQAECgcIEAABAAAAAA==.',
Th='Theod:BAAANQADCgYIBwAAAA==.Thesauce:BAACNQAFFIEGAAMgAAQKdRmwAQBdAQAgAAQKdRmwAQBdAQAhAAIKhxpXBwCjAAA1AAQKgR8AAyEACQr6JJIDAH0DACEACQoXJJIDAH0DACAABwoSI7wEAMgCAAAA.Thiaw:BAAANQADCggICAAAAA==.Thimo:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.Thrikal:BAABNQAECoEYAAIiAAgK4g3TJADsAQAiAAgK4g3TJADsAQAAAA==.',
To='Tomsmg:BAABNQAECoEYAAMCAAgKxRc+aABYAgACAAgKxRc+aABYAgANAAEKdAftMQA0AAAAAA==.Toofs:BAAANQAECgQIBgAAAA==.Toxifay:BAAANQAECgUJCQAAAA==.',
Tr='Traell:BAAANQADCgYIDAABNQAECgkJGAAiAMEeAA==.Trd:BAAANQABCgcJCAAAAA==.Treehuggles:BAAANQAECgQJBAABNQAECgcIDwABAAAAAA==.Truedat:BAAANQADCgQIBwAAAA==.',
['Tì']='Tìõ:BAAANQADCgYIBgABNQAECgcIGAAaALYSAA==.',
Ug='Ughtismo:BAAANQADCgUJBQAAAA==.',
Un='Undeadban:BAAANQABCgcJCQAAAA==.',
Us='Usagiknight:BAAANQAECgYICgAAAA==.Ushii:BAAANQAECgQJCgAAAA==.',
Va='Valdemort:BAAANQADCgQJBAABNQAECgIIBAABAAAAAA==.Valei:BAAANQAECgMIAwAAAA==.',
Ve='Veganforlife:BAAANQADCgIIAwAAAA==.',
Vi='Vinda:BAABNQAECoEYAAIPAAgKmRByGgAFAgAPAAgKmRByGgAFAgAAAA==.Vivixia:BAAANQAECgYICQAAAA==.',
Vo='Voodoolock:BAAANQAECgQICwABNQAECgYIBgABAAAAAA==.',
Wa='Walkingboot:BAAANQADCgQIBAAAAA==.Wallo:BAABNQAECoEYAAIGAAgKwwstcQC4AQAGAAgKwwstcQC4AQAAAA==.Washedbolt:BAAANQADCgYIBgAAAA==.Washedpyro:BAAANQAECgIIAgAAAA==.Washedzebu:BAABNQAECoEZAAMRAAcK+ReuGgAUAgARAAcK+ReuGgAUAgAOAAUKVw4QKQAgAQAAAA==.Watsatotem:BAAANQAECgEJAQAAAA==.Wayfairkid:BAAANQAECgEIAQAAAA==.',
We='Weeb:BAACNQAFFIEXAAIfAAcKPR9HAADMAgAfAAcKPR9HAADMAgA1AAQKgSEAAx8ACQqtJlcAAM4DAB8ACQqtJlcAAM4DABMACAqQGjUOACgCAAAA.',
Wh='Whiterabbitt:BAAANQADCggIKAAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQADCggJDgAAAA==.Wilmabfiymr:BAAANQAECgEIAQAAAA==.',
Wo='Woa:BAAANQADCggIEgAAAA==.Woofwoofwoof:BAAANQAECgQJBQAAAA==.',
Wr='Writhe:BAAANQABCgQICAABNQAFFAYICgAgAF4iAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Ye='Yeeloow:BAAANQADCgYIDQAAAA==.',
Ys='Yshaarj:BAAANQADCggIEgAAAA==.',
Yu='Yulok:BAACNQAFFIEKAAIgAAYKXiItAABjAgAgAAYKXiItAABjAgA1AAQKgRwAAiAACQqVJlMAAOwDACAACQqVJlMAAOwDAAAA.Yuukí:BAAANQADCggICAABNQAECgkJHQAHAAMeAA==.',
['Yú']='Yúúki:BAAANQAECgYICwABNQAECgkJHQAHAAMeAA==.',
Za='Zaberra:BAAANQAECgcIEAAAAA==.Zanarkand:BAAANQAECgQJBwAAAA==.Zaphoof:BAAANQADCgQJBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zerofort:BAAANQAECgYIBgAAAA==.Zexexe:BAAANQAECgcIDQABNQAFFAYJEwAVAHYgAA==.',
Zi='Zibroth:BAAANQAECgYJDwAAAA==.Zieg:BAAANQAECgUJBQAAAA==.Zina:BAAANQAECgIIAgAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQAECgQJBgAAAA==.',
['Ýu']='Ýuuki:BAABNQAECoEdAAIHAAkKAx71HwDsAgAHAAkKAx71HwDsAgAAAA==.',
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
