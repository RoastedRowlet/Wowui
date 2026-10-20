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

local lookup = {'Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Priest-Holy','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Warrior-Arms','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','Monk-Windwalker','Warlock-Destruction','Warrior-Protection','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Warrior-Fury','Rogue-Outlaw','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abhire:BAAANQAECgQIBQABNQAECgoKKgABADAWAA==.',
Ad='Advisor:BAACNQAFFH8GAAICAAMKrximCAAHAQACAAMKrximCAAHAQA1AAQKfy0AAwIACgpTIVkJAHYDAAIACgpTIVkJAHYDAAMAAQo0D/MrAT0AAAAA.',
Ae='Aería:BAABNQAECn8gAAICAAkKIyCzHAD7AgACAAkKIyCzHAD7AgAAAA==.',
Ak='Akarm:BAAANQAECgQIAQAAAA==.',
Al='Alyà:BAAANQAECgYIEgABNQAECgoKIwAEAJMLAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECgkJKwAFAKgjAA==.',
Ap='Aparajita:BAABNQAECn8yAAIGAAoKbh+rAgDFAgAGAAoKbh+rAgDFAgABNQAECgQIBQAHAAAAAA==.Aphrodite:BAABNQAECn8iAAIIAAoKhBsFJQDYAgAIAAoKhBsFJQDYAgAAAA==.',
Ar='Arianda:BAABNQAECn8sAAIJAAoK+SF8AwB/AwAJAAoK+SF8AwB/AwAAAA==.Aristoleh:BAAANQAECgUIBgABNQAFFAIIBQADAOQLAA==.Armagedonn:BAAANQADCgQIBAAAAA==.Arolder:BAABNQAECn8wAAMKAAoKxCLQBAAaAgALAAcKiSPIGgDZAgAKAAoKtiHQBAAaAgAAAA==.Artemis:BAAANQABCgYIBgABNQAECgoKIgAIAIQbAA==.',
As='Astayuno:BAAANQAECgMIBAAAAA==.',
At='Atoadaso:BAABNQAECn8eAAIMAAkKlhfeFgCtAQAMAAkKlhfeFgCtAQAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQADCggINAAHAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECn8jAAIEAAoKkwvDBwAcAgAEAAoKkwvDBwAcAgAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQAECgEIAQAAAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgIIAwAAAA==.Bankus:BAAANQADCgYICAAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECn8ZAAMNAAUKcRiqWgBpAQANAAUKcRiqWgBpAQAOAAIK5wpzeAAuAAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYIDQAAAA==.',
Bj='Björn:BAAANQADCggIEAAAAA==.',
Bl='Blasphemar:BAAANQADCgUICQAAAA==.Blinkz:BAAANQAECgEJAQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boombástic:BAABNQAECn8rAAMOAAgKKxTIDwBMAQAOAAgKKxTIDwBMAQANAAUKUQj3egDfAAAAAA==.Boomco:BAABNQAECn8rAAIPAAoK8AjEjgDsAQAPAAoK8AjEjgDsAQAAAA==.Bordinn:BAAANQADCgIIAgAAAA==.',
Br='Bravillius:BAAANQADCggIFQAAAA==.Breeti:BAAANQAECgIIBAAAAA==.Broin:BAAANQAECgIIAwAAAA==.Bryda:BAAANQAECgUIBwAAAA==.',
Bu='Bubblecreep:BAAANQADCgYICQABNQAECgcIDQAHAAAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Burtangus:BAAANQAECgUIDwAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQAECgEIAQABNQAECgIIAwAHAAAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAABNQAECn8eAAIQAAgK5xnnCgB2AQAQAAgK5xnnCgB2AQAAAA==.Calyssa:BAABNQAECn8mAAIRAAkKThnSUACjAgARAAkKThnSUACjAgAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQADCgYICAAHAAAAAA==.Capybara:BAAANQAECggIEAABNQAFFAUIEAANANkYAA==.Cartan:BAABNQAECn81AAISAAoKUxtACQD3AgASAAoKUxtACQD3AgAAAA==.Castisteus:BAAANQADCggICQAAAA==.Cathum:BAAANQAECggIBwAAAA==.',
Ch='Charizaardx:BAACNQAFFH8PAAITAAUKaAyhBwAPAQATAAUKaAyhBwAPAQA1AAQKf0oAAhMACgrTHM4BANgBABMACgrTHM4BANgBAAAA.Chromeski:BAAANQAECggIDwAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAABNQAECn8eAAIMAAgKcQ+DXwDZAAAMAAgKcQ+DXwDZAAAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQAECgIIAQAAAA==.Creepymage:BAAANQAECgcICgABNQAECgcIDQAHAAAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAABNQAECn8XAAIFAAcKfQV7HgD4AAAFAAcKfQV7HgD4AAAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECn8XAAIUAAcKvBWIQAC6AQAUAAcKvBWIQAC6AQAAAA==.',
Da='Dalna:BAABNQAECn8cAAMSAAcK5Q5YDQAAAQASAAcK5Q5YDQAAAQAVAAUK7wcYTQDDAAAAAA==.Danksoul:BAAANQAECgIIAwABNQAECggIDAAHAAAAAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAAANQAECgUIDwAAAA==.Darksaber:BAAANQADCggIGgAAAA==.Darkwi:BAABNQAECn8rAAMWAAkK1hAOHwB2AQAGAAcKSw+EkAC9AQAWAAYKqREOHwB2AQAAAA==.Dasthodan:BAAANQADCggIFgABNQAECggIDwAHAAAAAA==.Dayne:BAAANQAECgQIBAAAAA==.',
Dc='Dctrpepper:BAAANQAECgEIAQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgcIFwAUALwVAA==.Deathby:BAABNQAECn8bAAMMAAUKPgPOHAGiAAAMAAUKPgPOHAGiAAAXAAEKAADfRgAoAAAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECn8sAAQOAAkKUQWlIgC/AAAOAAkKUQWlIgC/AAANAAUKxAAaVAAxAAAYAAEKAADqTgAYAAAAAA==.Deldawalth:BAAANQAECgYICAAAAA==.Demonica:BAABNQAECn8dAAQUAAgKKwksIAD8AAAUAAcKKwksIAD8AAAZAAYKiASbIQC2AAAaAAMKcATfXACGAAAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECgUICwAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECn8uAAIRAAkKSRA8JQCQAQARAAkKSRA8JQCQAQAAAA==.',
Do='Dominoes:BAAANQAECgYIDgAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAABNQAECn8cAAMNAAgKtgjfVgB7AQANAAgKtgjfVgB7AQAOAAMK6gQGZQByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECn8oAAIJAAoKPhm9AwDrAQAJAAoKPhm9AwDrAQAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgAHAAAAAA==.',
Eg='Ego:BAABNQAECn8nAAIbAAgKcyHjHAAAAwAbAAgKcyHjHAAAAwAAAA==.',
Ei='Eiduartplis:BAAANQAECggIDwAAAA==.',
El='Ellaana:BAAANQAECgQIBgAAAA==.Ellee:BAAANQAECgQIBAAAAA==.Elotarra:BAAANQADCgYIDgAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECgkJKwAFAKgjAA==.Fananabanana:BAAANQAECgYIDwABNQAECgkJGAAIAB0MAA==.',
Fe='Fenrith:BAAANQAECgEIAQAAAA==.',
Fi='Figaro:BAAANQAECgUIBwABNQAECgkJHAAcAKweAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECn8lAAIBAAcKHROT2gDSAQABAAcKHROT2gDSAQAAAA==.',
Fl='Flameheart:BAAANQAECgMIAwAAAA==.Fleathulhu:BAABNQAECn8sAAIIAAkKBBeYWQAVAgAIAAkKBBeYWQAVAgAAAA==.Flungpu:BAAANQADCggIKwABNQAECggIJwAPACcLAA==.',
Fo='Fostock:BAAANQAECgIIAwAAAA==.',
Fr='Frobenius:BAAANQAECgcICgABNQAECgoKNQASAFMbAA==.Frostmoon:BAAANQABCgcIDQAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAABNQAECn8uAAIQAAoKyxAyGQAAAQAQAAoKyxAyGQAAAQAAAA==.',
Gh='Ghostkev:BAABNQAECn8nAAMPAAoKPhzMLQDkAgAPAAoKPhzMLQDkAgAcAAQKjQiNXACzAAAAAA==.Ghoulmaxing:BAAANQADCgEIAgABNQAECgoKNgAMAAEdAA==.',
Gl='Glaistia:BAAANQADCggIDAAAAA==.Glen:BAAANQAECgQIBgAAAA==.Glowstik:BAAANQAECgMIAwAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECn8pAAIdAAoKRRysAQBUAgAdAAoKRRysAQBUAgAAAA==.Hankmoodie:BAABNQAECn8VAAIMAAkK+wZzOAA3AQAMAAkK+wZzOAA3AQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgIIAwAAAA==.',
Ho='Holysim:BAAANQAECgIIAgAAAA==.Honir:BAABNQAECn8kAAIeAAkKOB06AgA0AgAeAAkKOB06AgA0AgAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEJAQAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECgkJKwAFAKgjAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECn8jAAMWAAkK9gkcAwAfAQAGAAgKAQjJvgBPAQAWAAcKxgkcAwAfAQAAAA==.Imooforu:BAAANQADCgUJBgABNQADCgUIDAAHAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgYICQAAAA==.Jaen:BAAANQAECgEIAQABNQAECggIKgAIAIURAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Jc='Jckruzy:BAAANQADCgIIAgAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcIEgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECn8nAAIPAAgKJwu0kwDhAQAPAAgKJwu0kwDhAQAAAA==.Kaladiin:BAABNQAECn8XAAIfAAcKewhzCwDEAAAfAAcKewhzCwDEAAAAAA==.Kallias:BAABNQAECn8qAAIbAAkK/iObAgD5AgAbAAkK/iObAgD5AgAAAA==.Kandistars:BAABNQAECn8iAAINAAcKsBIZTACzAQANAAcKsBIZTACzAQAAAA==.Karite:BAABNQAECn8uAAIgAAkKgxxTAAA/AgAgAAkKgxxTAAA/AgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Kaymyn:BAABNQAECn8lAAIFAAoKBRJoBABqAQAFAAoKBRJoBABqAQAAAA==.Kazar:BAAANQADCgUICgAAAA==.Kazen:BAAANQADCggICAAAAA==.Kazenoth:BAAANQADCgUIBQAAAA==.',
Ke='Kehjistan:BAAANQAECgcIDAAAAA==.Kennychaoss:BAABNQAECn8mAAICAAkKvRsXDwDjAQACAAkKvRsXDwDjAQAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAAANQAECgYICgAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Koland:BAAANQADCgcIEQAAAA==.Kosseluna:BAABNQAECn8cAAINAAcKRgeXKgC4AAANAAcKRgeXKgC4AAAAAA==.Kostazu:BAABNQAECn8rAAIDAAkK3wvtFAB0AQADAAkK3wvtFAB0AQAAAA==.',
La='Laity:BAAANQAECgUICgAAAA==.Lazariir:BAAANQAECgcICgAAAA==.Lazkal:BAAANQAECgUICAAAAA==.',
Le='Lebesgue:BAABNQAECn8eAAICAAoKaRjoPQBoAgACAAoKaRjoPQBoAgABNQAECgoKNQASAFMbAA==.Lebigmu:BAABNQAECn8XAAIdAAcKfBp9EQBSAgAdAAcKfBp9EQBSAgAAAA==.Leelee:BAAANQAECgUIBgAAAA==.',
Li='Lilbones:BAAANQADCgUIBQABNQAECgoKNgAMAAEdAA==.Lisettar:BAAANQAECgcICgAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECgcIDQAHAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYICgABNQAECgcIBQAHAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAHAAAAAA==.Luralia:BAAANQAECgUICAAAAA==.',
Ly='Lycanbyte:BAAANQADCggINQAAAA==.Lylith:BAABNQAECn8sAAIaAAgKhhVPCwBgAQAaAAgKhhVPCwBgAQAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Magdalena:BAAANQAECgYIEQAAAA==.Magegrumpy:BAAANQADCgIIAgAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magmaface:BAAANQAECgYIBgAAAA==.Magnólia:BAABNQAECn8lAAICAAkKvR98JgDLAgACAAkKvR98JgDLAgAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQADCgUIBgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgYIDAAAAA==.Maribelle:BAAANQAECgEIAQABNQAECgkJKwAFAKgjAA==.Masha:BAAANQADCgIIAgAAAA==.Maximander:BAAANQAECgQIBAAAAA==.',
Me='Melomel:BAAANQAECgIIAwAAAA==.Melonsquezer:BAABNQAECn8oAAIeAAkK5Bx+EQCJAgAeAAkK5Bx+EQCJAgAAAA==.Menmei:BAAANQAECgIIAwAAAA==.Meow:BAAANQAECgQIBgAAAA==.Meowmix:BAAANQAECgEIAQAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAABNQAECn8WAAIhAAcKHwZFQgAgAQAhAAcKHwZFQgAgAQAAAA==.',
Mi='Milkman:BAAANQABCgEIAQABNQAECggIGgARAOYZAA==.Minien:BAABNQAECn8hAAIdAAoKQBQ+CgBSAQAdAAoKQBQ+CgBSAQAAAA==.Minore:BAAANQAECggIDAAAAA==.',
Mo='Moa:BAABNQAECn8aAAMNAAkK7RAVHgD5AAANAAkK7RAVHgD5AAAJAAQKCQgGSACPAAABNQAECgoKIwAEAJMLAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAABNQAECn8rAAMcAAkKDRSVKgD2AQAcAAkKRRKVKgD2AQAPAAQKMBFRWAD+AAAAAA==.Moortz:BAAANQAECgIIAgABNQAECgoKJwAcALAfAA==.Morillic:BAABNQAECn8lAAQEAAoKTheTBACQAgAEAAkK/xeTBACQAgAGAAQKjBGzEAGqAAAWAAMK8ROzCQCCAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAAANQAECgYIBgAAAA==.',
My='Myros:BAABNQAECn8oAAMFAAkKDhYYBQBVAQABAAYKfxP3CAF+AQAFAAcKcBYYBQBVAQAAAA==.',
Na='Nadiaa:BAAANQADCggIDAAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgQIBAABNQAECgkJKAAFAA4WAA==.Narestor:BAAANQAECgYIDgAAAA==.Nazervis:BAACNQAFFH8RAAMTAAUKohzYAwCkAQATAAUKohzYAwCkAQAiAAEKGQHaGgAyAAA1AAQKfyoAAxMACgokJG4FADsDABMACgokJG4FADsDACMAAQrbH3IhAEsAAAE1AAUUBwgIACQAVQwA.',
Ne='Nekopunch:BAAANQAECgUJBQAAAA==.Nelcor:BAAANQAECgUIEwAAAA==.Nemesîs:BAAANQADCggICAAAAA==.Newhealer:BAABNQAECn8YAAMIAAkKHQxDfwCbAQAIAAkKHQxDfwCbAQAlAAIKTQWXIwBMAAAAAA==.',
No='Noint:BAABNQAECn8ZAAIKAAcK9AeCKwDvAAAKAAcK9AeCKwDvAAAAAA==.Nortree:BAAANQAECgIIAwAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECn8hAAMTAAcK2Bp6EQA8AgATAAcK2Bp6EQA8AgAjAAQKGhYwEwD9AAAAAA==.',
Ny='Nymue:BAABNQAECn8iAAMDAAcKXBI1ewCxAQADAAcKXBI1ewCxAQAdAAEKAAB2OQApAAAAAA==.Nyyrivik:BAAANQADCgYJCAAAAA==.',
Nz='Nzoth:BAAANQADCgEIAQAAAA==.',
Oc='Octapie:BAABNQAECn8sAAICAAoKRRSIKgA4AQACAAoKRRSIKgA4AQAAAA==.',
Oh='Ohitsadragon:BAABNQAECn8VAAITAAgK+wuGGADAAQATAAgK+wuGGADAAQAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAABNQAECn8VAAIBAAUKAgsGiwCvAAABAAUKAgsGiwCvAAAAAA==.Oreoscruunit:BAAANQADCgYICAAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAAANQAECgUIDgAAAA==.',
Ow='Owl:BAABNQAECn8fAAIEAAoKkwaJDACYAQAEAAoKkwaJDACYAQAAAA==.Owlcatraz:BAACNQAFFH8GAAINAAUK3gTxEwArAQANAAUK3gTxEwArAQA1AAQKfzMAAg0ACQoeHXESADQDAA0ACQoeHXESADQDAAAA.',
Pa='Paendrag:BAAANQADCggIDQAAAA==.Panteragon:BAAANQAECgIIAwAAAA==.Panthean:BAABNQAECn8XAAIIAAcKviBHDgALAgAIAAcKviBHDgALAgAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgIIAwAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECn8kAAIIAAkKnA3EaADkAQAIAAkKnA3EaADkAQAAAA==.Persaud:BAABNQAECn8ZAAMWAAgKpiBKFwCyAQAGAAcK/R4iXABDAgAWAAUK6x9KFwCyAQAAAA==.Pettacular:BAABNQAECn8uAAIPAAoK7hVgHQCiAQAPAAoK7hVgHQCiAQAAAA==.',
Ph='Phidra:BAABNQAECn8uAAMCAAkK2wqLEwC4AQACAAkK2wqLEwC4AQADAAYKxAHs8gCvAAAAAA==.',
Po='Poprocks:BAAANQAECgIIAwAAAA==.Potatogg:BAAANQAECgIIBgAAAA==.',
Pr='Predatorc:BAABNQAECn8dAAIPAAgKqQaHwgB9AQAPAAgKqQaHwgB9AQAAAA==.Primevil:BAAANQAECgcIDAAAAA==.Primevl:BAABNQAECn8gAAINAAkKSguYTwCgAQANAAkKSguYTwCgAQAAAA==.',
Pu='Puspatroll:BAAANQAECgEIAQAAAA==.',
Py='Pyrissa:BAAANQABCgYIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQAECgYICgAAAA==.Raediant:BAABNQAECn8VAAIeAAgKwBMdKwCEAQAeAAgKwBMdKwCEAQAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Rahvinwulf:BAAANQADCgQJBAAAAA==.Raquel:BAABNQAECn8dAAICAAgKgAIHuwD1AAACAAgKgAIHuwD1AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBAAAAA==.Rectaltremor:BAAANQADCgYIBgAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEAAHAAAAAA==.Reign:BAAANQADCggIIwABNQAECgoKIwAEAJMLAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgAHAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECn8nAAIUAAkKcxGnFgA4AQAUAAkKcxGnFgA4AQAAAA==.Ris:BAABNQAECn8yAAMBAAkKvRenKgBwAQABAAgKjRanKgBwAQAFAAIKPRS8EQBzAAAAAA==.Ritami:BAABNQAECn8cAAIcAAkKrB5wFgCoAgAcAAkKrB5wFgCoAgAAAA==.',
Ro='Roffy:BAABNQAECn8sAAIbAAoKfBExHQB3AQAbAAoKfBExHQB3AQAAAA==.Roknathar:BAABNQAECn8nAAMcAAoKsB9xAgAsAgAcAAoKsB9xAgAsAgAPAAEKAABdUQFBAAAAAA==.',
Sa='Saerin:BAABNQAECn8UAAIBAAgKWxv1iQBrAgABAAgKWxv1iQBrAgAAAA==.Saintmedes:BAAANQAECgQICAAAAA==.Sangoma:BAAANQADCgcJBwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQAECgIIBAAAAA==.Sehlia:BAABNQAECn8tAAIGAAkKiBMzWwBFAgAGAAkKiBMzWwBFAgAAAA==.Selarae:BAAANQAECgQIBAABNQAECgkJHAAcAKweAA==.Selenis:BAAANQAECgQIBgABNQAECgkJMAALAMgjAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAAANQAECgcIDAAAAA==.Shadowwizard:BAABNQAECn8UAAIBAAgKUBchsgAfAgABAAgKUBchsgAfAgABNQAECggIGgARAOYZAA==.Shamania:BAAANQAECgcIDQAAAA==.Shaomai:BAABNQAECn8lAAMDAAoK1hquawDdAQADAAYKoB2uawDdAQACAAgK8xJ/bwC9AQABNQAFFAMIBwABACQhAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAAANQAECggIDgABNQAECgoKIgAIAIQbAA==.Shidandfard:BAABNQAECn8mAAIBAAoKmSCQMwAjAwABAAoKmSCQMwAjAwAAAA==.Shifte:BAABNQAECn8rAAIYAAkKcg/CAwCZAQAYAAkKcg/CAwCZAQAAAA==.Shishkä:BAAANQAECggIDAAAAA==.Shiv:BAAANQADCggIFgABNQAECgIIAgAHAAAAAA==.Shockabeotch:BAAANQAECggICwAAAA==.Shêrra:BAAANQADCgEIAQAAAA==.',
Si='Silverwin:BAAANQAECgIIAwAAAA==.',
Sk='Skorvrax:BAAANQAECgQICgAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAECggICQAAAA==.Slimage:BAABNQAECn8mAAIBAAoKLBclMABhAQABAAoKLBclMABhAQAAAA==.Slushius:BAAANQADCgEJAQAAAA==.',
Sm='Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAABNQAECn8gAAIeAAcKSQ5OMQBVAQAeAAcKSQ5OMQBVAQAAAA==.',
Sp='Spaarkle:BAABNQAECn8XAAINAAcKjgx7HQD9AAANAAcKjgx7HQD9AAAAAA==.Spectrehawk:BAAANQAECgEIAQABNQAFFAMICAALAJYaAA==.Speçtre:BAACNQAFFH8IAAILAAMKlhrtBgDlAAALAAMKlhrtBgDlAAA1AAQKfy4AAgsACQrOIUoZAOMCAAsACQrOIUoZAOMCAAAA.',
St='Stheris:BAAANQADCgYJBgABNQAECgYIDgAHAAAAAA==.',
Su='Supak:BAAANQAECgQIBQAAAA==.Suppabad:BAABNQAECn8uAAISAAkKqhpDAgBQAgASAAkKqhpDAgBQAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgIJAgABNQAECgkJKwAFAKgjAA==.Tadlight:BAAANQAECgIIBAAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tarysha:BAAANQAECgYIBgAAAA==.Tattooman:BAAANQABCgIIAQAAAA==.Tazara:BAAANQAECgUIBgAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEAAAAA==.Ted:BAABNQAECn8kAAIDAAgKZBijLQAHAQADAAgKZBijLQAHAQAAAA==.Tehnegev:BAAANQAECgYICQABNQAECggIGAARAKIWAA==.Tehzealza:BAAANQADCggICAAAAA==.Teias:BAAANQAECgUIBQABNQAECgoKOAAIADgaAA==.Temptressxx:BAAANQAECgUJDQAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAAANQAECgYIEAABNQAECgkJGQAVAFQdAA==.Themage:BAAANQADCggICAAAAA==.Thokmay:BAAANQAECgIIAgAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQAECgQIBAAAAA==.',
Ti='Tiandrinna:BAABNQAECn8xAAMmAAoKJxkCAgBVAgAmAAgKwRkCAgBVAgABAAoKqBSFMwBYAQAAAA==.Tightywhitey:BAAANQABCgYIBwAAAA==.Tigirius:BAAANQAECgMIAwAAAA==.Timkaoss:BAAANQAECgEIAgAAAA==.Timmyjudge:BAAANQAECgIIAgAAAA==.',
Tm='Tmagnet:BAAANQAECgIIAwAAAA==.',
To='Tophats:BAAANQABCgcIDgAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQADCgYJCQAAAA==.Tourmaline:BAAANQAECgQIBgABNQAECgkJJQACAL0fAA==.',
Tr='Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQADCggIDgAAAA==.',
Tw='Tweedildee:BAABNQAECn8pAAIFAAoKFhhSBwB9AgAFAAoKFhhSBwB9AgAAAA==.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECgcIDQAHAAAAAA==.Unkindled:BAABNQAECn8aAAIRAAgK5hkcNABkAQARAAgK5hkcNABkAQAAAA==.',
Va='Valdor:BAABNQAECn8oAAIKAAkKJhLnOADxAQAKAAkKJhLnOADxAQAAAA==.Valicous:BAAANQADCggINAAAAA==.Vandalie:BAAANQAECgMIBQABNQAECgkJFgAkAPIeAA==.Vaylorian:BAABNQAECn8mAAIJAAkKaiaJAAD4AwAJAAkKaiaJAAD4AwAAAA==.',
Ve='Velion:BAAANQAECgIIAgAAAA==.Vellathor:BAAANQADCgQIBQABNQAECggIDwAHAAAAAA==.Velocity:BAABNQAECn8XAAMMAAgKgBj7JwBmAQAfAAUKiRwBEwBxAQAMAAgKRhb7JwBmAQAAAA==.Verianna:BAABNQAECn8wAAMLAAkKyCPtAQCpAgALAAkKyCPtAQCpAgAkAAYKVxRCcwBKAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgoKIwAEAJMLAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAACNQAFFH8HAAIBAAMKJCFVEgDIAAABAAMKJCFVEgDIAAA1AAQKfx8AAgEACgoXJKQAAGMDAAEACgoXJKQAAGMDAAAA.',
Vu='Vulpixen:BAAANQAECgYICAAAAA==.',
Wa='Wadumu:BAAANQAECgYICQAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgMIBQAAAA==.',
Wi='Willothewisp:BAAANQADCgUIBQAAAA==.Willowy:BAABNQAECn8rAAIFAAkKqCNzAACkAgAFAAkKqCNzAACkAgAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECn8uAAIMAAkKOAo8IwB3AQAMAAkKOAo8IwB3AQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xanda:BAAANQAECggIDgAAAA==.Xantyr:BAAANQAECgMIAgAAAA==.',
Ya='Yarman:BAAANQAECgIIAwAAAA==.',
Yo='Yojimbro:BAAANQAECgMIBAAAAA==.Yoshial:BAAANQAECgEIAgAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgQIBgAAAA==.Zalantir:BAAANQAECggIEAABNQAFFAUIDgAcADoVAA==.Zariski:BAAANQAECgEIAQABNQAECgoKNQASAFMbAA==.Zarthus:BAAANQAECgQIBQAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECn8YAAIRAAgKohZdnwDjAQARAAgKohZdnwDjAQAAAA==.Zera:BAAANQAECgEIAQABNQAECgkJMAALAMgjAA==.',
Zi='Zirl:BAAANQAECgEIAgABNQAFFAUIDgAcADoVAA==.Ziyn:BAACNQAFFH8OAAMcAAUKOhXrBADpAAAcAAQKOhXrBADpAAAPAAEKAAAfNgBOAAA1AAQKfzkAAw8ACgpaIFcHAKIDAA8ACQrRJFcHAKIDABwACQpxG6gMACoBAAAA.',
Zo='Zoplete:BAAANQAECgYIBQAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAAANQAECggICgAAAA==.',
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
