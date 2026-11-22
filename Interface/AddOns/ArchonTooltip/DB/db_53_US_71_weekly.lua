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

local lookup = {'Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Priest-Holy','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Druid-Guardian','DeathKnight-Blood','DeathKnight-Frost','Warrior-Arms','Warlock-Destruction','Paladin-Retribution','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','Monk-Windwalker','Warrior-Protection','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Fury','Rogue-Outlaw','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abhire:BAAANQAECgQIBQABNQAECgoKPwABAHUaAA==.',
Ad='Advisor:BAACNQAFFH8GAAICAAMKrxgEGADxAAACAAMKrxgEGADxAAA1AAQKf0MAAwIACgpnI1kJAHYDAAIACgpnI1kJAHYDAAMAAQo0D/MrAT0AAAAA.',
Ae='Aedali:BAAANQAECgIIAgAAAA==.Aería:BAABNQAECn8gAAICAAkKIyCzHAD7AgACAAkKIyCzHAD7AgAAAA==.',
Ak='Akarm:BAAANQAECggICQAAAA==.',
Al='Alyà:BAABNQAECn8iAAIEAAoK5hh5FwAbAwAEAAoK5hh5FwAbAwABNQAECgoKNQAFABMPAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECgoKQwAGAPMkAA==.',
Ap='Aparajita:BAABNQAECn86AAIHAAoKiyCPIQD+AgAHAAoKiyCPIQD+AgABNQAECgQIBQAIAAAAAA==.Aphrodite:BAABNQAECn8vAAQEAAoKixwFJQDYAgAEAAoKixwFJQDYAgAJAAMKdAnzQgCiAAAKAAEKfwriGgAvAAAAAA==.',
Ar='Arianda:BAABNQAECn9JAAILAAoKECTqAgBGAwALAAoKECTqAgBGAwAAAA==.Aristoleh:BAAANQAECggIDwABNQAFFAMICAADAKoMAA==.Armagedonn:BAAANQADCgQIBAAAAA==.Arolder:BAABNQAECn9EAAMMAAoKwySHBwAQAwAMAAoK1yOHBwAQAwANAAoKhyLhEAAIAwAAAA==.Artemis:BAAANQABCgYIBgABNQAECgoKLwAEAIscAA==.',
As='Astayuno:BAABNQAECn8VAAIHAAcKYAYVtADrAAAHAAcKYAYVtADrAAAAAA==.',
At='Atoadaso:BAABNQAECn8oAAIOAAoKDRq/PwBEAgAOAAoKDRq/PwBEAgAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQAECgQIBAAIAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECn81AAQFAAoKEw/DBwAcAgAFAAoKkwvDBwAcAgAHAAcKgA8afQBoAQAPAAEKxQ6VNQA7AAAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQAECgIIAQAAAA==.Azraella:BAAANQAECgIIAgABNQAECgoKRgAQALwdAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgUICgAAAA==.Bankus:BAAANQAECgQIBwAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECn8hAAMRAAgKNxmqWgBpAQARAAYKdxSqWgBpAQASAAUK3Ai2UwCrAAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYIDQAAAA==.',
Bj='Björn:BAAANQADCggIEAAAAA==.',
Bl='Blasphemar:BAAANQADCgUICQAAAA==.Blinkz:BAAANQAECgEIAQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boneycheese:BAAANQAECgIIAgABNQAECgoKIgAEAOAPAA==.Boombástic:BAABNQAECn87AAMSAAoK1BXrIADzAQASAAkKaRTrIADzAQARAAYKJQj3egDfAAAAAA==.Boomco:BAABNQAECn8/AAITAAoKlQ4lcQDeAQATAAoKlQ4lcQDeAQAAAA==.Bordinn:BAAANQADCgIIAgAAAA==.',
Br='Bravillius:BAAANQAECgMIAwAAAA==.Breeti:BAAANQAECgYIDQAAAA==.Broin:BAAANQAECgMIBAAAAA==.Bryda:BAAANQAECggICgAAAA==.',
Bu='Bubblecreep:BAAANQAECggIDgAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Burtangus:BAABNQAECn8zAAQHAAoKYhlWLABdAgAHAAoK0RhWLABdAgAFAAIKpxWZHACUAAAPAAIKrwqhKgBUAAAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQAECgEIAQABNQAECgMIBAAIAAAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAABNQAECn80AAIUAAkKMB5TCQBNAgAUAAkKMB5TCQBNAgAAAA==.Calyssa:BAABNQAECn9GAAMQAAoKvB3cPwBqAgAQAAoKvB3cPwBqAgAVAAkK3hCxGACxAQAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQAECgMIAwABNQAECggIEAAIAAAAAA==.Capybara:BAAANQAECggIEAABNQAFFAcICQAVANobAA==.Cartan:BAACNQAFFH8JAAIWAAMKJxGyBwDUAAAWAAMKJxGyBwDUAAA1AAQKf0gAAhYACgrbHxwGADADABYACgrbHxwGADADAAAA.Castisteus:BAAANQADCggICQAAAA==.Cathelina:BAAANQAECgEIAgAAAA==.Cathum:BAAANQAECggICgAAAA==.',
Ch='Charizaardx:BAACNQAFFH8TAAIXAAUKnQ+hBwAPAQAXAAUKnQ+hBwAPAQA1AAQKf20AAhcACgqzHr0DALYCABcACgqzHr0DALYCAAAA.Chromeski:BAABNQAECn8jAAIBAAoKKhLNcwDIAQABAAoKKhLNcwDIAQAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAABNQAECn8rAAIOAAoKaxTfYgDXAQAOAAoKaxTfYgDXAQAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQAECgMIAwAAAA==.Creepymage:BAAANQAECgcICgABNQAECggIDgAIAAAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crys:BAAANQADCggICAAAAA==.Crystalys:BAABNQAECn8aAAIGAAgKKAZ7HgD4AAAGAAgKKAZ7HgD4AAAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECn8aAAIYAAkKdxaIQAC6AQAYAAkKdxaIQAC6AQAAAA==.',
Da='Dalna:BAABNQAECn8yAAMWAAkKZQ/AFgCUAQAWAAkKZQ/AFgCUAQAZAAUK7wcYTQDDAAAAAA==.Dandaril:BAAANQADCgIIAgAAAA==.Danksoul:BAAANQAECgIIAwABNQAECgoKFAALANcUAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAABNQAECn8kAAITAAgKoQdbnQB5AQATAAgKoQdbnQB5AQAAAA==.Darksaber:BAAANQADCggIIQAAAA==.Darkwi:BAABNQAECn8rAAMPAAkK1hAOHwB2AQAHAAcKSw+EkAC9AQAPAAYKqREOHwB2AQAAAA==.Dasthodan:BAAANQAECgYICwABNQAECgoKIwABACoSAA==.Dayne:BAAANQAECgYIBwAAAA==.Dayus:BAAANQAECgMIAgAAAA==.',
Dc='Dctrpepper:BAAANQAECgQIBQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgkJGgAYAHcWAA==.Deathby:BAABNQAECn8cAAMOAAUKPgPOHAGiAAAOAAUKPgPOHAGiAAAaAAEKAADfRgAoAAAAAA==.Deathcore:BAAANQADCggIEAAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECn8/AAQSAAoKhgdsNgBDAQASAAoKhgdsNgBDAQARAAUKxACKkQAqAAAbAAEKAADqTgAYAAAAAA==.Deldawalth:BAAANQAECgYICAAAAA==.Delvisprezly:BAAANQABCgYIBgABNQAECggIEAAIAAAAAA==.Demonica:BAABNQAECn86AAQcAAoK6wgFEwAbAQAcAAoKOAcFEwAbAQAYAAgKVAlzUADiAAAdAAMKcATfXACGAAAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAABNQAECn8aAAQPAAkKkxR8FQCvAAAFAAcKJRIlEgAVAQAHAAYKKg3A3wAKAQAPAAYKExB8FQCvAAAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECn9EAAIQAAoKVBR3ZgAEAgAQAAoKVBR3ZgAEAgAAAA==.Dionysos:BAAANQAECgIIAgAAAA==.',
Do='Dominoes:BAABNQAECn8nAAITAAkKAhPrfQC/AQATAAkKAhPrfQC/AQAAAA==.Dotho:BAAANQAECggIAwAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Dragonzord:BAAANQAECgEIAQAAAA==.Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAABNQAECn8cAAMRAAgKtgjfVgB7AQARAAgKtgjfVgB7AQASAAMK6gQGZQByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECn80AAILAAoK/xzsCgCNAgALAAoK/xzsCgCNAgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgAIAAAAAA==.',
Ec='Eclamp:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn8yAAIeAAkKgCDjHAAAAwAeAAkKgCDjHAAAAwAAAA==.',
Ei='Eiduartplis:BAAANQAECggIEQABNQAFFAQICAATAGoXAA==.',
El='Elizabet:BAAANQAECgcIBwAAAA==.Ellaana:BAAANQAECgQIBgAAAA==.Ellee:BAAANQAECgQIBAAAAA==.Elotarra:BAAANQAECgQIBAAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.Exodiá:BAAANQAECgUIBQAAAA==.',
Fa='Faema:BAAANQAECgQIBAAAAA==.Faethe:BAAANQADCgIIAgABNQAECgoKQwAGAPMkAA==.Fananabanana:BAABNQAECn8ZAAIFAAkKbQ5jDQCEAQAFAAkKbQ5jDQCEAQABNQAECgoKIgAEAOAPAA==.',
Fe='Fenrith:BAAANQABCgQIBAAAAA==.Feorarlia:BAAANQADCgQIBAABNQAECgoKIgAEAOAPAA==.',
Fi='Figaro:BAAANQAECgUIBwABNQAECgkJHQAfABQgAA==.Finite:BAAANQADCgQIBAAAAA==.Firebaerd:BAAANQAECgYIBQAAAA==.Firewater:BAABNQAECn8lAAIBAAcKHROT2gDSAQABAAcKHROT2gDSAQAAAA==.',
Fl='Flameheart:BAAANQAECgUIBwAAAA==.Fleathulhu:BAABNQAECn9AAAIEAAoKgBkvKwCdAgAEAAoKgBkvKwCdAgAAAA==.Flungpu:BAAANQAECgQIAwABNQAECgoKNwATAKMMAA==.',
Fo='Fostock:BAAANQAECgUICgAAAA==.',
Fr='Frobenius:BAABNQAECn8hAAIEAAkKYxpIKgChAgAEAAkKYxpIKgChAgABNQAFFAMICQAWACcRAA==.Frostmoon:BAAANQABCgcIDQAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Gangsta:BAAANQAECgIIAgAAAA==.Garwynn:BAABNQAECn9CAAIUAAoKgBb+FgByAQAUAAoKgBb+FgByAQAAAA==.',
Gh='Ghostkev:BAABNQAECn8wAAMTAAoKWR3MLQDkAgATAAoKWR3MLQDkAgAfAAQKjQiNXACzAAAAAA==.Ghoulmaxing:BAAANQADCgEIAgABNQAECgoKRwAOAE8iAA==.',
Gl='Glaistia:BAAANQADCggIDAAAAA==.Glen:BAAANQAECgQIBgAAAA==.Glowstik:BAAANQAECgMIAwAAAA==.',
Gr='Grabmymelonz:BAAANQADCgIIAgAAAA==.Grisly:BAAANQAECgYIBgAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECn80AAIgAAoKGx/hBwD9AgAgAAoKGx/hBwD9AgAAAA==.Hankmoodie:BAABNQAECn8pAAIOAAoKJAtycACxAQAOAAoKJAtycACxAQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.Haranda:BAAANQADCgcIBwAAAA==.Harmoni:BAAANQAECgMIAwABNQAECgoKQwAGAPMkAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgUICgAAAA==.Hexlight:BAAANQAECggICAAAAA==.',
Ho='Holysim:BAAANQAECgIIAgAAAA==.Honir:BAABNQAECn86AAIVAAoKTB8nCQCtAgAVAAoKTB8nCQCtAgAAAA==.Horderolder:BAAANQAECgQIAwAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEIAQAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECgoKQwAGAPMkAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECn83AAMPAAoK3wwRBwBnAQAPAAkKDwwRBwBnAQAHAAoK0AdLowAQAQAAAA==.Imooforu:BAAANQADCgUJBgABNQADCgUIDAAIAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgcIDAAAAA==.Jaen:BAAANQAECgUIBAABNQAECgoKPwAEAJEPAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Jc='Jckruzy:BAAANQADCgIIAgAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcIEgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECn83AAITAAoKowy0kwDhAQATAAoKowy0kwDhAQAAAA==.Kaelya:BAAANQAECgEIAQABNQAECgoKRgAQALwdAA==.Kaladiin:BAABNQAECn8aAAIhAAgKJgkfGQAQAQAhAAgKJgkfGQAQAQAAAA==.Kallias:BAABNQAECn9HAAMeAAoK6SOEBADYAwAeAAoK6SOEBADYAwAQAAEKTAPnqAEqAAAAAA==.Kandistars:BAABNQAECn8mAAIRAAcKNRMZTACzAQARAAcKNRMZTACzAQAAAA==.Karite:BAABNQAECn9CAAIiAAoK4CGuAAD8AgAiAAoK4CGuAAD8AgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Katte:BAAANQADCgMIAwAAAA==.Kayleitha:BAAANQADCgEIAQABNQAECgoKRgAQALwdAA==.Kaymyn:BAACNQAFFH8IAAIGAAMKZgIWCACaAAAGAAMKZgIWCACaAAA1AAQKfz8AAgYACgruEyYMAPoBAAYACgruEyYMAPoBAAAA.Kazar:BAAANQADCgUICgAAAA==.Kazen:BAAANQAECgYIDgAAAA==.Kazenoth:BAAANQADCgUIBgAAAA==.',
Ke='Kehjistan:BAAANQAECggIDwAAAA==.Kennychaoss:BAABNQAECn88AAMCAAoKKRtQIwCoAgACAAoKKRtQIwCoAgADAAIKRQVO4wBSAAAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Kh='Kholoreous:BAAANQAECgQIBAAAAA==.',
Ki='Kille:BAABNQAECn8dAAITAAkKoA6ahwCpAQATAAkKoA6ahwCpAQAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Kobebrÿant:BAAANQABCgQIBAAAAA==.Koland:BAAANQADCgcIEQAAAA==.Kosseluna:BAABNQAECn8yAAIRAAkKawe8QQAgAQARAAkKawe8QQAgAQAAAA==.Kostazu:BAABNQAECn8+AAIDAAoKdw9LQQDOAQADAAoKdw9LQQDOAQAAAA==.',
La='Laity:BAAANQAECgcIEQAAAA==.Lazariir:BAABNQAECn8XAAIOAAkK2RqmOABdAgAOAAkK2RqmOABdAgAAAA==.Lazkal:BAAANQAECgcIDwAAAA==.',
Le='Lebesgue:BAABNQAECn84AAMCAAoKMRqaNABJAgACAAoKMRqaNABJAgADAAIKcgRU5QBOAAABNQAFFAMICQAWACcRAA==.Lebigmu:BAABNQAECn8tAAIgAAoKhB3CCACXAgAgAAoKhB3CCACXAgAAAA==.Leelee:BAAANQAECgYICQAAAA==.',
Li='Lilbones:BAAANQADCgUIBQABNQAECgoKRwAOAE8iAA==.Lisettar:BAAANQAECgcICgAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECggIDgAIAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYICgABNQAECgcIBwAIAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAIAAAAAA==.Luralia:BAAANQAECgYICAAAAA==.',
Ly='Lycanbyte:BAAANQAECgQIBAAAAA==.Lylith:BAABNQAECn89AAIdAAoKBRR8GgDZAQAdAAoKBRR8GgDZAQAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Maddicollins:BAAANQAECgcIDgABNQAFFAMICAAQALYPAA==.Magdalena:BAABNQAECn8kAAITAAkK7Ql4jQCcAQATAAkK7Ql4jQCcAQAAAA==.Magegrumpy:BAAANQADCggICQAAAA==.Maghavik:BAAANQADCgMIAwAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magmaface:BAAANQAECgYIDAAAAA==.Magnólia:BAABNQAECn82AAICAAoKjyF1FgADAwACAAoKjyF1FgADAwAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQAECgQIBgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgYIDAAAAA==.Maribelle:BAAANQAECgUIDgABNQAECgoKQwAGAPMkAA==.Masha:BAAANQADCgIIAgAAAA==.Mattdemòn:BAAANQAECgEIAgABNQAECgUIBwAIAAAAAA==.Maximander:BAAANQAECgUICgAAAA==.',
Me='Melomel:BAAANQAECgUICgAAAA==.Melonsquezer:BAABNQAECn87AAIVAAoK8R5wCwB9AgAVAAoK8R5wCwB9AgAAAA==.Menmei:BAAANQAECgUICgAAAA==.Meow:BAAANQAECgQIBgAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAABNQAECn8cAAIJAAkK0AVFQgAgAQAJAAkK0AVFQgAgAQAAAA==.',
Mi='Milkman:BAAANQABCgEIAQABNQAECggIIgAQAFEfAA==.Minbyunggyu:BAAANQADCgIIAwAAAA==.Minien:BAABNQAECn8oAAIgAAoKYRcaEQBYAgAgAAoKYRcaEQBYAgAAAA==.Minko:BAAANQABCgUIBQAAAA==.Minore:BAAANQAECggIDgAAAA==.',
Mo='Moa:BAABNQAECn8jAAMRAAoKKRIKJQDUAQARAAoKKRIKJQDUAQALAAQKCQgGSACPAAABNQAECgoKNQAFABMPAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAABNQAECn9NAAMfAAoKYBdJDwBHAgAfAAoKLRdJDwBHAgATAAYKQhMTlACNAQAAAA==.Moortz:BAAANQAECgIIAgABNQAECgoKOQAfAOEiAA==.Morillic:BAABNQAECn8vAAQFAAoKfxeTBACQAgAFAAkK/xeTBACQAgAPAAMK8RNUQADBAAAHAAUKcg6zEAGqAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAABNQAECn8fAAIHAAoKlRaYMwBBAgAHAAoKlRaYMwBBAgAAAA==.',
My='Myros:BAABNQAECn87AAMGAAoKoxh7CAAoAgAGAAoKlRd7CAAoAgABAAYKfxP3CAF+AQAAAA==.',
Na='Nadiaa:BAAANQAECgYIBQAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgMIBAABNQAECgoKOwAGAKMYAA==.Narestor:BAABNQAECn8ZAAMOAAoKNQuQkABgAQAOAAkKOAyQkABgAQAhAAMKXwWrKQBkAAABNQAFFAQIBwAjAFwFAA==.Nasril:BAAANQADCgEIAQAAAA==.Nazervis:BAACNQAFFH8RAAMXAAUKohzYAwCkAQAXAAUKohzYAwCkAQAjAAEKGQHaGgAyAAA1AAQKfyoAAxcACgokJG4FADsDABcACgokJG4FADsDACQAAQrbH3IhAEsAAAE1AAUUCAgKACUAUQ0A.',
Ne='Nekopunch:BAAANQAECgUJBQAAAA==.Nelcor:BAABNQAECn8nAAIjAAkKYg3BEwC9AQAjAAkKYg3BEwC9AQAAAA==.Nemesîs:BAAANQADCggICAAAAA==.Newhealer:BAABNQAECn8iAAMEAAoK4A9DfwCbAQAEAAoK4A9DfwCbAQAKAAIKTQWXIwBMAAAAAA==.',
No='Noint:BAABNQAECn8eAAINAAgKNwm0YQASAQANAAgKNwm0YQASAQAAAA==.Nortree:BAAANQAECgUICgAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECn8rAAMXAAcK2Bp6EQA8AgAXAAcK2Bp6EQA8AgAkAAQKGhYwEwD9AAAAAA==.',
Ny='Nymue:BAABNQAECn8tAAMDAAgKOBA1ewCxAQADAAgKOBA1ewCxAQAgAAEKAAB2OQApAAAAAA==.Nyyrivik:BAAANQADCgcIDwAAAA==.',
Nz='Nzoth:BAAANQADCgEIAQAAAA==.',
Ob='Obabo:BAAANQAECgcICAAAAA==.',
Oc='Octapie:BAABNQAECn84AAICAAoKbxWDRgD5AQACAAoKbxWDRgD5AQAAAA==.',
Oh='Ohitsadragon:BAABNQAECn8jAAIXAAoKSg8qCwCxAQAXAAoKSg8qCwCxAQAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAABNQAECn8dAAIBAAUKAgvyTAEPAQABAAUKAgvyTAEPAQAAAA==.Orcburger:BAAANQAECgcICAAAAA==.Oreoscruunit:BAAANQAECggIEAAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAABNQAECn8bAAIHAAYKVAN5AgHHAAAHAAYKVAN5AgHHAAAAAA==.',
Ow='Owl:BAABNQAECn8oAAIFAAoKhQeJDACYAQAFAAoKhQeJDACYAQAAAA==.Owlcatraz:BAACNQAFFH8NAAIRAAcKVQyUCgByAQARAAcKVQyUCgByAQA1AAQKf0MAAhEACQo3IHESADQDABEACQo3IHESADQDAAAA.',
Pa='Paendrag:BAAANQAECgQIBAAAAA==.Paladinna:BAAANQADCgQIBAAAAA==.Panteragon:BAAANQAECgUICgAAAA==.Panthean:BAABNQAECn8aAAIEAAgKOx1wSAAWAgAEAAgKOx1wSAAWAgAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgUICgAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECn9HAAIEAAoKMxnfKACqAgAEAAoKMxnfKACqAgAAAA==.Persaud:BAABNQAECn8eAAMPAAoKDx5KFwCyAQAHAAkKgBwiXABDAgAPAAUK6x9KFwCyAQAAAA==.Pettacular:BAABNQAECn83AAITAAoK7hXdXgAKAgATAAoK7hXdXgAKAgAAAA==.',
Ph='Phidra:BAABNQAECn9CAAMCAAoKxQpKWACzAQACAAoKxQpKWACzAQADAAYKxAHs8gCvAAAAAA==.Philfaux:BAAANQAECgQIBAAAAA==.Philitrescu:BAAANQAECggICAAAAA==.Phytos:BAAANQAECgEIAQAAAA==.',
Po='Poprocks:BAAANQAECgIIAwAAAA==.Potatogg:BAAANQAECgUIDgAAAA==.',
Pr='Predatorc:BAABNQAECn8gAAITAAgKAgiHwgB9AQATAAgKAgiHwgB9AQAAAA==.Primevil:BAABNQAECn8WAAMVAAgKPg3EMwBFAQAVAAYKqBDEMwBFAQAQAAgKyAX44gAYAQAAAA==.Primevl:BAABNQAECn86AAIRAAoKRBL4IAD2AQARAAoKRBL4IAD2AQAAAA==.Primévil:BAAANQAECgIIAgAAAA==.',
Py='Pyrissa:BAAANQABCgYIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Qu='Quarz:BAAANQADCgIIAgAAAA==.',
Ra='Radïance:BAABNQAECn8fAAMQAAkK9wkexwBHAQAQAAkK9wkexwBHAQAVAAEKAACSgQAAAAAAAA==.Raediant:BAABNQAECn8fAAIVAAoKkBIdKwCEAQAVAAoKkBIdKwCEAQAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Rahvinwulf:BAAANQADCgQIBAAAAA==.Raquel:BAABNQAECn8gAAICAAgKvgIHuwD1AAACAAgKvgIHuwD1AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBAAAAA==.Rectaltremor:BAAANQADCgYIBgAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEAAIAAAAAA==.Reign:BAAANQADCggIIwABNQAECgoKNQAFABMPAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgAIAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECn89AAIYAAoK4hQaHwATAgAYAAoK4hQaHwATAgAAAA==.Ris:BAABNQAECn9GAAMGAAoKDRqKDQC/AQABAAkK5BY5cwDKAQAGAAYKohqKDQC/AQAAAA==.Ritami:BAABNQAECn8dAAIfAAkKFCBwFgCoAgAfAAkKFCBwFgCoAgAAAA==.',
Ro='Roffy:BAABNQAECn84AAIeAAoKTBOhPAAkAgAeAAoKTBOhPAAkAgAAAA==.Roknathar:BAABNQAECn85AAMfAAoK4SIIBwBfAwAfAAoK4SIIBwBfAwATAAEKAABdUQFBAAAAAA==.',
Ru='Ruitiny:BAAANQAECgEIAQAAAA==.',
Sa='Saerin:BAABNQAECn8UAAIBAAgKWxv1iQBrAgABAAgKWxv1iQBrAgAAAA==.Saintmedes:BAAANQAECgQICAAAAA==.Sangoma:BAAANQADCggIFAAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.Saxmaster:BAAANQAECgIIAgAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQAECgMIBgAAAA==.Sehlia:BAABNQAECn9FAAIHAAoKwxYoRQAFAgAHAAoKwxYoRQAFAgAAAA==.Selarae:BAAANQAECggIDQABNQAECgkJHQAfABQgAA==.Selenis:BAAANQAECgYICgABNQAECgoKRAAMAL4lAA==.Seraphyne:BAAANQAECgIIAgABNQAECgUIDwAIAAAAAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAABNQAECn8XAAINAAkKUAbcXQAgAQANAAkKUAbcXQAgAQAAAA==.Shadowwizard:BAABNQAECn8UAAIBAAgKUBchsgAfAgABAAgKUBchsgAfAgABNQAECggIIgAQAFEfAA==.Shadygrove:BAAANQABCgEIAQABNQAECgoKNgACAI8hAA==.Shamania:BAAANQAECgcIDQABNQAECggIDgAIAAAAAA==.Shaomai:BAABNQAECn8sAAMDAAoK1hyuawDdAQADAAYKoB2uawDdAQACAAoKGxl/bwC9AQABNQAFFAYIEQABAOQhAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAAANQAECggIEQABNQAECgoKLwAEAIscAA==.Shidandfard:BAABNQAECn8xAAIBAAoKGCGQMwAjAwABAAoKGCGQMwAjAwAAAA==.Shifte:BAABNQAECn9NAAIbAAoKHBZbDAANAgAbAAoKHBZbDAANAgAAAA==.Shishkä:BAAANQAECggIDAAAAA==.Shiv:BAAANQADCggIFgABNQAECgIIAgAIAAAAAA==.Shizuka:BAAANQADCggICAAAAA==.Shockabeotch:BAABNQAECn8aAAIDAAkKqgwfbwA7AQADAAkKqgwfbwA7AQABNQAECgkKGgATAOAWAA==.Shy:BAAANQAECgcIEgABNQAECgoKLwAEAIscAA==.Shêrra:BAAANQADCgEIAQAAAA==.',
Si='Silverwin:BAAANQAECgUICgAAAA==.',
Sk='Skorvrax:BAABNQAECn8YAAIOAAcKSwZHxADsAAAOAAcKSwZHxADsAAAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAFFAIIAgAAAA==.Slimage:BAABNQAECn8zAAIBAAoKfhhVlwBSAgABAAoKfhhVlwBSAgAAAA==.Slushius:BAAANQADCgEJAQAAAA==.',
Sm='Smashufacein:BAAANQAECgQIAgAAAA==.Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAABNQAECn8+AAIVAAoK+Q9KGwCXAQAVAAoK+Q9KGwCXAQAAAA==.',
Sp='Spaarkle:BAABNQAECn8aAAIRAAgKSgwBQwAaAQARAAgKSgwBQwAaAQAAAA==.Spectrehawk:BAAANQAECgEIAQABNQAFFAMICAAMAJYaAA==.Speçtre:BAACNQAFFH8IAAIMAAMKlhozFgC9AAAMAAMKlhozFgC9AAA1AAQKfy4AAgwACQrOIUoZAOMCAAwACQrOIUoZAOMCAAAA.',
St='Stheris:BAAANQADCgYJBgABNQAFFAQIBwAjAFwFAA==.',
Su='Supak:BAAANQAECgQIBQAAAA==.Suppabad:BAABNQAECn9CAAIWAAoK2hreCgCUAgAWAAoK2hreCgCUAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgQICgABNQAECgoKQwAGAPMkAA==.Tadlight:BAAANQAECgMIBgAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tarysha:BAABNQAECn8YAAImAAkKCghccABYAQAmAAkKCghccABYAQAAAA==.Tattooman:BAAANQABCgIIAQAAAA==.Tayoma:BAAANQABCgYICgAAAA==.Tazara:BAAANQAECgUIBwAAAA==.Tazmaniaa:BAAANQAECgQIBAAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEAAAAA==.Ted:BAABNQAECn84AAIDAAoKRR1iIQBrAgADAAoKRR1iIQBrAgAAAA==.Tehnegev:BAABNQAECn8WAAImAAcKiRLVXACWAQAmAAcKiRLVXACWAQABNQAECgoKIwAQAIoZAA==.Tehzealza:BAAANQAECgMIAwABNQAECgoKIwAQAIoZAA==.Teias:BAAANQAECgUIBQABNQAFFAMICQAEADsRAA==.Temptressxx:BAAANQAECgUIDQAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAABNQAECn8YAAIEAAcKMhcXbACZAQAEAAcKMhcXbACZAQABNQAECgkJGQAZAFQdAA==.Themage:BAAANQADCggICAAAAA==.Thokmay:BAAANQAECgQIBQAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQAECgQICAAAAA==.',
Ti='Tiandrinna:BAABNQAECn8/AAMnAAoKEBoCAgBVAgAnAAoKyBkCAgBVAgABAAoK0BQUWwAEAgAAAA==.Tightywhitey:BAAANQABCgYIBwAAAA==.Tigirius:BAAANQAECgMIAgAAAA==.Timkaoss:BAAANQAECgMIBAAAAA==.Timmyjudge:BAAANQAECgUICQAAAA==.Timmykaoss:BAAANQADCgYIBgAAAA==.',
Tm='Tmagnet:BAAANQAECgUICgAAAA==.',
To='Tophats:BAAANQABCgcIDgAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQADCgYJCQAAAA==.Tourmaline:BAAANQAECgIIBAABNQAECgoKNgACAI8hAA==.Toyoma:BAAANQABCgIIBAAAAA==.',
Tr='Trancepants:BAAANQAECggICgAAAA==.Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQADCggIDgAAAA==.',
Tw='Tweedildee:BAACNQAFFH8JAAIGAAMK8RLYAwDcAAAGAAMK8RLYAwDcAAA1AAQKfz0AAgYACgrkGVIHAH0CAAYACgrkGVIHAH0CAAAA.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECggIDgAIAAAAAA==.Unkindled:BAABNQAECn8iAAIQAAgKUR8YXwAVAgAQAAgKUR8YXwAVAgAAAA==.',
Va='Valdor:BAABNQAECn81AAINAAoKCRHnOADxAQANAAoKCRHnOADxAQAAAA==.Valicous:BAAANQAECgQIBAAAAA==.Valoreon:BAAANQAECgQIBAAAAA==.Vandalie:BAAANQAECgQIBwABNQAECgkJGgAlACogAA==.Vaskie:BAEANQAECgcIDAABNQAFFAYIEgAOAHsUAA==.Vaylorian:BAABNQAECn8mAAILAAkKaiaJAAD4AwALAAkKaiaJAAD4AwAAAA==.',
Ve='Velion:BAAANQAECgYIDQAAAA==.Vellathor:BAAANQADCgQIBQABNQAECgoKIwABACoSAA==.Velocity:BAABNQAECn8xAAMOAAoKuhsONQBrAgAOAAoKnBsONQBrAgAhAAUKiRwBEwBxAQAAAA==.Verianna:BAABNQAECn9EAAMMAAoKviUgAwBTAwAMAAoKviUgAwBTAwAlAAYKVxRCcwBKAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgoKNQAFABMPAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAACNQAFFH8RAAIBAAYK5CEjEACDAQABAAYK5CEjEACDAQA1AAQKfygAAgEACgq4JMgNAB0DAAEACgq4JMgNAB0DAAAA.',
Vu='Vulpixen:BAAANQAECggIDwAAAA==.',
Wa='Wadumu:BAAANQAECgYIDgAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgMIBQAAAA==.',
We='Wevu:BAAANQAECggICAAAAA==.',
Wi='Willothewisp:BAAANQADCgUIBQAAAA==.Willowy:BAABNQAECn9DAAIGAAoK8ySvAQAiAwAGAAoK8ySvAQAiAwAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECn9CAAIOAAoKXQwpbgC3AQAOAAoKXQwpbgC3AQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xanda:BAABNQAECn8YAAIOAAkK1AxlfwCJAQAOAAkK1AxlfwCJAQAAAA==.Xantyr:BAAANQAECgYICwAAAA==.',
Ya='Yarman:BAAANQAECgUICgAAAA==.',
Yo='Yojimbro:BAAANQAECgUIDQAAAA==.Yoshial:BAAANQAECgMICQAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgUIBwAAAA==.Zalantir:BAAANQAECggIEAABNQAFFAYIDwAfALgWAA==.Zariski:BAAANQAECgQIDAABNQAFFAMICQAWACcRAA==.Zarthus:BAAANQAECgUICQAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECn8jAAIQAAoKihn3ZwABAgAQAAoKihn3ZwABAgAAAA==.',
Zi='Zirl:BAAANQAECgEIAgABNQAFFAYIDwAfALgWAA==.Ziyn:BAACNQAFFH8PAAMfAAYKuBZKEgAaAQAfAAQKOhVKEgAaAQATAAIKMBvcKwBgAAA1AAQKf04AAxMACgq3JVcHAKIDABMACgqnJVcHAKIDAB8ACQp2G1AXANYBAAAA.',
Zo='Zoplete:BAABNQAECn8jAAIBAAoKCxIDUwAZAgABAAoKCxIDUwAZAgAAAA==.',
Zy='Zyp:BAAANQAECgEIAgAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAABNQAECn8VAAIHAAkKvga1nwAYAQAHAAkKvga1nwAYAQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQAECgEIAQAAAA==.',
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
