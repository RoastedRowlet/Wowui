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

local lookup = {'Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Priest-Holy','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Druid-Guardian','DeathKnight-Blood','DeathKnight-Frost','Warrior-Arms','Warlock-Destruction','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Paladin-Protection','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','Monk-Windwalker','Warrior-Protection','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Fury','Rogue-Outlaw','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abhire:BAAANQAECgQIBgABNQAECgoKPAABAG0ZAA==.',
Ad='Advisor:BAACNQAFFH8GAAICAAMKrxiAFQDyAAACAAMKrxiAFQDyAAA1AAQKf0MAAwIACgpnI1kJAHYDAAIACgpnI1kJAHYDAAMAAQo0D/MrAT0AAAAA.',
Ae='Aedali:BAAANQAECgIIAgAAAA==.Aería:BAABNQAECn8gAAICAAkKIyCzHAD7AgACAAkKIyCzHAD7AgAAAA==.',
Ak='Akarm:BAAANQAECggICgAAAA==.',
Al='Alehae:BAAANQAECgEIAQAAAA==.Alyà:BAABNQAECn8hAAIEAAkKCBsUGwDuAgAEAAkKCBsUGwDuAgABNQAECgoKNQAFABMPAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECgoKPwAGAKQkAA==.',
Ap='Aparajita:BAABNQAECn86AAIHAAoKiyCPIQD+AgAHAAoKiyCPIQD+AgABNQAECgQIBQAIAAAAAA==.Aphrodite:BAABNQAECn8vAAQEAAoKixwFJQDYAgAEAAoKixwFJQDYAgAJAAMKdAmZPgCiAAAKAAEKfwpSGQAvAAAAAA==.',
Ar='Arianda:BAABNQAECn9IAAILAAoKECSvAgBIAwALAAoKECSvAgBIAwAAAA==.Aristoleh:BAAANQAECggIEQABNQAFFAMICAADAKoMAA==.Armagedonn:BAAANQADCgQIBAAAAA==.Arolder:BAABNQAECn9AAAMMAAoKWyTWCAD3AgANAAoKhyLhEAAIAwAMAAoKliLWCAD3AgAAAA==.Artemis:BAAANQABCgYIBgABNQAECgoKLwAEAIscAA==.',
As='Astayuno:BAABNQAECn8UAAIHAAYKxgbkvgDAAAAHAAYKxgbkvgDAAAAAAA==.',
At='Atoadaso:BAABNQAECn8oAAIOAAoKDRpaOgBJAgAOAAoKDRpaOgBJAgAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQAECgQIBAAIAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECn81AAQFAAoKEw/DBwAcAgAFAAoKkwvDBwAcAgAHAAcKgA+2cwBrAQAPAAEKxQ79MgA7AAAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQAECgIIAwAAAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgMIBQAAAA==.Bankus:BAAANQAECgMIAwAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECn8hAAMQAAgKNxmqWgBpAQAQAAYKdxSqWgBpAQARAAUK3AibTgCsAAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYIDQAAAA==.',
Bl='Blasphemar:BAAANQADCgUICQAAAA==.Blinkz:BAAANQAECgEIAQAAAA==.Blåde:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.',
Bo='Bogarash:BAAANQAECgEIBgAAAA==.Boneycheese:BAAANQAECgIIAgABNQAECgoKIQAEAOAPAA==.Boombástic:BAABNQAECn87AAMRAAoK1BXKHQD2AQARAAkKaRTKHQD2AQAQAAYKJQj3egDfAAAAAA==.Boomco:BAABNQAECn8/AAISAAoKlQ4ZZgDfAQASAAoKlQ4ZZgDfAQAAAA==.Bordinn:BAAANQADCgIIAgAAAA==.',
Br='Bravillius:BAAANQADCggIJQAAAA==.Breeti:BAAANQAECgUIDAAAAA==.Broin:BAAANQAECgIIAwAAAA==.Bryda:BAAANQAECggICgAAAA==.',
Bu='Bubblecreep:BAAANQAECggIDgAAAA==.Burblingbee:BAAANQAECgQIBQAAAA==.Burtangus:BAABNQAECn8wAAQHAAoKZRdvLgBGAgAHAAoKLBdvLgBGAgAFAAIKzRNTGwCLAAAPAAIKrwo7KABUAAAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQAECgEIAgABNQAECgIIAwAIAAAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAABNQAECn8yAAITAAgK5R2uDADzAQATAAgK5R2uDADzAQAAAA==.Calyssa:BAABNQAECn8/AAMUAAoKZB2qPABmAgAUAAoKZB2qPABmAgAVAAkK3hCEFgCyAQAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQAECgcIDQAIAAAAAA==.Capybara:BAAANQAECggIEQABNQAFFAcICQAVANobAA==.Carpe:BAAANQAECgEIAgAAAA==.Cartan:BAACNQAFFH8JAAIWAAMKJxHcBgDVAAAWAAMKJxHcBgDVAAA1AAQKf0gAAhYACgrbH4cFADQDABYACgrbH4cFADQDAAAA.Castisteus:BAAANQAECgEIAQAAAA==.Cathum:BAAANQAECgcIBwAAAA==.',
Ch='Charizaardx:BAACNQAFFH8TAAIXAAUKnQ+hBwAPAQAXAAUKnQ+hBwAPAQA1AAQKf2cAAhcACgqzHmwDALcCABcACgqzHmwDALcCAAAA.Chromeski:BAABNQAECn8fAAIBAAoKZQ90dgCuAQABAAoKZQ90dgCuAQAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAABNQAECn8rAAIOAAoKaxQKWwDaAQAOAAoKaxQKWwDaAQAAAA==.',
Co='Cowdeath:BAAANQAECgEIAQAAAA==.',
Cr='Creedz:BAAANQAECgMIAwAAAA==.Creepymage:BAAANQAECgcIDQABNQAECggIDgAIAAAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crys:BAAANQADCggICAAAAA==.Crystalys:BAABNQAECn8YAAIGAAcKfQV7HgD4AAAGAAcKfQV7HgD4AAAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECn8aAAIYAAkKdxaIQAC6AQAYAAkKdxaIQAC6AQAAAA==.',
Da='Dalna:BAABNQAECn8wAAMWAAgK4g/RFwBsAQAWAAgK4g/RFwBsAQAZAAUK7wcYTQDDAAAAAA==.Dandaril:BAAANQADCgIIAgAAAA==.Danksoul:BAAANQAECgIIAwABNQAECggIEQAIAAAAAA==.Darkderek:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.Darklürker:BAABNQAECn8hAAISAAgKoQeAjwB7AQASAAgKoQeAjwB7AQAAAA==.Darksaber:BAAANQADCggIIQAAAA==.Darkwi:BAABNQAECn8rAAMPAAkK1hAOHwB2AQAHAAcKSw+EkAC9AQAPAAYKqREOHwB2AQAAAA==.Dasthodan:BAAANQAECgQICAABNQAECgoKHwABAGUPAA==.Dayne:BAAANQAECgYICAAAAA==.Dayus:BAAANQAECgMIAQAAAA==.',
Dc='Dctrpepper:BAAANQAECgQIBQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgkJGgAYAHcWAA==.Deathby:BAABNQAECn8cAAMOAAUKPgPOHAGiAAAOAAUKPgPOHAGiAAAaAAEKAADfRgAoAAAAAA==.Deathcore:BAAANQAECgEIAQAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECn85AAQRAAoK2gZzMwA8AQARAAoK2gZzMwA8AQAQAAUKxAANiwAqAAAbAAEKAADqTgAYAAAAAA==.Deldawalth:BAAANQAECgYICAAAAA==.Delvisprezly:BAAANQABCgYIBgABNQAECgcIDQAIAAAAAA==.Demonica:BAABNQAECn8zAAQcAAoK6wieEQAYAQAcAAoKDgeeEQAYAQAYAAgKVAkHSwDlAAAdAAMKcATfXACGAAAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAABNQAECn8aAAQPAAkKkxSdEwCxAAAFAAcKJRJmEAAWAQAHAAYKKg3A3wAKAQAPAAYKExCdEwCxAAAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECn9EAAIUAAoKVBQdXAALAgAUAAoKVBQdXAALAgAAAA==.Dionysos:BAAANQABCgQIBAAAAA==.',
Do='Dominoes:BAABNQAECn8nAAISAAkKAhMPcgDAAQASAAkKAhMPcgDAAQAAAA==.Dotho:BAAANQAECggIAwAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Dragonzord:BAAANQADCggIFwAAAA==.Drakth:BAAANQAECgEIAQAAAA==.',
Du='Dummblond:BAABNQAECn8cAAMQAAgKtgjfVgB7AQAQAAgKtgjfVgB7AQARAAMK6gQGZQByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECn80AAILAAoK/xzRCQCSAgALAAoK/xzRCQCSAgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBwAIAAAAAA==.',
Ec='Eclamp:BAAANQAECgEIAQAAAA==.',
Eg='Ego:BAABNQAECn8yAAIeAAkKgCDjHAAAAwAeAAkKgCDjHAAAAwAAAA==.',
Ei='Eiduartplis:BAAANQAECggIEwABNQAFFAQICAASAGoXAA==.',
El='Ellaana:BAAANQAECgQIBgAAAA==.Ellee:BAAANQAECgQIBQAAAA==.Elotarra:BAAANQAECgQIBAAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faema:BAAANQAECgQIBAAAAA==.Faethe:BAAANQADCgIIAgABNQAECgoKPwAGAKQkAA==.Fananabanana:BAABNQAECn8YAAIFAAkKbQ5jDQCEAQAFAAkKbQ5jDQCEAQABNQAECgoKIQAEAOAPAA==.',
Fe='Fenrith:BAAANQABCgQIBAAAAA==.Feorarlia:BAAANQADCgQIBAABNQAECgoKIQAEAOAPAA==.',
Fi='Figaro:BAAANQAECgUICAABNQAECgkJHQAfABQgAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECn8lAAIBAAcKHROT2gDSAQABAAcKHROT2gDSAQAAAA==.',
Fl='Flameheart:BAAANQAECgUIDQAAAA==.Fleathulhu:BAABNQAECn8+AAIEAAoKIBnrJgCgAgAEAAoKIBnrJgCgAgAAAA==.Flungpu:BAAANQADCggIMgABNQAECgkJMwASACMMAA==.',
Fo='Fostock:BAAANQAECgMIBQAAAA==.',
Fr='Frobenius:BAABNQAECn8hAAIEAAkKYxpoJQCpAgAEAAkKYxpoJQCpAgABNQAFFAMICQAWACcRAA==.Frostmoon:BAAANQABCgcIDQAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Gangsta:BAAANQAECgIIAgAAAA==.Garwynn:BAABNQAECn9CAAITAAoKgBadFQB1AQATAAoKgBadFQB1AQAAAA==.',
Gh='Ghostkev:BAABNQAECn8wAAMSAAoKWR3MLQDkAgASAAoKWR3MLQDkAgAfAAQKjQiNXACzAAAAAA==.Ghoulmaxing:BAAANQADCgEIAgABNQAECgoKRwAOAE8iAA==.',
Gl='Glaistia:BAAANQAECgEIAQAAAA==.Glen:BAAANQAECgQIBgAAAA==.Glowstik:BAAANQAECgMIAwAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECn80AAIgAAoKGx/hBwD9AgAgAAoKGx/hBwD9AgAAAA==.Hankmoodie:BAABNQAECn8jAAIOAAoK3woyagCsAQAOAAoK3woyagCsAQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.Haranda:BAAANQADCgcIBwAAAA==.Harmoni:BAAANQAECgMIAwABNQAECgoKPwAGAKQkAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgMIBQAAAA==.Hexlight:BAAANQAECggICAAAAA==.',
Ho='Holysim:BAAANQAECgIIAgAAAA==.Honir:BAABNQAECn83AAIVAAoKKx+LCQCUAgAVAAoKKx+LCQCUAgAAAA==.Horderolder:BAAANQAECgQIAwAAAA==.',
['Hâ']='Hâvoc:BAAANQAECgEIAgAAAA==.',
['Hü']='Hünter:BAAANQAECgEIBgAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECgoKPwAGAKQkAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECn8xAAMPAAoKyQwtBgBrAQAPAAkKDwwtBgBrAQAHAAkKzQfJvgBPAQAAAA==.Imooforu:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQAECgEIAQAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgYICwAAAA==.Jaen:BAAANQAECgUIBAABNQAECgoKPwAEAJEPAA==.Jamus:BAAANQAECgQIBwAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Jc='Jckruzy:BAAANQADCgIIAgAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQAECgEIAgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECn8zAAISAAkKIwy0kwDhAQASAAkKIwy0kwDhAQAAAA==.Kaelya:BAAANQAECgEIAQABNQAECgoKPwAUAGQdAA==.Kaladiin:BAABNQAECn8YAAIhAAcKewgfGQAQAQAhAAcKewgfGQAQAQAAAA==.Kallias:BAABNQAECn8+AAMeAAoK6SO7AwDhAwAeAAoK6SO7AwDhAwAUAAEKTAOnlgErAAAAAA==.Kandistars:BAABNQAECn8mAAIQAAcKNRMZTACzAQAQAAcKNRMZTACzAQAAAA==.Karite:BAABNQAECn88AAIiAAoKtyDZAADSAgAiAAoKtyDZAADSAgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Katte:BAAANQADCgMIAwAAAA==.Kaymyn:BAACNQAFFH8FAAIGAAIKzQIRCgBpAAAGAAIKzQIRCgBpAAA1AAQKfzsAAgYACgruEyYMAPoBAAYACgruEyYMAPoBAAAA.Kazar:BAAANQADCgUICgAAAA==.Kazen:BAAANQADCggIDgAAAA==.Kazenoth:BAAANQADCgUIBgAAAA==.',
Ke='Kehjistan:BAAANQAECgcIEgAAAA==.Kellement:BAAANQAECgEIAQAAAA==.Kennychaoss:BAABNQAECn84AAMCAAoK7hpYIQCfAgACAAoK7hpYIQCfAgADAAIKRQVd2ABSAAAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAABNQAECn8dAAISAAkKoA42ewCqAQASAAkKoA42ewCqAQAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Kobebrÿant:BAAANQABCgQIBAAAAA==.Koland:BAAANQADCgcIEQAAAA==.Kosseluna:BAABNQAECn8wAAIQAAgK0gcTQwAGAQAQAAgK0gcTQwAGAQAAAA==.Kostazu:BAABNQAECn81AAIDAAoKpA64PgDDAQADAAoKpA64PgDDAQAAAA==.',
La='Laity:BAAANQAECgcIEwAAAA==.Lazariir:BAAANQAECggIEgAAAA==.Lazkal:BAAANQAECgcIDAAAAA==.',
Le='Lebesgue:BAABNQAECn84AAMCAAoKMRrmLgBQAgACAAoKMRrmLgBQAgADAAIKcgRR2gBOAAABNQAFFAMICQAWACcRAA==.Lebigmu:BAABNQAECn8qAAIgAAoK9hy7CACJAgAgAAoK9hy7CACJAgAAAA==.Leelee:BAAANQAECgYICwAAAA==.',
Li='Lilbones:BAAANQADCgUIBQABNQAECgoKRwAOAE8iAA==.Lisettar:BAAANQAECgcICwAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECggIDgAIAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYIDAABNQAECgcIBgAIAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAIAAAAAA==.Luralia:BAAANQAECgUICQAAAA==.',
Ly='Lycanbyte:BAAANQAECgQIBAAAAA==.Lylith:BAABNQAECn83AAIdAAoKAhPKHACtAQAdAAoKAhPKHACtAQAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Maddicollins:BAAANQAECgcIDgABNQAFFAIIBQAUAFIOAA==.Magdalena:BAABNQAECn8iAAISAAcKXgnLtQArAQASAAcKXgnLtQArAQAAAA==.Magegrumpy:BAAANQADCggICQAAAA==.Maghavik:BAAANQADCgMIAwAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magmaface:BAAANQAECgYIDAAAAA==.Magnólia:BAABNQAECn82AAICAAoKjyEHFAAFAwACAAoKjyEHFAAFAwAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQAECgQIBgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgYIDAAAAA==.Maribelle:BAAANQAECgQICQABNQAECgoKPwAGAKQkAA==.Masha:BAAANQAECgEIAQAAAA==.Mattdemòn:BAAANQAECgEIAgABNQAECgUIBwAIAAAAAA==.Maximander:BAAANQAECgUICgAAAA==.',
Me='Melomel:BAAANQAECgMIBQAAAA==.Melonsquezer:BAABNQAECn81AAIVAAoKax4mDQBHAgAVAAoKax4mDQBHAgAAAA==.Menmei:BAAANQAECgMIBQAAAA==.Meow:BAAANQAECgQIBgAAAA==.Meowmix:BAAANQAECgEIAwAAAA==.Merphia:BAAANQAECgEIAQAAAA==.Meygen:BAABNQAECn8cAAIJAAkK0AVFQgAgAQAJAAkK0AVFQgAgAQAAAA==.',
Mi='Milkman:BAAANQAECgEIAQABNQAECggIIgAUAFEfAA==.Minbyunggyu:BAAANQADCgIIAwAAAA==.Minien:BAABNQAECn8oAAIgAAoKYRcaEQBYAgAgAAoKYRcaEQBYAgAAAA==.Minko:BAAANQAECgEIAwAAAA==.Minore:BAAANQAECggIEAAAAA==.',
Mo='Moa:BAABNQAECn8jAAMQAAoKKRJTIgDVAQAQAAoKKRJTIgDVAQALAAQKCQgGSACPAAABNQAECgoKNQAFABMPAA==.Moneybadger:BAAANQAECgEIAQAAAA==.Moonshot:BAABNQAECn9EAAMfAAoKUReeEAAmAgAfAAoKDhWeEAAmAgASAAYKQhMShwCOAQAAAA==.Moortz:BAAANQAECgIIBQABNQAECgoKNAAfAHsiAA==.Morillic:BAABNQAECn8vAAQFAAoKfxeTBACQAgAFAAkK/xeTBACQAgAPAAMK8RNUQADBAAAHAAUKcg6zEAGqAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAABNQAECn8ZAAIHAAoKmhNBPQAPAgAHAAoKmhNBPQAPAgAAAA==.',
My='Myros:BAABNQAECn81AAMGAAoKUxhQCAAUAgAGAAoKJhdQCAAUAgABAAYKfxP3CAF+AQAAAA==.',
Na='Nadiaa:BAAANQADCggIFwAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgMIBgABNQAECgoKNQAGAFMYAA==.Narestor:BAABNQAECn8XAAMOAAoKzwl+kQBJAQAOAAkKnwp+kQBJAQAhAAMKXwXpJQBmAAABNQAFFAQIBwAjAFwFAA==.Nazervis:BAACNQAFFH8RAAMXAAUKohzYAwCkAQAXAAUKohzYAwCkAQAjAAEKGQHaGgAyAAA1AAQKfyoAAxcACgokJG4FADsDABcACgokJG4FADsDACQAAQrbH3IhAEsAAAE1AAUUCAgKACUAUQ0A.',
Ne='Nekopunch:BAAANQAECgUJBgAAAA==.Nelcor:BAABNQAECn8lAAIjAAgKUg6yFACSAQAjAAgKUg6yFACSAQAAAA==.Nemesîs:BAAANQADCggICAAAAA==.Neudru:BAAANQAECgEIAgAAAA==.Newhealer:BAABNQAECn8hAAMEAAoK4A/bcwBnAQAEAAoK4A/bcwBnAQAKAAIKTQWXIwBMAAAAAA==.',
No='Noint:BAABNQAECn8bAAINAAcK9AcRYgAcAQANAAcK9AcRYgAcAQAAAA==.Nortree:BAAANQAECgMIBQAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECn8rAAMXAAcK2Bp6EQA8AgAXAAcK2Bp6EQA8AgAkAAQKGhYwEwD9AAAAAA==.',
Ny='Nymue:BAABNQAECn8tAAMDAAgKOBA1ewCxAQADAAgKOBA1ewCxAQAgAAEKAAB2OQApAAAAAA==.Nyyrivik:BAAANQADCgcIDwAAAA==.',
Nz='Nzoth:BAAANQAECgEIAQAAAA==.',
Ob='Obabo:BAAANQAECgEIAQAAAA==.',
Oc='Octapie:BAABNQAECn84AAICAAoKbxVDQQD4AQACAAoKbxVDQQD4AQAAAA==.',
Oh='Ohitsadragon:BAABNQAECn8iAAIXAAoKZA1TCwCYAQAXAAoKZA1TCwCYAQAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAABNQAECn8dAAIBAAUKAgvyTAEPAQABAAUKAgvyTAEPAQAAAA==.Orcburger:BAAANQAECgcICAAAAA==.Oreoscruunit:BAAANQAECgcIDQAAAA==.Ormil:BAAANQAECgEIAQAAAA==.',
Os='Oscuridad:BAABNQAECn8bAAIHAAYKVAN5AgHHAAAHAAYKVAN5AgHHAAAAAA==.',
Ow='Owl:BAABNQAECn8oAAIFAAoKhQeJDACYAQAFAAoKhQeJDACYAQAAAA==.Owlcatraz:BAACNQAFFH8IAAIQAAcKjAXxEwArAQAQAAcKjAXxEwArAQA1AAQKf0MAAhAACQo3IHESADQDABAACQo3IHESADQDAAAA.',
Pa='Paendrag:BAAANQAECgQIBAAAAA==.Paladinna:BAAANQADCgQIBAAAAA==.Panteragon:BAAANQAECgMIBQAAAA==.Panthean:BAABNQAECn8YAAIEAAcKviCSTADxAQAEAAcKviCSTADxAQAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgMIBQAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECn8+AAIEAAoKBxb9LgB0AgAEAAoKBxb9LgB0AgAAAA==.Persaud:BAABNQAECn8ZAAMPAAgKpiBKFwCyAQAHAAcK/R4iXABDAgAPAAUK6x9KFwCyAQAAAA==.Pettacular:BAABNQAECn83AAISAAoK7hVYVAAMAgASAAoK7hVYVAAMAgAAAA==.',
Ph='Phidra:BAABNQAECn88AAMCAAoKiAruUwCsAQACAAoKiAruUwCsAQADAAYKxAHs8gCvAAAAAA==.',
Po='Poprocks:BAAANQAECgIIAwAAAA==.Potatogg:BAAANQAECgQICwAAAA==.',
Pr='Predatorc:BAABNQAECn8gAAISAAgKAgiHwgB9AQASAAgKAgiHwgB9AQAAAA==.Primevil:BAABNQAECn8WAAMVAAgKPg3EMwBFAQAVAAYKqBDEMwBFAQAUAAgKyAXL0wAbAQAAAA==.Primevl:BAABNQAECn8zAAIQAAoK3hD+IQDYAQAQAAoK3hD+IQDYAQAAAA==.',
Py='Pyrissa:BAAANQABCgYIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Qu='Quarz:BAAANQADCgIIAgAAAA==.',
Ra='Radïance:BAABNQAECn8fAAMUAAkK9wmbuABKAQAUAAkK9wmbuABKAQAVAAEKAADxegAAAAAAAA==.Raediant:BAABNQAECn8fAAIVAAoKkBIdKwCEAQAVAAoKkBIdKwCEAQAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Rahvinwulf:BAAANQADCgQIBAAAAA==.Raquel:BAABNQAECn8gAAICAAgKvgIHuwD1AAACAAgKvgIHuwD1AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBQAAAA==.Rectaltremor:BAAANQADCgYIBgAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEgAIAAAAAA==.Reign:BAAANQAECgEIAQABNQAECgoKNQAFABMPAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBwAIAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECn85AAIYAAoK4hSGHAAWAgAYAAoK4hSGHAAWAgAAAA==.Ris:BAABNQAECn9AAAMGAAoKvBmNDQCgAQABAAkK5BbFbQDEAQAGAAYK7hiNDQCgAQAAAA==.Ritami:BAABNQAECn8dAAIfAAkKFCBwFgCoAgAfAAkKFCBwFgCoAgAAAA==.',
Ro='Roffy:BAABNQAECn84AAIeAAoKTBPqNgAtAgAeAAoKTBPqNgAtAgAAAA==.Roknathar:BAABNQAECn80AAMfAAoKeyIIBwBfAwAfAAoKeyIIBwBfAwASAAEKAABdUQFBAAAAAA==.',
Ru='Ruitiny:BAAANQAECgEIAQAAAA==.',
Sa='Saerin:BAABNQAECn8UAAIBAAgKWxv1iQBrAgABAAgKWxv1iQBrAgAAAA==.Saintmedes:BAAANQAECgQICQAAAA==.Sangoma:BAAANQADCggIDwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.Saxmaster:BAAANQAECgIIAgAAAA==.',
Se='Sechiwa:BAAANQAECgEIAQAAAA==.Sedo:BAAANQAECgMIBgAAAA==.Sehlia:BAABNQAECn9BAAIHAAoKuBVIRgDwAQAHAAoKuBVIRgDwAQAAAA==.Selarae:BAAANQAECggIDQABNQAECgkJHQAfABQgAA==.Selenis:BAAANQAECgYICwABNQAECgoKPgAMALklAA==.Seraphyne:BAAANQAECgEIAQABNQAECgUIEwAIAAAAAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAABNQAECn8UAAINAAgK0QXrYgD2AAANAAgK0QXrYgD2AAAAAA==.Shadowwizard:BAABNQAECn8UAAIBAAgKUBchsgAfAgABAAgKUBchsgAfAgABNQAECggIIgAUAFEfAA==.Shadygrove:BAAANQABCgEIAQABNQAECgoKNgACAI8hAA==.Shamania:BAAANQAECgcIDgABNQAECggIDgAIAAAAAA==.Shaomai:BAABNQAECn8sAAMDAAoK1hyuawDdAQADAAYKoB2uawDdAQACAAoKGxl/bwC9AQABNQAFFAUIEAABAJgiAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAAANQAECggIEQABNQAECgoKLwAEAIscAA==.Shidandfard:BAABNQAECn8xAAIBAAoKGCGQMwAjAwABAAoKGCGQMwAjAwAAAA==.Shifte:BAABNQAECn9EAAIbAAoKBxXlCwD2AQAbAAoKBxXlCwD2AQAAAA==.Shishkä:BAAANQAECggIDQAAAA==.Shiv:BAAANQADCggIFgABNQAECgIIAgAIAAAAAA==.Shockabeotch:BAABNQAECn8WAAIDAAgK7Qu/mABnAQADAAgK7Qu/mABnAQAAAA==.Shy:BAAANQAECgcIEgABNQAECgoKLwAEAIscAA==.Shêrra:BAAANQADCgEIAQAAAA==.',
Si='Silverwin:BAAANQAECgMIBQAAAA==.',
Sk='Skorvrax:BAAANQAECgUIEAAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAFFAIIAgAAAA==.Slimage:BAABNQAECn8zAAIBAAoKfhhVlwBSAgABAAoKfhhVlwBSAgAAAA==.Slushius:BAAANQAECgEIAQAAAA==.',
Sm='Smashufacein:BAAANQAECgIIAgAAAA==.Smiteclub:BAAANQAECgEIAQAAAA==.Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAABNQAECn83AAIVAAoKgw9hGQCSAQAVAAoKgw9hGQCSAQAAAA==.',
Sp='Spaarkle:BAABNQAECn8YAAIQAAcKjgwzTADbAAAQAAcKjgwzTADbAAAAAA==.Spectrehawk:BAAANQAECgEIAwABNQAFFAMICAAMAJYaAA==.Speçtre:BAACNQAFFH8IAAIMAAMKlhpBEwDDAAAMAAMKlhpBEwDDAAA1AAQKfy4AAgwACQrOIUoZAOMCAAwACQrOIUoZAOMCAAAA.',
St='Stheris:BAAANQADCgYJBgABNQAFFAQIBwAjAFwFAA==.',
Su='Supak:BAAANQAECgQIBgAAAA==.Suppabad:BAABNQAECn88AAIWAAoK2RpnCgCKAgAWAAoK2RpnCgCKAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgQIBgABNQAECgoKPwAGAKQkAA==.Tadlight:BAAANQAECgMIBgAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tarysha:BAABNQAECn8UAAImAAkKCghvZgBYAQAmAAkKCghvZgBYAQAAAA==.Tattooman:BAAANQABCgIIAQAAAA==.Tayoma:BAAANQABCgYICgAAAA==.Tazara:BAAANQAECgYICQAAAA==.Tazmaniaa:BAAANQADCggIDgAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEgAAAA==.Ted:BAABNQAECn84AAIDAAoKRR0hHgBwAgADAAoKRR0hHgBwAgAAAA==.Tehnegev:BAABNQAECn8UAAImAAcK7xHBVQCRAQAmAAcK7xHBVQCRAQABNQAECgoKIgAUAIoZAA==.Tehzealza:BAAANQAECgMIAwABNQAECgoKIgAUAIoZAA==.Teias:BAAANQAECgUIBgABNQAFFAMICAAEADsRAA==.Temptressxx:BAAANQAECgUJDwAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAABNQAECn8YAAIEAAcKMhdLYgCiAQAEAAcKMhdLYgCiAQABNQAECgkJGQAZAFQdAA==.Themage:BAAANQADCggICAAAAA==.Thokmay:BAAANQAECgIIAgAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQAECgQICwAAAA==.',
Ti='Tiandrinna:BAABNQAECn8/AAMnAAoKEBoCAgBVAgAnAAoKyBkCAgBVAgABAAoK0BS6VAAFAgAAAA==.Tightywhitey:BAAANQABCgYIBwAAAA==.Tigirius:BAAANQAECgMIBAAAAA==.Timkaoss:BAAANQAECgEIAwAAAA==.Timmyjudge:BAAANQAECgUICQAAAA==.Tirinia:BAAANQAECgEIAgAAAA==.',
Tm='Tmagnet:BAAANQAECgMIBQAAAA==.',
To='Tophats:BAAANQAECgEIAQAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQAECgEIAQAAAA==.Tourmaline:BAAANQAECgIIBgABNQAECgoKNgACAI8hAA==.Toyoma:BAAANQABCgIIBAAAAA==.',
Tr='Trancepants:BAAANQAECggICQAAAA==.Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQADCggIDgAAAA==.',
Tw='Tweedildee:BAACNQAFFH8JAAIGAAMK8RI9AwDcAAAGAAMK8RI9AwDcAAA1AAQKfz0AAgYACgrkGcQFAGMCAAYACgrkGcQFAGMCAAAA.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECggIDgAIAAAAAA==.Unkindled:BAABNQAECn8iAAIUAAgKUR+cVAAeAgAUAAgKUR+cVAAeAgAAAA==.',
Va='Valdor:BAABNQAECn81AAINAAoKCRHnOADxAQANAAoKCRHnOADxAQAAAA==.Valicous:BAAANQAECgQIBAAAAA==.Vandalie:BAAANQAECgQIBwABNQAECgkJGgAlACogAA==.Vaskie:BAEANQAECgcIDAABNQAFFAYIEgAOAHsUAA==.Vaylorian:BAABNQAECn8mAAILAAkKaiaJAAD4AwALAAkKaiaJAAD4AwAAAA==.',
Ve='Velion:BAAANQAECgYIDQAAAA==.Vellathor:BAAANQADCgQIBQABNQAECgoKHwABAGUPAA==.Velocity:BAABNQAECn8rAAMOAAoKdRr1OABOAgAOAAoKWBr1OABOAgAhAAUKiRwBEwBxAQAAAA==.Verianna:BAABNQAECn8+AAMMAAoKuSXaBAA0AwAMAAoKuSXaBAA0AwAlAAYKVxRCcwBKAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgoKNQAFABMPAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAACNQAFFH8QAAIBAAUKmCLJFQAsAQABAAUKmCLJFQAsAQA1AAQKfycAAgEACgq4JF8MACADAAEACgq4JF8MACADAAAA.',
Vu='Vulpixen:BAAANQAECggIDwAAAA==.',
Wa='Wadumu:BAAANQAECgYIEQAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgMIBQAAAA==.',
Wi='Willothewisp:BAAANQADCgUIBQAAAA==.Willowy:BAABNQAECn8/AAIGAAoKpCSGAQAeAwAGAAoKpCSGAQAeAwAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECn88AAIOAAoKcws0bACnAQAOAAoKcws0bACnAQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xanda:BAABNQAECn8YAAIOAAkK1Aw9dgCMAQAOAAkK1Aw9dgCMAQAAAA==.Xantyr:BAAANQAECgYIDAAAAA==.',
Ya='Yarman:BAAANQAECgMIBQAAAA==.',
Yo='Yojimbro:BAAANQAECgUIDQAAAA==.Yoshial:BAAANQAECgMIBgAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgUIBwAAAA==.Zalantir:BAAANQAECggIEgABNQAFFAYIDwAfALgWAA==.Zariski:BAAANQAECgYICwABNQAFFAMICQAWACcRAA==.Zarthus:BAAANQAECgUICQAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECn8iAAIUAAoKihl+ewDCAQAUAAoKihl+ewDCAQAAAA==.',
Zi='Zirl:BAAANQAECgEIAwABNQAFFAYIDwAfALgWAA==.Ziyn:BAACNQAFFH8PAAMfAAYKuBZqDwDPAAAfAAQKOhVqDwDPAAASAAIKMBtGKABgAAA1AAQKf04AAxIACgq3JVcHAKIDABIACgqnJVcHAKIDAB8ACQp2G30VANsBAAAA.',
Zo='Zoplete:BAABNQAECn8fAAIBAAoKoxFzUAAQAgABAAoKoxFzUAAQAgAAAA==.',
Zy='Zyp:BAAANQAECgEIAgAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAABNQAECn8VAAIHAAkKvgaDlQAaAQAHAAkKvgaDlQAaAQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQAECgEIAgAAAA==.',
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
