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

local lookup = {'Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Priest-Holy','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Warrior-Arms','Warlock-Destruction','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','Monk-Windwalker','Warrior-Protection','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Warrior-Fury','Rogue-Outlaw','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abhire:BAAANQAECgQIBQABNQAECgoKMQABAJMWAA==.',
Ad='Advisor:BAACNQAFFH8GAAICAAMKrxhgDgD7AAACAAMKrxhgDgD7AAA1AAQKfzYAAwIACgr3IlkJAHYDAAIACgr3IlkJAHYDAAMAAQo0D/MrAT0AAAAA.',
Ae='Aería:BAABNQAECn8gAAICAAkKIyCzHAD7AgACAAkKIyCzHAD7AgAAAA==.',
Ak='Akarm:BAAANQAECggICQAAAA==.',
Al='Alyà:BAABNQAECn8aAAIEAAgK7BX4MwDsAQAEAAgK7BX4MwDsAQABNQAECgoKKgAFAJMLAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECgkJMAAGAPsjAA==.',
Ap='Aparajita:BAABNQAECn82AAIHAAoKiyCtEwCMAgAHAAoKiyCtEwCMAgABNQAECgQIBQAIAAAAAA==.Aphrodite:BAABNQAECn8mAAIEAAoKixwFJQDYAgAEAAoKixwFJQDYAgAAAA==.',
Ar='Arianda:BAABNQAECn81AAIJAAoKpSJ8AwB/AwAJAAoKpSJ8AwB/AwAAAA==.Aristoleh:BAAANQAECgcIBwABNQAFFAMICAADAKoMAA==.Armagedonn:BAAANQADCgQIBAAAAA==.Arolder:BAABNQAECn84AAMKAAoKxCLhEAAIAwAKAAoKtiHhEAAIAwALAAcKiSPIGgDZAgAAAA==.Artemis:BAAANQABCgYIBgABNQAECgoKJgAEAIscAA==.',
As='Astayuno:BAAANQAECgUICAAAAA==.',
At='Atoadaso:BAABNQAECn8fAAIMAAkKrxg7UQCPAQAMAAkKrxg7UQCPAQAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQAECgQIBAAIAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECn8qAAQFAAoKkwvDBwAcAgAFAAoKkwvDBwAcAgANAAEK6AwnKAA6AAAHAAIKZQfu8AArAAAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQADCgEIAQAAAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgMIBQAAAA==.Bankus:BAAANQADCgYICAAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECn8dAAMOAAgK3B2qWgBpAQAOAAUKcRiqWgBpAQAPAAUK3AgtOQC2AAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYIDQAAAA==.',
Bj='Björn:BAAANQADCggIEAAAAA==.',
Bl='Blasphemar:BAAANQADCgUICQAAAA==.Blinkz:BAAANQAECgEJAQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boombástic:BAABNQAECn8zAAMPAAgKYRUMFQDZAQAPAAgKYRUMFQDZAQAOAAUKUQj3egDfAAAAAA==.Boomco:BAABNQAECn80AAIQAAoKuAnDYAB9AQAQAAoKuAnDYAB9AQAAAA==.Bordinn:BAAANQADCgIIAgAAAA==.',
Br='Bravillius:BAAANQADCggIHQAAAA==.Breeti:BAAANQAECgMIBwAAAA==.Broin:BAAANQAECgIIAwAAAA==.Bryda:BAAANQAECgYICAAAAA==.',
Bu='Bubblecreep:BAAANQAECgcICQABNQAECgcIDQAIAAAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Burtangus:BAABNQAECn8aAAIHAAgKbxRaQQCkAQAHAAgKbxRaQQCkAQAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQAECgEIAQABNQAECgIIAwAIAAAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAABNQAECn8lAAIRAAgKthyGCgDcAQARAAgKthyGCgDcAQAAAA==.Calyssa:BAABNQAECn8vAAISAAoKGB1OIwB6AgASAAoKGB1OIwB6AgAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQADCgYICAAIAAAAAA==.Capybara:BAAANQAECggIEAABNQAFFAYIFgALAGYfAA==.Cartan:BAABNQAECn86AAITAAoKrh1ACQD3AgATAAoKrh1ACQD3AgAAAA==.Castisteus:BAAANQADCggICQAAAA==.Cathum:BAAANQAECgcIBwAAAA==.',
Ch='Charizaardx:BAACNQAFFH8QAAIUAAUKaAyhBwAPAQAUAAUKaAyhBwAPAQA1AAQKf1QAAhQACgqiHX4DAF4CABQACgqiHX4DAF4CAAAA.Chromeski:BAABNQAECn8XAAIBAAkKAw5ybABuAQABAAkKAw5ybABuAQAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAABNQAECn8iAAIMAAgKJBE3sQChAQAMAAgKJBE3sQChAQAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQAECgMIAwAAAA==.Creepymage:BAAANQAECgcICgABNQAECgcIDQAIAAAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAABNQAECn8XAAIGAAcKfQV7HgD4AAAGAAcKfQV7HgD4AAAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECn8aAAIVAAkKdxaIQAC6AQAVAAkKdxaIQAC6AQAAAA==.',
Da='Dalna:BAABNQAECn8jAAMTAAgKaA5LEwBDAQATAAgKaA5LEwBDAQAWAAUK7wcYTQDDAAAAAA==.Danksoul:BAAANQAECgIIAwABNQAECggIDQAIAAAAAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAABNQAECn8UAAIQAAYKtQYjlwACAQAQAAYKtQYjlwACAQAAAA==.Darksaber:BAAANQADCggIGgAAAA==.Darkwi:BAABNQAECn8rAAMNAAkK1hAOHwB2AQAHAAcKSw+EkAC9AQANAAYKqREOHwB2AQAAAA==.Dasthodan:BAAANQAECgUIBAABNQAECgkJFwABAAMOAA==.Dayne:BAAANQAECgYIBgAAAA==.Dayus:BAAANQAECgMIAQAAAA==.',
Dc='Dctrpepper:BAAANQAECgQIBQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgkJGgAVAHcWAA==.Deathby:BAABNQAECn8cAAMMAAUKPgPOHAGiAAAMAAUKPgPOHAGiAAAXAAEKAADfRgAoAAAAAA==.Deathcore:BAAANQADCggIEAAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECn8vAAQPAAkKcwVWQgAXAQAPAAkKcwVWQgAXAQAOAAUKxADtcQAtAAAYAAEKAADqTgAYAAAAAA==.Deldawalth:BAAANQAECgYICAAAAA==.Demonica:BAABNQAECn8iAAQVAAgKVAnPNwD1AAAVAAgKVAnPNwD1AAAZAAcK2QSbIQC2AAAaAAMKcATfXACGAAAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECgcIDAAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECn81AAISAAoKKBAqVQC2AQASAAoKKBAqVQC2AQAAAA==.',
Do='Dominoes:BAABNQAECn8cAAIQAAYKQhbuqwCtAQAQAAYKQhbuqwCtAQAAAA==.Dotho:BAAANQAECggIAQAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Dragonzord:BAAANQADCgUIBQAAAA==.Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAABNQAECn8cAAMOAAgKtgjfVgB7AQAOAAgKtgjfVgB7AQAPAAMK6gQGZQByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECn8rAAIJAAoK8hlECwAHAgAJAAoK8hlECwAHAgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgAIAAAAAA==.',
Ec='Eclamp:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn8tAAIbAAgKcyHjHAAAAwAbAAgKcyHjHAAAAwAAAA==.',
Ei='Eiduartplis:BAAANQAECgcIDgAAAA==.',
El='Ellaana:BAAANQAECgQIBgAAAA==.Ellee:BAAANQAECgQIBAAAAA==.Elotarra:BAAANQADCgYIDgAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECgkJMAAGAPsjAA==.Fananabanana:BAABNQAECn8UAAIFAAgKfQ5jDQCEAQAFAAgKfQ5jDQCEAQABNQAECgkJGwAEAHANAA==.',
Fe='Fenrith:BAAANQABCgQIBAAAAA==.Feorarlia:BAAANQADCgQIBAABNQAECgkJGwAEAHANAA==.',
Fi='Figaro:BAAANQAECgUIBwABNQAECgkJHQAcABQgAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECn8lAAIBAAcKHROT2gDSAQABAAcKHROT2gDSAQAAAA==.',
Fl='Flameheart:BAAANQAECgIIAwAAAA==.Fleathulhu:BAABNQAECn8wAAIEAAoKaRaYWQAVAgAEAAoKaRaYWQAVAgAAAA==.Flungpu:BAAANQADCggIMgABNQAECggILQAQACMMAA==.',
Fo='Fostock:BAAANQAECgMIBQAAAA==.',
Fr='Frobenius:BAABNQAECn8XAAIEAAkKzBXKNQDjAQAEAAkKzBXKNQDjAQABNQAECgoKOgATAK4dAA==.Frostmoon:BAAANQABCgcIDQAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAABNQAECn81AAIRAAoK8BHEFgBEAQARAAoK8BHEFgBEAQAAAA==.',
Gh='Ghostkev:BAABNQAECn8qAAMQAAoKpxzMLQDkAgAQAAoKpxzMLQDkAgAcAAQKjQiNXACzAAAAAA==.Ghoulmaxing:BAAANQADCgEIAgABNQAECgoKQAAMAE8iAA==.',
Gl='Glaistia:BAAANQADCggIDAAAAA==.Glen:BAAANQAECgQIBgAAAA==.Glowstik:BAAANQAECgMIAwAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECn8zAAIdAAoK+R5ZBAC1AgAdAAoK+R5ZBAC1AgAAAA==.Hankmoodie:BAABNQAECn8ZAAIMAAkKGQhpYgBcAQAMAAkKGQhpYgBcAQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.Harmoni:BAAANQAECgMIAwABNQAECgkJMAAGAPsjAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgMIBQAAAA==.',
Ho='Holysim:BAAANQAECgIIAgAAAA==.Honir:BAABNQAECn8sAAIeAAkK0R6dDQDBAgAeAAkK0R6dDQDBAgAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEIAQAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECgkJMAAGAPsjAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECn8nAAMNAAkKLgpVBwADAQAHAAkKzQfJvgBPAQANAAcKxglVBwADAQAAAA==.Imooforu:BAAANQADCgUJBgABNQADCgUIDAAIAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgYICQAAAA==.Jaen:BAAANQAECgUIBAABNQAECgkJMgAEAEcQAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Jc='Jckruzy:BAAANQADCgIIAgAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcIEgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECn8tAAIQAAgKIwy0kwDhAQAQAAgKIwy0kwDhAQAAAA==.Kaladiin:BAABNQAECn8XAAIfAAcKewgfGQAQAQAfAAcKewgfGQAQAQAAAA==.Kallias:BAABNQAECn8sAAIbAAkKDyQGDQD7AgAbAAkKDyQGDQD7AgAAAA==.Kandistars:BAABNQAECn8iAAIOAAcKsBIZTACzAQAOAAcKsBIZTACzAQAAAA==.Karite:BAABNQAECn8yAAIgAAkKgR9VAQAyAgAgAAkKgR9VAQAyAgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Katte:BAAANQADCgMIAwAAAA==.Kaymyn:BAABNQAECn8pAAIGAAoKPBMmDAD6AQAGAAoKPBMmDAD6AQAAAA==.Kazar:BAAANQADCgUICgAAAA==.Kazen:BAAANQADCggIDQAAAA==.Kazenoth:BAAANQADCgUIBQAAAA==.',
Ke='Kehjistan:BAAANQAECgYIDgAAAA==.Kennychaoss:BAABNQAECn8tAAMCAAkKfxzmLADzAQACAAkKfxzmLADzAQADAAIKRQVtqgBSAAAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAABNQAECn8XAAIQAAYKzg2dpgDhAAAQAAYKzg2dpgDhAAAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Kobebrÿant:BAAANQABCgQIBAAAAA==.Koland:BAAANQADCgcIEQAAAA==.Kosseluna:BAABNQAECn8jAAIOAAgKpgcPMgAJAQAOAAgKpgcPMgAJAQAAAA==.Kostazu:BAABNQAECn8sAAIDAAkK7AxLPgBbAQADAAkK7AxLPgBbAQAAAA==.',
La='Laity:BAAANQAECgcIEQAAAA==.Lazariir:BAAANQAECggIEAAAAA==.Lazkal:BAAANQAECgUICAAAAA==.',
Le='Lebesgue:BAABNQAECn8mAAICAAoKLRmmKQAHAgACAAoKLRmmKQAHAgABNQAECgoKOgATAK4dAA==.Lebigmu:BAABNQAECn8fAAIdAAgK3BstDADWAQAdAAgK3BstDADWAQAAAA==.Leelee:BAAANQAECgYICQAAAA==.',
Li='Lilbones:BAAANQADCgUIBQABNQAECgoKQAAMAE8iAA==.Lisettar:BAAANQAECgcICgAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECgcIDQAIAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYICgABNQAECgcIBQAIAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAIAAAAAA==.Luralia:BAAANQAECgUICAAAAA==.',
Ly='Lycanbyte:BAAANQAECgQIBAAAAA==.Lylith:BAABNQAECn8vAAIaAAkK4BMeGAB4AQAaAAkK4BMeGAB4AQAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Maddicollins:BAAANQAECgIIAgABNQAECgoKOwASAJseAA==.Magdalena:BAABNQAECn8ZAAIQAAcKiwcynQD1AAAQAAcKiwcynQD1AAAAAA==.Magegrumpy:BAAANQADCgIIAgAAAA==.Maghavik:BAAANQADCgMIAwAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magmaface:BAAANQAECgYIDAAAAA==.Magnólia:BAABNQAECn8uAAICAAoKNCB8JgDLAgACAAoKNCB8JgDLAgAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQADCgUIBgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgYIDAAAAA==.Maribelle:BAAANQAECgQIBQABNQAECgkJMAAGAPsjAA==.Masha:BAAANQADCgIIAgAAAA==.Maximander:BAAANQAECgYIBQAAAA==.',
Me='Melomel:BAAANQAECgMIBQAAAA==.Melonsquezer:BAABNQAECn8sAAIeAAkK5Bx+EQCJAgAeAAkK5Bx+EQCJAgAAAA==.Menmei:BAAANQAECgMIBQAAAA==.Meow:BAAANQAECgQIBgAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAABNQAECn8WAAIhAAcKHwZFQgAgAQAhAAcKHwZFQgAgAQAAAA==.',
Mi='Milkman:BAAANQABCgEIAQABNQAECggIIgASAFEfAA==.Minien:BAABNQAECn8kAAIdAAoK3hQaEQBYAgAdAAoK3hQaEQBYAgAAAA==.Minko:BAAANQABCgUIBQAAAA==.Minore:BAAANQAECggIDgAAAA==.',
Mo='Moa:BAABNQAECn8jAAMOAAoKKRLDFgDqAQAOAAoKKRLDFgDqAQAJAAQKCQgGSACPAAABNQAECgoKKgAFAJMLAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAABNQAECn8zAAMcAAkKVhaVKgD2AQAcAAkKRRKVKgD2AQAQAAYKpRHmWwCKAQAAAA==.Moortz:BAAANQAECgIIAgABNQAECgoKKgAcANUhAA==.Morillic:BAABNQAECn8mAAQFAAoKTheTBACQAgAFAAkK/xeTBACQAgAHAAQKjBGzEAGqAAANAAMK8ROsFgBtAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAAANQAECgcIDQAAAA==.',
My='Myros:BAABNQAECn8sAAMGAAkKPRZ8CQB8AQABAAYKfxP3CAF+AQAGAAgKjBV8CQB8AQAAAA==.',
Na='Nadiaa:BAAANQADCggIDAAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgQIBAABNQAECgkJLAAGAD0WAA==.Narestor:BAABNQAECn8UAAMMAAkKMQnWggANAQAMAAgKCgrWggANAQAfAAEKIATzJgAaAAAAAA==.Nazervis:BAACNQAFFH8RAAMUAAUKohzYAwCkAQAUAAUKohzYAwCkAQAiAAEKGQHaGgAyAAA1AAQKfyoAAxQACgokJG4FADsDABQACgokJG4FADsDACMAAQrbH3IhAEsAAAE1AAUUBwgIACQAVQwA.',
Ne='Nekopunch:BAAANQAECgUJBQAAAA==.Nelcor:BAABNQAECn8YAAIiAAcKFA6EFQAVAQAiAAcKFA6EFQAVAQAAAA==.Nemesîs:BAAANQADCggICAAAAA==.Newhealer:BAABNQAECn8bAAMEAAkKcA1DfwCbAQAEAAkKcA1DfwCbAQAlAAIKTQWXIwBMAAAAAA==.',
No='Noint:BAABNQAECn8ZAAIKAAcK9AcRYgAcAQAKAAcK9AcRYgAcAQAAAA==.Nortree:BAAANQAECgMIBQAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECn8nAAMUAAcK2Bp6EQA8AgAUAAcK2Bp6EQA8AgAjAAQKGhYwEwD9AAAAAA==.',
Ny='Nymue:BAABNQAECn8pAAMDAAgKOBA1ewCxAQADAAgKOBA1ewCxAQAdAAEKAAB2OQApAAAAAA==.Nyyrivik:BAAANQADCgYJCAAAAA==.',
Nz='Nzoth:BAAANQADCgEIAQAAAA==.',
Oc='Octapie:BAABNQAECn8vAAICAAoK4hQbPQCkAQACAAoK4hQbPQCkAQAAAA==.',
Oh='Ohitsadragon:BAABNQAECn8bAAIUAAkKJwyGGADAAQAUAAkKJwyGGADAAQAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAABNQAECn8dAAIBAAUKAgvg1QCmAAABAAUKAgvg1QCmAAAAAA==.Oreoscruunit:BAAANQADCgYICAAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAABNQAECn8bAAIHAAYKVAMquQB/AAAHAAYKVAMquQB/AAAAAA==.',
Ow='Owl:BAABNQAECn8oAAIFAAoKhQdvBQCFAQAFAAoKhQdvBQCFAQAAAA==.Owlcatraz:BAACNQAFFH8HAAIOAAYKXgXxEwArAQAOAAYKXgXxEwArAQA1AAQKfzcAAg4ACQoeHXESADQDAA4ACQoeHXESADQDAAAA.',
Pa='Paendrag:BAAANQADCggIDQAAAA==.Panteragon:BAAANQAECgMIBQAAAA==.Panthean:BAABNQAECn8XAAIEAAcKviA7NQDlAQAEAAcKviA7NQDlAQAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgMIBQAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECn8tAAIEAAoKdBAMNADsAQAEAAoKdBAMNADsAQAAAA==.Persaud:BAABNQAECn8ZAAMNAAgKpiBKFwCyAQAHAAcK/R4iXABDAgANAAUK6x9KFwCyAQAAAA==.Pettacular:BAABNQAECn8xAAIQAAoK7hXUZABLAgAQAAoK7hXUZABLAgAAAA==.',
Ph='Phidra:BAABNQAECn8yAAMCAAkK7wppPgCeAQACAAkK7wppPgCeAQADAAYKxAHs8gCvAAAAAA==.',
Po='Poprocks:BAAANQAECgIIAwAAAA==.Potatogg:BAAANQAECgIIBgAAAA==.',
Pr='Predatorc:BAABNQAECn8gAAIQAAgKAgiHwgB9AQAQAAgKAgiHwgB9AQAAAA==.Primevil:BAAANQAECgcIEAAAAA==.Primevl:BAABNQAECn8oAAIOAAkKuQ0DIQB+AQAOAAkKuQ0DIQB+AQAAAA==.',
Py='Pyrissa:BAAANQABCgYIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQAECgUICwAAAA==.Raediant:BAABNQAECn8VAAIeAAgKwBMdKwCEAQAeAAgKwBMdKwCEAQAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Rahvinwulf:BAAANQADCgQIBAAAAA==.Raquel:BAABNQAECn8gAAICAAgKvgIHuwD1AAACAAgKvgIHuwD1AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBAAAAA==.Rectaltremor:BAAANQADCgYIBgAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEAAIAAAAAA==.Reign:BAAANQADCggIIwABNQAECgoKKgAFAJMLAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgAIAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECn8vAAIVAAkKhRG3HgCiAQAVAAkKhRG3HgCiAQAAAA==.Ris:BAABNQAECn82AAMBAAkKDBh5WwCbAQABAAgKWhd5WwCbAQAGAAIKPRSTHwBxAAAAAA==.Ritami:BAABNQAECn8dAAIcAAkKFCBwFgCoAgAcAAkKFCBwFgCoAgAAAA==.',
Ro='Roffy:BAABNQAECn8vAAIbAAoKGhILPwCbAQAbAAoKGhILPwCbAQAAAA==.Roknathar:BAABNQAECn8qAAMcAAoK1SEIBwBfAwAcAAoK1SEIBwBfAwAQAAEKAABdUQFBAAAAAA==.',
Sa='Saerin:BAABNQAECn8UAAIBAAgKWxv1iQBrAgABAAgKWxv1iQBrAgAAAA==.Saintmedes:BAAANQAECgQICAAAAA==.Sangoma:BAAANQADCgcJBwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.Saxmaster:BAAANQAECgIIAgAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQAECgMIBgAAAA==.Sehlia:BAABNQAECn81AAIHAAoKKxMzWwBFAgAHAAoKKxMzWwBFAgAAAA==.Selarae:BAAANQAECggICwABNQAECgkJHQAcABQgAA==.Selenis:BAAANQAECgcIBgABNQAECgkJNAALAEslAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAAANQAECgcIDQAAAA==.Shadowwizard:BAABNQAECn8UAAIBAAgKUBchsgAfAgABAAgKUBchsgAfAgABNQAECggIIgASAFEfAA==.Shadygrove:BAAANQABCgEIAQABNQAECgoKLgACADQgAA==.Shamania:BAAANQAECgcIDQAAAA==.Shaomai:BAABNQAECn8qAAMDAAoK1hyuawDdAQADAAYKoB2uawDdAQACAAoKixh/bwC9AQABNQAFFAUIDAABAIEgAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAAANQAECggIEQABNQAECgoKJgAEAIscAA==.Shidandfard:BAABNQAECn8vAAIBAAoKGCE+IAB5AgABAAoKGCE+IAB5AgAAAA==.Shifte:BAABNQAECn8zAAIYAAkKehBGCgCYAQAYAAkKehBGCgCYAQAAAA==.Shishkä:BAAANQAECggIDAAAAA==.Shiv:BAAANQADCggIFgABNQAECgIIAgAIAAAAAA==.Shockabeotch:BAABNQAECn8UAAIDAAgKYAu/mABnAQADAAgKYAu/mABnAQAAAA==.Shy:BAAANQAECgYIBwABNQAECgoKJgAEAIscAA==.Shêrra:BAAANQADCgEIAQAAAA==.',
Si='Silverwin:BAAANQAECgMIBQAAAA==.',
Sk='Skorvrax:BAAANQAECgUICwAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAFFAIIAgAAAA==.Slimage:BAABNQAECn8tAAIBAAoK8RdVlwBSAgABAAoK8RdVlwBSAgAAAA==.Slushius:BAAANQADCgEJAQAAAA==.',
Sm='Smashufacein:BAAANQAECgMIAQAAAA==.Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAABNQAECn8nAAIeAAgK8g/YGgAmAQAeAAgK8g/YGgAmAQAAAA==.',
Sp='Spaarkle:BAABNQAECn8XAAIOAAcKjgwvOADoAAAOAAcKjgwvOADoAAAAAA==.Spectrehawk:BAAANQAECgEIAQABNQAFFAMICAALAJYaAA==.Speçtre:BAACNQAFFH8IAAILAAMKlhqUCwDXAAALAAMKlhqUCwDXAAA1AAQKfy4AAgsACQrOIUoZAOMCAAsACQrOIUoZAOMCAAAA.',
St='Stheris:BAAANQADCgYJBgABNQAECgkJFAAMADEJAA==.',
Su='Supak:BAAANQAECgQIBQAAAA==.Suppabad:BAABNQAECn8yAAITAAkKIxsQCABWAgATAAkKIxsQCABWAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgQIBAABNQAECgkJMAAGAPsjAA==.Tadlight:BAAANQAECgMIBgAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tarysha:BAAANQAECggIDAAAAA==.Tattooman:BAAANQABCgIIAQAAAA==.Tazara:BAAANQAECgUIBwAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEAAAAA==.Ted:BAABNQAECn8tAAIDAAkKuRfTKgC0AQADAAkKuRfTKgC0AQAAAA==.Tehnegev:BAAANQAECgYIDQABNQAECgkJGgASAOkVAA==.Tehzealza:BAAANQAECgMIAwABNQAECgkJGgASAOkVAA==.Teias:BAAANQAECgUIBQABNQAECgoKPgAEABQcAA==.Temptressxx:BAAANQAECgUJDQAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAABNQAECn8UAAIEAAYKGxqHTAB/AQAEAAYKGxqHTAB/AQABNQAECgkJGQAWAFQdAA==.Themage:BAAANQADCggICAAAAA==.Thokmay:BAAANQAECgIIAgAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQAECgQICAAAAA==.',
Ti='Tiandrinna:BAABNQAECn87AAMmAAoKJxkCAgBVAgAmAAgKwRkCAgBVAgABAAoK0BRwNgAZAgAAAA==.Tightywhitey:BAAANQABCgYIBwAAAA==.Tigirius:BAAANQAECgMIAgAAAA==.Timkaoss:BAAANQAECgEIAgAAAA==.Timmyjudge:BAAANQAECgUIBwAAAA==.',
Tm='Tmagnet:BAAANQAECgMIBQAAAA==.',
To='Tophats:BAAANQABCgcIDgAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQADCgYJCQAAAA==.Tourmaline:BAAANQAECgIIBAABNQAECgoKLgACADQgAA==.',
Tr='Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQADCggIDgAAAA==.',
Tw='Tweedildee:BAACNQAFFH8GAAIGAAMKiQwRAgDZAAAGAAMKiQwRAgDZAAA1AAQKfzMAAgYACgoQGToDAGcCAAYACgoQGToDAGcCAAAA.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECgcIDQAIAAAAAA==.Unkindled:BAABNQAECn8iAAISAAgKUR/nLQBFAgASAAgKUR/nLQBFAgAAAA==.',
Va='Valdor:BAABNQAECn8qAAIKAAkKzBLnOADxAQAKAAkKzBLnOADxAQAAAA==.Valicous:BAAANQAECgQIBAAAAA==.Vandalie:BAAANQAECgYIBQABNQAECgkJGgAkACogAA==.Vaylorian:BAABNQAECn8mAAIJAAkKaiaJAAD4AwAJAAkKaiaJAAD4AwAAAA==.',
Ve='Velion:BAAANQAECgYICAAAAA==.Vellathor:BAAANQADCgQIBQABNQAECgkJFwABAAMOAA==.Velocity:BAABNQAECn8eAAMMAAkKTxnLSwCiAQAMAAkKZhfLSwCiAQAfAAUKiRwBEwBxAQAAAA==.Verianna:BAABNQAECn80AAMLAAkKSyUxCQBvAwALAAkKSyUxCQBvAwAkAAYKVxRCcwBKAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgoKKgAFAJMLAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAACNQAFFH8MAAIBAAUKgSBGDwAXAQABAAUKgSBGDwAXAQA1AAQKfyYAAgEACgqxJEIEAEYDAAEACgqxJEIEAEYDAAAA.',
Vu='Vulpixen:BAAANQAECggICQAAAA==.',
Wa='Wadumu:BAAANQAECgYIDQAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgMIBQAAAA==.',
Wi='Willothewisp:BAAANQADCgUIBQAAAA==.Willowy:BAABNQAECn8wAAIGAAkK+yNEAgBOAwAGAAkK+yNEAgBOAwAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECn8yAAIMAAkKeQrdXgBmAQAMAAkKeQrdXgBmAQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xanda:BAABNQAECn8YAAIMAAkK1Ay4TwCVAQAMAAkK1Ay4TwCVAQAAAA==.Xantyr:BAAANQAECgYICwAAAA==.',
Ya='Yarman:BAAANQAECgMIBQAAAA==.',
Yo='Yojimbro:BAAANQAECgUICAAAAA==.Yoshial:BAAANQAECgEIAwAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgQIBgAAAA==.Zalantir:BAAANQAECggIEAABNQAFFAUIDgAcADoVAA==.Zariski:BAAANQAECgQIBAABNQAECgoKOgATAK4dAA==.Zarthus:BAAANQAECgUICQAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECn8aAAISAAkK6RVdnwDjAQASAAkK6RVdnwDjAQAAAA==.',
Zi='Zirl:BAAANQAECgEIAgABNQAFFAUIDgAcADoVAA==.Ziyn:BAACNQAFFH8OAAMcAAUKOhXjCADcAAAcAAQKOhXjCADcAAAQAAEKAAAfNgBOAAA1AAQKf0MAAxAACgq3JVcHAKIDABAACgqnJVcHAKIDABwACQpxG4UgAEoCAAAA.',
Zo='Zoplete:BAAANQAECgcICwAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAAANQAECggIDgAAAA==.',
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
