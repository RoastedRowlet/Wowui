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

local lookup = {'Shaman-Restoration','Shaman-Elemental','Priest-Holy','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Priest-Shadow','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Warrior-Arms','Warlock-Destruction','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','Mage-Arcane','DemonHunter-Havoc','Monk-Windwalker','Warrior-Protection','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Devourer','Paladin-Holy','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Warrior-Fury','Rogue-Outlaw','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abhire:BAAANQAECgQIBQAAAA==.',
Ad='Advisor:BAACNQAFFH8GAAIBAAMKrxh6EgD0AAABAAMKrxh6EgD0AAA1AAQKfz8AAwEACgr3IlkJAHYDAAEACgr3IlkJAHYDAAIAAQo0D/MrAT0AAAAA.',
Ae='Aedali:BAAANQAECgEIAQAAAA==.Aería:BAABNQAECn8gAAIBAAkKIyCzHAD7AgABAAkKIyCzHAD7AgAAAA==.',
Ak='Akarm:BAAANQAECggICgAAAA==.',
Al='Alyà:BAABNQAECn8hAAIDAAkKCBs9FgD4AgADAAkKCBs9FgD4AgABNQAECgoKNQAEABMPAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECgkJOAAFAOckAA==.',
Ap='Aparajita:BAABNQAECn86AAIGAAoKiyCPIQD+AgAGAAoKiyCPIQD+AgABNQAECgQIBQAHAAAAAA==.Aphrodite:BAABNQAECn8rAAMDAAoKixwFJQDYAgADAAoKixwFJQDYAgAIAAMKdAlPOACiAAAAAA==.',
Ar='Arianda:BAABNQAECn8+AAIJAAoKGyN3AwAiAwAJAAoKGyN3AwAiAwAAAA==.Aristoleh:BAAANQAECggIEQABNQAFFAMICAACAKoMAA==.Armagedonn:BAAANQADCgQIBAAAAA==.Arolder:BAABNQAECn88AAMKAAoKlSPhEAAIAwAKAAoKhyLhEAAIAwALAAcKiSPIGgDZAgAAAA==.Artemis:BAAANQABCgYIBgABNQAECgoKKwADAIscAA==.Arwyndawn:BAAANQAECgEIAQABNQAECgkJJgABAPYOAA==.',
As='Astayuno:BAAANQAECgUIDQAAAA==.',
At='Atoadaso:BAABNQAECn8fAAIMAAkKrxh0bACCAQAMAAkKrxh0bACCAQAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQAECgQIBAAHAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECn81AAQEAAoKEw/DBwAcAgAEAAoKkwvDBwAcAgAGAAcKgA/laABiAQANAAEKxQ4eLwA7AAAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQAECgIIAgAAAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgMIBgAAAA==.Bankus:BAAANQADCgYICAAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECn8fAAMOAAgKDB6qWgBpAQAOAAUKcRiqWgBpAQAPAAUK3AhpRwCoAAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYIDQAAAA==.',
Bj='Björn:BAAANQAECgEIAgAAAA==.',
Bl='Blasphemar:BAAANQADCgUICQAAAA==.Blinkz:BAAANQAECgEJAQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boneycheese:BAAANQAECgIIAwABNQAECgoKIQADAOAPAA==.Boombástic:BAABNQAECn86AAMPAAkKaRQMGQD6AQAPAAkKaRQMGQD6AQAOAAUKUQj3egDfAAAAAA==.Boomco:BAABNQAECn86AAIQAAoKCAw+YwC4AQAQAAoKCAw+YwC4AQAAAA==.Bordinn:BAAANQADCgIIAgAAAA==.',
Br='Bravillius:BAAANQADCggIHwAAAA==.Breeti:BAAANQAECgMICgAAAA==.Broin:BAAANQAECgIIAwAAAA==.Bryda:BAAANQAECggICwAAAA==.',
Bu='Bubblecreep:BAAANQAECggIEAAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Burtangus:BAABNQAECn8jAAIGAAoKPxSfPwDkAQAGAAoKPxSfPwDkAQAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQAECgEIAQABNQAECgIIAwAHAAAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAABNQAECn8sAAIRAAgK5R0tCwD4AQARAAgK5R0tCwD4AQAAAA==.Calyssa:BAABNQAECn82AAISAAoKZB03MQByAgASAAoKZB03MQByAgAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQAECgcICQAHAAAAAA==.Capybara:BAAANQAECggIEAABNQAFFAYIFwALAGYfAA==.Cartan:BAACNQAFFH8GAAITAAIKOA4KCAB9AAATAAIKOA4KCAB9AAA1AAQKf0QAAhMACgrbH60EAD4DABMACgrbH60EAD4DAAAA.Castisteus:BAAANQADCggICQAAAA==.Cathum:BAAANQAECgcICAAAAA==.',
Ch='Charizaardx:BAACNQAFFH8TAAIUAAUKnQ+hBwAPAQAUAAUKnQ+hBwAPAQA1AAQKf18AAhQACgpbHiMEAHMCABQACgpbHiMEAHMCAAAA.Chromeski:BAABNQAECn8aAAIVAAoK4Q5FbACqAQAVAAoK4Q5FbACqAQAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAABNQAECn8mAAIMAAkKyBI3sQChAQAMAAkKyBI3sQChAQAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQAECgMIAwAAAA==.Creepymage:BAAANQAECgcICgABNQAECggIEAAHAAAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAABNQAECn8XAAIFAAcKfQV7HgD4AAAFAAcKfQV7HgD4AAAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECn8aAAIWAAkKdxaIQAC6AQAWAAkKdxaIQAC6AQAAAA==.',
Da='Dagul:BAAANQAECgIIAgAAAA==.Dalna:BAABNQAECn8qAAMTAAgKmw+RFQBpAQATAAgKmw+RFQBpAQAXAAUK7wcYTQDDAAAAAA==.Danksoul:BAAANQAECgIIAwABNQAECggIEAAHAAAAAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAABNQAECn8ZAAIQAAYKvQa5tAAEAQAQAAYKvQa5tAAEAQAAAA==.Darksaber:BAAANQAECgEIAQAAAA==.Darkwi:BAABNQAECn8rAAMNAAkK1hAOHwB2AQAGAAcKSw+EkAC9AQANAAYKqREOHwB2AQAAAA==.Dasthodan:BAAANQAECgUIBQABNQAECgoKGgAVAOEOAA==.Dayne:BAAANQAECgYIBgAAAA==.Dayus:BAAANQAECgMIAQAAAA==.',
Dc='Dctrpepper:BAAANQAECgQIBQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgkJGgAWAHcWAA==.Deathby:BAABNQAECn8cAAMMAAUKPgPOHAGiAAAMAAUKPgPOHAGiAAAYAAEKAADfRgAoAAAAAA==.Deathcore:BAAANQADCggIEAAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECn81AAQPAAkK5wafMwASAQAPAAkK5wafMwASAQAOAAUKxAAPggAqAAAZAAEKAADqTgAYAAAAAA==.Deldawalth:BAAANQAECgYICAAAAA==.Demonica:BAABNQAECn8pAAQaAAkK8QjTFADPAAAWAAgKVAnkRADgAAAaAAgKNwbTFADPAAAbAAMKcATfXACGAAAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECggIEwAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECn8+AAISAAoKJRJeYADXAQASAAoKJRJeYADXAQAAAA==.',
Do='Dominoes:BAABNQAECn8iAAIQAAkKgxBSdgCIAQAQAAkKgxBSdgCIAQAAAA==.Dotho:BAAANQAECggIAwAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Dragonzord:BAAANQADCggIEQAAAA==.Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAABNQAECn8cAAMOAAgKtgjfVgB7AQAOAAgKtgjfVgB7AQAPAAMK6gQGZQByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECn80AAIJAAoK/xwdCACaAgAJAAoK/xwdCACaAgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgAHAAAAAA==.',
Ec='Eclamp:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn8uAAIcAAkK0B/jHAAAAwAcAAkK0B/jHAAAAwAAAA==.',
Ei='Eiduartplis:BAAANQAECgcIEwABNQAFFAQICAAQAGoXAA==.',
El='Ellaana:BAAANQAECgQIBgAAAA==.Ellee:BAAANQAECgQIBAAAAA==.Elotarra:BAAANQADCgYIDgAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faema:BAAANQAECgQIBAAAAA==.Faethe:BAAANQADCgIIAgABNQAECgkJOAAFAOckAA==.Fananabanana:BAABNQAECn8YAAIEAAkKbQ5jDQCEAQAEAAkKbQ5jDQCEAQABNQAECgoKIQADAOAPAA==.',
Fe='Fenrith:BAAANQAECgEIAQAAAA==.Feorarlia:BAAANQAECgEIAQABNQAECgoKIQADAOAPAA==.',
Fi='Figaro:BAAANQAECgUIBwABNQAECgkJHQAdABQgAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECn8lAAIVAAcKHROT2gDSAQAVAAcKHROT2gDSAQAAAA==.',
Fl='Flameheart:BAAANQAECgQIBwAAAA==.Fleathulhu:BAABNQAECn83AAIDAAoKvheYWQAVAgADAAoKvheYWQAVAgAAAA==.Flungpu:BAAANQADCggIMgABNQAECggILwAQACMMAA==.',
Fo='Fostock:BAAANQAECgMIBgAAAA==.',
Fr='Frobenius:BAABNQAECn8bAAIDAAkKRBrtLgBTAgADAAkKRBrtLgBTAgABNQAFFAIIBgATADgOAA==.Frostmoon:BAAANQABCgcIDQAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Gangsta:BAAANQAECgIIAgAAAA==.Garwynn:BAABNQAECn87AAIRAAoKgBaMEwB7AQARAAoKgBaMEwB7AQAAAA==.',
Gh='Ghostkev:BAABNQAECn8sAAMQAAoKpxzMLQDkAgAQAAoKpxzMLQDkAgAdAAQKjQiNXACzAAAAAA==.Ghoulmaxing:BAAANQADCgEIAgABNQAECgoKQQAMAE8iAA==.',
Gl='Glaistia:BAAANQADCggIDAAAAA==.Glen:BAAANQAECgQIBgAAAA==.Glowstik:BAAANQAECgMIAwAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECn80AAIeAAoKGx8JBwCXAgAeAAoKGx8JBwCXAgAAAA==.Hankmoodie:BAABNQAECn8fAAIMAAkKqQrkbgB8AQAMAAkKqQrkbgB8AQAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.Haranda:BAAANQADCgcIBwAAAA==.Harmoni:BAAANQAECgMIAwABNQAECgkJOAAFAOckAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgMIBgAAAA==.Hexlight:BAAANQAECggICAAAAA==.',
Ho='Holysim:BAAANQAECgIIAgAAAA==.Honir:BAABNQAECn80AAIfAAkKDR+dDQDBAgAfAAkKDR+dDQDBAgAAAA==.Horderolder:BAAANQAECgQIBAAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEIAgAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECgkJOAAFAOckAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECn8tAAMNAAkKtAv8BgA4AQAGAAkKzQfJvgBPAQANAAgKpwr8BgA4AQAAAA==.Imooforu:BAAANQADCgUJBgABNQADCgUIDAAHAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgYICQAAAA==.Jaen:BAAANQAECgUIBQABNQAECgoKOQADAD0PAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Jc='Jckruzy:BAAANQADCgIIAgAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcIEgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECn8vAAIQAAgKIwy0kwDhAQAQAAgKIwy0kwDhAQAAAA==.Kaelya:BAAANQAECgEIAQABNQAECgoKNgASAGQdAA==.Kaladiin:BAABNQAECn8XAAIgAAcKewgfGQAQAQAgAAcKewgfGQAQAQAAAA==.Kallias:BAABNQAECn81AAIcAAkKFSTGCQBmAwAcAAkKFSTGCQBmAwAAAA==.Kandistars:BAABNQAECn8iAAIOAAcKsBIZTACzAQAOAAcKsBIZTACzAQAAAA==.Karite:BAABNQAECn84AAIhAAkKUyBQAQBtAgAhAAkKUyBQAQBtAgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Katte:BAAANQADCgMIAwAAAA==.Kaymyn:BAACNQAFFH8FAAIFAAIKzQKLCABrAAAFAAIKzQKLCABrAAA1AAQKfzIAAgUACgp2EyYMAPoBAAUACgp2EyYMAPoBAAAA.Kazar:BAAANQADCgUICgAAAA==.Kazen:BAAANQADCggIDgAAAA==.Kazenoth:BAAANQADCgUIBgAAAA==.',
Ke='Kehjistan:BAAANQAECgcIEAAAAA==.Kennychaoss:BAABNQAECn81AAMBAAkKfxwIIwB5AgABAAkKfxwIIwB5AgACAAIKRQVSxwBSAAAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAABNQAECn8dAAIQAAkKoA6ibACgAQAQAAkKoA6ibACgAQAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Kobebrÿant:BAAANQABCgQIBAAAAA==.Koland:BAAANQADCgcIEQAAAA==.Kosseluna:BAABNQAECn8qAAIOAAgKpgewPQABAQAOAAgKpgewPQABAQAAAA==.Kostazu:BAABNQAECn8sAAICAAkK7Az8UQBXAQACAAkK7Az8UQBXAQAAAA==.',
La='Laity:BAAANQAECgcIEQAAAA==.Lazariir:BAAANQAECgcIEwAAAA==.Lazkal:BAAANQAECgcIDgAAAA==.',
Le='Lebesgue:BAABNQAECn8xAAMBAAoKCRpoLwAyAgABAAoKCRpoLwAyAgACAAIKcgRMyQBOAAABNQAFFAIIBgATADgOAA==.Lebigmu:BAABNQAECn8nAAIeAAgK1h5YDgD5AQAeAAgK1h5YDgD5AQAAAA==.Leelee:BAAANQAECgYICQAAAA==.',
Li='Lilbones:BAAANQADCgUIBQABNQAECgoKQQAMAE8iAA==.Lisettar:BAAANQAECgcICgAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECggIEAAHAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYICgABNQAECgcIBQAHAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAHAAAAAA==.Luralia:BAAANQAECgUICAAAAA==.',
Ly='Lycanbyte:BAAANQAECgQIBAAAAA==.Lylith:BAABNQAECn81AAIbAAkK4BMUKAAEAgAbAAkK4BMUKAAEAgAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Maddicollins:BAAANQAECgcICgABNQAFFAIIBQASAFIOAA==.Magdalena:BAABNQAECn8eAAIQAAcKOAk9ogApAQAQAAcKOAk9ogApAQAAAA==.Magegrumpy:BAAANQAECgEIAQAAAA==.Maghavik:BAAANQADCgMIAwAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magmaface:BAAANQAECgYIDQAAAA==.Magnólia:BAABNQAECn8uAAIBAAoKNCB8JgDLAgABAAoKNCB8JgDLAgAAAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQAECgQIBgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgYIDAAAAA==.Maribelle:BAAANQAECgQICQABNQAECgkJOAAFAOckAA==.Masha:BAAANQADCgIIAgAAAA==.Mattdemòn:BAAANQAECgEIAQABNQAECgUIBgAHAAAAAA==.Maximander:BAAANQAECgcICwAAAA==.',
Me='Melomel:BAAANQAECgMIBgAAAA==.Melonsquezer:BAABNQAECn8xAAIfAAkKtB1+EQCJAgAfAAkKtB1+EQCJAgAAAA==.Menmei:BAAANQAECgMIBgAAAA==.Meow:BAAANQAECgQIBgAAAA==.Meowmix:BAAANQAECgEIAQAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAABNQAECn8cAAIIAAkK0AVFQgAgAQAIAAkK0AVFQgAgAQAAAA==.',
Mi='Milkman:BAAANQABCgEIAQABNQAECggIIgASAFEfAA==.Minbyunggyu:BAAANQADCgEIAQAAAA==.Minien:BAABNQAECn8oAAIeAAoKYRcaEQBYAgAeAAoKYRcaEQBYAgAAAA==.Minko:BAAANQABCgUIBQAAAA==.Minore:BAAANQAECggIDwAAAA==.',
Mo='Moa:BAABNQAECn8jAAMOAAoKKRKMHgDYAQAOAAoKKRKMHgDYAQAJAAQKCQgGSACPAAABNQAECgoKNQAEABMPAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAABNQAECn87AAMdAAkK8BZDGgBxAQAQAAYKQhOSdQCKAQAdAAkKSBNDGgBxAQAAAA==.Moortz:BAAANQAECgIIAgABNQAECgoKMAAdAHsiAA==.Morillic:BAABNQAECn8vAAQEAAoKfxeTBACQAgAEAAkK/xeTBACQAgANAAMK8RNUQADBAAAGAAUKcg6zEAGqAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAABNQAECn8VAAIGAAoKdBIvOAAAAgAGAAoKdBIvOAAAAgAAAA==.',
My='Myros:BAABNQAECn8xAAMFAAkKzBZrCgC2AQAFAAkKdBVrCgC2AQAVAAYKfxP3CAF+AQAAAA==.',
Na='Nadiaa:BAAANQADCggIDAAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgMIBQABNQAECgkJMQAFAMwWAA==.Narestor:BAABNQAECn8WAAMMAAkKMQk9ngALAQAMAAgKCgo9ngALAQAgAAMKXwUVIQBnAAABNQAFFAQIBwAiAFwFAA==.Nazervis:BAACNQAFFH8RAAMUAAUKohzYAwCkAQAUAAUKohzYAwCkAQAiAAEKGQHaGgAyAAA1AAQKfyoAAxQACgokJG4FADsDABQACgokJG4FADsDACMAAQrbH3IhAEsAAAE1AAUUBwgIACQAVQwA.',
Ne='Nekopunch:BAAANQAECgUJBQAAAA==.Nelcor:BAABNQAECn8fAAIiAAcKpQ5tFQBcAQAiAAcKpQ5tFQBcAQAAAA==.Nemesîs:BAAANQAECgEIAgAAAA==.Newhealer:BAABNQAECn8hAAMDAAoK4A8WZgBwAQADAAoK4A8WZgBwAQAlAAIKTQWXIwBMAAAAAA==.',
No='Noint:BAABNQAECn8aAAIKAAcK9AcRYgAcAQAKAAcK9AcRYgAcAQAAAA==.Nortree:BAAANQAECgMIBgAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECn8nAAMUAAcK2Bp6EQA8AgAUAAcK2Bp6EQA8AgAjAAQKGhYwEwD9AAAAAA==.',
Ny='Nymue:BAABNQAECn8pAAMCAAgKOBA1ewCxAQACAAgKOBA1ewCxAQAeAAEKAAB2OQApAAAAAA==.Nyyrivik:BAAANQADCgcIDwAAAA==.',
Nz='Nzoth:BAAANQADCgEIAQAAAA==.',
Oc='Octapie:BAABNQAECn84AAIBAAoKbxWTOAAGAgABAAoKbxWTOAAGAgAAAA==.',
Oh='Ohitsadragon:BAABNQAECn8iAAIUAAoKZA3/CQCbAQAUAAoKZA3/CQCbAQAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAABNQAECn8dAAIVAAUKAgvyTAEPAQAVAAUKAgvyTAEPAQAAAA==.Orcburger:BAAANQAECgUIBwAAAA==.Oreoscruunit:BAAANQAECgcICQAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAABNQAECn8bAAIGAAYKVAN5AgHHAAAGAAYKVAN5AgHHAAAAAA==.',
Ow='Owl:BAABNQAECn8oAAIEAAoKhQcMCgBfAQAEAAoKhQcMCgBfAQAAAA==.Owlcatraz:BAACNQAFFH8HAAIOAAYKXgXxEwArAQAOAAYKXgXxEwArAQA1AAQKfz8AAg4ACQo3IHESADQDAA4ACQo3IHESADQDAAAA.',
Pa='Paendrag:BAAANQAECgQIBAAAAA==.Panteragon:BAAANQAECgMIBgAAAA==.Panthean:BAABNQAECn8XAAIDAAcKviA9SgDWAQADAAcKviA9SgDWAQAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgMIBgAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECn81AAIDAAoK7xMVMQBJAgADAAoK7xMVMQBJAgAAAA==.Persaud:BAABNQAECn8ZAAMNAAgKpiBKFwCyAQAGAAcK/R4iXABDAgANAAUK6x9KFwCyAQAAAA==.Pettacular:BAABNQAECn83AAIQAAoK7hVGRgAKAgAQAAoK7hVGRgAKAgAAAA==.',
Ph='Phidra:BAABNQAECn84AAMBAAkK7wqcUgCWAQABAAkK7wqcUgCWAQACAAYKxAHs8gCvAAAAAA==.',
Po='Poprocks:BAAANQAECgIIAwAAAA==.Potatogg:BAAANQAECgQICwAAAA==.',
Pr='Predatorc:BAABNQAECn8gAAIQAAgKAgiHwgB9AQAQAAgKAgiHwgB9AQAAAA==.Primevil:BAAANQAECgcIEAAAAA==.Primevl:BAABNQAECn8wAAIOAAkKoQ8rJgCUAQAOAAkKoQ8rJgCUAQAAAA==.',
Pu='Puspatroll:BAAANQAECgEIAQAAAA==.',
Py='Pyrissa:BAAANQABCgYIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Qu='Quarz:BAAANQADCgIIAgAAAA==.',
Ra='Radïance:BAABNQAECn8XAAMSAAkKLwnWrQA0AQASAAkKLwnWrQA0AQAfAAEKAAAscQAAAAAAAA==.Raediant:BAABNQAECn8fAAIfAAoKkBIdKwCEAQAfAAoKkBIdKwCEAQAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Rahvinwulf:BAAANQADCgQIBAAAAA==.Raquel:BAABNQAECn8gAAIBAAgKvgIHuwD1AAABAAgKvgIHuwD1AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBAAAAA==.Rectaltremor:BAAANQADCgYIBgAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEAAHAAAAAA==.Reign:BAAANQADCggIIwABNQAECgoKNQAEABMPAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgAHAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECn83AAIWAAkKZRSBIADMAQAWAAkKZRSBIADMAQAAAA==.Ris:BAABNQAECn88AAMFAAkK7hjtFAAIAQAVAAgK7BcKdwCPAQAFAAQK7hftFAAIAQAAAA==.Ritami:BAABNQAECn8dAAIdAAkKFCBwFgCoAgAdAAkKFCBwFgCoAgAAAA==.',
Ro='Roffy:BAABNQAECn84AAIcAAoKTBMcLwA0AgAcAAoKTBMcLwA0AgAAAA==.Roknathar:BAABNQAECn8wAAMdAAoKeyIIBwBfAwAdAAoKeyIIBwBfAwAQAAEKAABdUQFBAAAAAA==.',
Ru='Ruitiny:BAAANQAECgEIAQAAAA==.',
Sa='Saerin:BAABNQAECn8UAAIVAAgKWxv1iQBrAgAVAAgKWxv1iQBrAgAAAA==.Saintmedes:BAAANQAECgQICAAAAA==.Sangoma:BAAANQADCgcJBwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.Saxmaster:BAAANQAECgIIAgAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQAECgMIBgAAAA==.Sehlia:BAABNQAECn88AAIGAAoKehQBRQDRAQAGAAoKehQBRQDRAQAAAA==.Selarae:BAAANQAECggIEAABNQAECgkJHQAdABQgAA==.Selenis:BAAANQAECgYIEAABNQAECgkJOgALAJ8lAA==.Seraphyne:BAAANQAECgEIAQABNQAECgUIDwAHAAAAAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAABNQAECn8UAAIKAAgK0QW/WAD2AAAKAAgK0QW/WAD2AAAAAA==.Shadowwizard:BAABNQAECn8UAAIVAAgKUBchsgAfAgAVAAgKUBchsgAfAgABNQAECggIIgASAFEfAA==.Shadygrove:BAAANQAECgEIAQABNQAECgoKLgABADQgAA==.Shamania:BAAANQAECgcIDQABNQAECggIEAAHAAAAAA==.Shaomai:BAABNQAECn8sAAMCAAoK1hyuawDdAQACAAYKoB2uawDdAQABAAoKGxl/bwC9AQABNQAFFAUIDAAVAIEgAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAABNQAECn8UAAIiAAoKuQfyGQAcAQAiAAoKuQfyGQAcAQABNQAECgoKKwADAIscAA==.Shidandfard:BAABNQAECn8vAAIVAAoKGCGQMwAjAwAVAAoKGCGQMwAjAwAAAA==.Shifte:BAABNQAECn87AAIZAAkK/RGUDgCPAQAZAAkK/RGUDgCPAQAAAA==.Shishkä:BAAANQAECggIDAAAAA==.Shiv:BAAANQADCggIFgABNQAECgIIAgAHAAAAAA==.Shockabeotch:BAABNQAECn8WAAICAAgK7Qu/mABnAQACAAgK7Qu/mABnAQAAAA==.Shy:BAAANQAECgcIDQABNQAECgoKKwADAIscAA==.Shêrra:BAAANQADCgEIAQAAAA==.',
Si='Silverwin:BAAANQAECgMIBgAAAA==.',
Sk='Skorvrax:BAAANQAECgUIDQAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAFFAIIAgAAAA==.Slimage:BAABNQAECn8zAAIVAAoKfhhVlwBSAgAVAAoKfhhVlwBSAgAAAA==.Slushius:BAAANQADCgEJAQAAAA==.',
Sm='Smashufacein:BAAANQAECgMIAwAAAA==.Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAABNQAECn8uAAIfAAgKsBDCHwA7AQAfAAgKsBDCHwA7AQAAAA==.',
Sp='Spaarkle:BAABNQAECn8XAAIOAAcKjgxeRQDcAAAOAAcKjgxeRQDcAAAAAA==.Spectrehawk:BAAANQAECgEIAQABNQAFFAMICAALAJYaAA==.Speçtre:BAACNQAFFH8IAAILAAMKlhqkDwDMAAALAAMKlhqkDwDMAAA1AAQKfy4AAgsACQrOIUoZAOMCAAsACQrOIUoZAOMCAAAA.',
St='Stheris:BAAANQADCgYJBgABNQAFFAQIBwAiAFwFAA==.',
Su='Supak:BAAANQAECgQIBQAAAA==.Suppabad:BAABNQAECn84AAITAAkKQRscCwBLAgATAAkKQRscCwBLAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgQIBAABNQAECgkJOAAFAOckAA==.Tadlight:BAAANQAECgMIBgAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tarysha:BAAANQAECgcIDgAAAA==.Tattooman:BAAANQAECgEIAQAAAA==.Tayoma:BAAANQABCgYICgAAAA==.Tazara:BAAANQAECgYICQAAAA==.Tazmaniaa:BAAANQAECgEIAQAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEAAAAA==.Ted:BAABNQAECn83AAICAAoKDR0wGgBzAgACAAoKDR0wGgBzAgAAAA==.Tehnegev:BAAANQAECgYIDQABNQAECgkJHwASAMQYAA==.Tehzealza:BAAANQAECgMIAwABNQAECgkJHwASAMQYAA==.Teias:BAAANQAECgUIBQABNQAFFAMIBgADALEPAA==.Temptressxx:BAAANQAECgUJDQAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAABNQAECn8YAAIDAAcKMhcOVgCpAQADAAcKMhcOVgCpAQABNQAECgkJGQAXAFQdAA==.Themage:BAAANQADCggICAAAAA==.Thokmay:BAAANQAECgIIAgAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQAECgQICAAAAA==.',
Ti='Tiandrinna:BAABNQAECn87AAMmAAoKJxkCAgBVAgAmAAgKwRkCAgBVAgAVAAoK0BQlSwAHAgAAAA==.Tightywhitey:BAAANQABCgYIBwAAAA==.Tigirius:BAAANQAECgMIAwAAAA==.Timkaoss:BAAANQAECgEIAgAAAA==.Timmyjudge:BAAANQAECgUIBwAAAA==.',
Tm='Tmagnet:BAAANQAECgMIBgAAAA==.',
To='Tophats:BAAANQABCgcIDgAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQADCgYJCQAAAA==.Tourmaline:BAAANQAECgIIBwABNQAECgoKLgABADQgAA==.Toyoma:BAAANQAECgEIAQAAAA==.',
Tr='Trancepants:BAAANQAECggICgAAAA==.Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQAECgEIAQAAAA==.',
Tw='Tweedildee:BAACNQAFFH8JAAIFAAMK8RKYAgDgAAAFAAMK8RKYAgDgAAA1AAQKfz0AAgUACgrkGZcEAG0CAAUACgrkGZcEAG0CAAAA.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECggIEAAHAAAAAA==.Unkindled:BAABNQAECn8iAAISAAgKUR89RQAnAgASAAgKUR89RQAnAgAAAA==.',
Va='Valdor:BAABNQAECn8yAAIKAAkKCxPnOADxAQAKAAkKCxPnOADxAQAAAA==.Valicous:BAAANQAECgQIBAAAAA==.Vandalie:BAAANQAECgQICQABNQAECgkJGgAkACogAA==.Vaskie:BAEANQAECggICQABNQAFFAYIEgAMAHsUAA==.Vaylorian:BAABNQAECn8mAAIJAAkKaiaJAAD4AwAJAAkKaiaJAAD4AwAAAA==.',
Ve='Velion:BAAANQAECgYICAAAAA==.Vellathor:BAAANQADCgQIBQABNQAECgoKGgAVAOEOAA==.Velocity:BAABNQAECn8lAAMMAAoKPBp0MABWAgAMAAoKHxp0MABWAgAgAAUKiRwBEwBxAQAAAA==.Verianna:BAABNQAECn86AAMLAAkKnyUxCQBvAwALAAkKnyUxCQBvAwAkAAYKVxRCcwBKAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgoKNQAEABMPAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAACNQAFFH8MAAIVAAUKgSASFgAMAQAVAAUKgSASFgAMAQA1AAQKfycAAhUACgq4JCMJAC0DABUACgq4JCMJAC0DAAAA.',
Vu='Vulpixen:BAAANQAECggIEQAAAA==.',
Wa='Wadumu:BAAANQAECgYIDgAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgMIBQAAAA==.',
Wi='Willothewisp:BAAANQADCgUIBQAAAA==.Willowy:BAABNQAECn84AAIFAAkK5yREAgBOAwAFAAkK5yREAgBOAwAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECn84AAIMAAkKqQrqdABsAQAMAAkKqQrqdABsAQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xanda:BAABNQAECn8YAAIMAAkK1Ax7aACOAQAMAAkK1Ax7aACOAQAAAA==.Xantyr:BAAANQAECgcICwAAAA==.',
Ya='Yarman:BAAANQAECgMIBgAAAA==.',
Yo='Yojimbro:BAAANQAECgUICAAAAA==.Yoshial:BAAANQAECgEIAwAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgQICAAAAA==.Zalantir:BAAANQAECggIEAABNQAFFAYIDwAdALgWAA==.Zariski:BAAANQAECgUICQABNQAFFAIIBgATADgOAA==.Zarthus:BAAANQAECgUICgAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECn8fAAISAAkKxBhdnwDjAQASAAkKxBhdnwDjAQAAAA==.Zera:BAAANQAECgEIAgABNQAECgkJOgALAJ8lAA==.',
Zi='Zirl:BAAANQAECgEIAgABNQAFFAYIDwAdALgWAA==.Ziyn:BAACNQAFFH8PAAMdAAYKuBZdDADSAAAdAAQKOhVdDADSAAAQAAIKMBsQJABgAAA1AAQKf0gAAxAACgq3JVcHAKIDABAACgqnJVcHAKIDAB0ACQpxG4UgAEoCAAAA.',
Zo='Zoplete:BAABNQAECn8ZAAIVAAoKdA/+TgD8AQAVAAoKdA/+TgD8AQAAAA==.',
Zy='Zyp:BAAANQAECgEIAQAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAABNQAECn8UAAIGAAkKVwZ1jAANAQAGAAkKVwZ1jAANAQAAAA==.',
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
