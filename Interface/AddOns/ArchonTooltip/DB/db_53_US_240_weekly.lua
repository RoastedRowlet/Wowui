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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Warlock-Destruction','Druid-Restoration','Druid-Feral','DeathKnight-Blood','Shaman-Elemental','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Monk-Mistweaver','Paladin-Retribution','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Evoker-Preservation','Shaman-Restoration','Monk-Brewmaster','Mage-Frost','Mage-Arcane','Paladin-Protection','Monk-Windwalker','Warrior-Arms','Shaman-Enhancement',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aardin:BAABNQAECn8xAAMBAAoKtA+5KwDPAQACAAoKSwz0MgARAgABAAkKpw25KwDPAQAAAA==.',
Ad='Adyrill:BAAANQADCgYICwAAAA==.',
Ai='Ailani:BAAANQADCgIIAgAAAA==.Airnantas:BAAANQADCgEIAQABNQAECggIJgADAEkVAA==.',
Al='Allure:BAABNQAECn8cAAMEAAkKDRWnQAC5AQAEAAkK9BKnQAC5AQAFAAMK4RymIQC2AAAAAA==.',
Am='Amadin:BAABNQAECn9EAAIGAAoKGiC4BwBPAwAGAAoKGiC4BwBPAwAAAA==.Amoralibash:BAAANQAECgcIDwABNQAECggIJgADAEkVAA==.',
An='Anguskhan:BAAANQADCggIFQAAAA==.Anhafal:BAAANQADCgYIDwAAAA==.',
Ao='Aoife:BAABNQAECn8vAAIGAAgK3x9oHQBZAgAGAAgK3x9oHQBZAgAAAA==.Aosin:BAAANQAECgYICQAAAA==.',
Ap='Apocalipze:BAAANQADCgUICwAAAA==.',
Ar='Aragosa:BAAANQABCgQIBQAAAA==.Archdruid:BAAANQAECggICAAAAA==.Arileous:BAAANQAECgEIAQAAAA==.Aroes:BAAANQADCgUIBgAAAA==.Artemiza:BAAANQABCgcJDgAAAA==.',
As='Ashariel:BAAANQADCgYICwAAAA==.Asylum:BAAANQAECgQIDwAAAA==.',
Ay='Ayeamanoob:BAAANQABCgIIAgABNQABCgYICgAHAAAAAA==.',
Ba='Bambiná:BAAANQADCgQIBQAAAA==.Bar:BAAANQAECgMIBAAAAA==.Batshaun:BAAANQADCgYIBgAAAA==.Bault:BAAANQAECgEIAQABNQAECgMIBAAHAAAAAA==.',
Be='Benadryl:BAABNQAECn8XAAIIAAYKERfdBwD1AAAIAAYKERfdBwD1AAAAAA==.',
Bh='Bhalen:BAAANQADCggIDAAAAA==.',
Bl='Bloodpear:BAAANQAECgMIAwABNQAFFAEIAQAHAAAAAA==.',
Br='Brakey:BAAANQAECgYIEAAAAA==.Briar:BAABNQAECn8nAAQJAAkKMAu7OwBDAQAJAAgK3Qe7OwBDAQADAAcKnQZJcgABAQAKAAcKZA6bFgDTAAAAAA==.Britnysteers:BAAANQADCgEIAQAAAA==.Brungar:BAAANQAECggIDQAAAA==.',
Bu='Bubblybear:BAAANQAECgYIEAAAAA==.Bucksdk:BAABNQAECn8ZAAILAAoKHgklaABSAQALAAoKHgklaABSAQAAAA==.Buckshotheal:BAAANQADCgMIAwABNQAECgoKGQALAB4JAA==.Butterworm:BAAANQAECgEIAQAAAA==.',
Ca='Castiél:BAAANQADCgYIDAAAAA==.Caín:BAAANQADCgcICgAAAA==.',
Ch='Chuckroast:BAABNQAECn8dAAIMAAYKRAofcADCAAAMAAYKRAofcADCAAAAAA==.',
Cy='Cynastus:BAABNQAECn8cAAILAAcKNhkTOwAZAgALAAcKNhkTOwAZAgAAAA==.Cyrandalord:BAACNQAFFH8GAAINAAQKZRCqEAAiAQANAAQKZRCqEAAiAQA1AAQKfy8ABA0ACgrwHb00AJUCAA0ACgrSHb00AJUCAA4AAgrHGBMcAIYAAA8AAQoAAHiNAB0AAAAA.Cyrandalorr:BAAANQAECgYICwABNQAFFAQIBgANAGUQAA==.',
Da='Danteghost:BAAANQADCgYIBgAAAA==.',
De='Deathzdemize:BAACNQAFFH8aAAQQAAgKAB+6AgAUAgAQAAYKqh+6AgAUAgARAAEKsxsFCwBfAAALAAEKAAAEKgBOAAA1AAQKf28ABBAACgrnJjYAAAwEABAACgrnJjYAAAwEABEAAgrfJhKQAOgAAAsAAQooHsO6AFIAAAAA.Demonbane:BAABNQAECn8kAAMSAAgKiQ4/MADAAQASAAgKiA4/MADAAQAEAAIKmgUiaQA1AAAAAA==.Demíse:BAAANQADCgEIAQAAAA==.',
Di='Dinduscuffin:BAAANQADCgcIBwABNQAFFAgIGgAQAAAfAA==.Dirtpear:BAAANQAFFAEIAQAAAA==.',
Do='Doci:BAAANQADCggJFQABNQAECgcIEQAHAAAAAA==.',
Dr='Dragundeznut:BAAANQAECgMIAwABNQAFFAgIGgAQAAAfAA==.Drakythor:BAAANQAECgEIAQABNQAECgoKLQATAFQaAA==.Dreadnought:BAAANQADCgUIBQAAAA==.Druisy:BAAANQAECgYIDgAAAA==.',
Dy='Dyrillin:BAABNQAECn8fAAIUAAkKZhRbiQAUAgAUAAkKZhRbiQAUAgAAAA==.',
El='Eleonna:BAAANQADCgEIAQAAAA==.',
Em='Emberblaze:BAAANQADCgcIBwAAAA==.Emiragosa:BAAANQAECgEIAwABNQAECgIIAgAHAAAAAA==.',
Er='Erazar:BAAANQADCgUIBQABNQAFFAQIBgANAGUQAA==.',
Et='Ethelstan:BAAANQADCgMIAwAAAA==.',
Ev='Evoker:BAACNQAFFH8HAAIVAAQKLwnxBgD7AAAVAAQKLwnxBgD7AAA1AAQKfyUAAhUACQoVHCoFAJwCABUACQoVHCoFAJwCAAE1AAUUBQgFABIA+AQA.',
Ex='Exorcizim:BAAANQAECgEIAQAAAA==.',
Fa='Facethegon:BAABNQAECn9OAAMWAAoK1x/lFwCXAgAXAAkKyBkQFAC/AgAWAAkKdCHlFwCXAgAAAA==.Facethezoom:BAAANQAECgQIBAABNQAECgoKTgAWANcfAA==.Father:BAAANQAECgQIBgAAAA==.',
Fe='Feld:BAAANQADCgYIDQAAAA==.Felreaper:BAAANQADCgMIAwAAAA==.Feziwig:BAAANQADCgYIDgAAAA==.',
Fi='Fizbar:BAAANQADCgQIBAABNQAECgUIEAAHAAAAAA==.Fiztweaver:BAAANQADCggIDgABNQAECgUIEAAHAAAAAA==.Fizzywater:BAAANQAECgUIEAAAAA==.',
Fo='Fonzo:BAAANQADCgcICgAAAA==.Forloyn:BAAANQAECgIIAgAAAA==.',
Fr='Frozarath:BAAANQADCggICAAAAA==.Frozntempest:BAAANQADCgYIDgAAAA==.',
Ga='Galairn:BAAANQAECgQICAAAAA==.Garlatha:BAABNQAECn8oAAIYAAgKPRawCwAHAgAYAAgKPRawCwAHAgAAAA==.',
Ge='Gellicaan:BAAANQADCgYIFgAAAA==.Geves:BAAANQAECgQICAAAAA==.',
Go='Gortry:BAAANQAECggIEAAAAA==.',
Gr='Gromdred:BAAANQADCgEIAQAAAA==.Gryfter:BAAANQADCggIDAAAAA==.',
He='Hedgehog:BAAANQADCgYIBQAAAA==.Helbrecht:BAAANQADCgUIBQAAAA==.Hellgar:BAAANQAECgQIDQAAAA==.Hellraid:BAABNQAECn8mAAIDAAgKSRWCJABgAQADAAgKSRWCJABgAQAAAA==.',
Ho='Holysquid:BAAANQADCggIDAAAAA==.Hordebreaker:BAAANQADCggICAAAAA==.',
Hu='Humblépié:BAAANQADCgMIAwAAAA==.',
Hy='Hydrosavior:BAABNQAECn8lAAINAAoKHRi0EwDIAgANAAoKHRi0EwDIAgAAAA==.',
Il='Illbegood:BAAANQADCgQIBAAAAA==.',
Im='Impearing:BAAANQADCgcIBwABNQAFFAEIAQAHAAAAAA==.',
In='Indaback:BAAANQADCgEIAQAAAA==.Initalog:BAAANQADCgUIBQAAAA==.',
It='Ithlaris:BAAANQADCgUIBQAAAA==.',
Iz='Izakura:BAAANQAECgYIBgAAAA==.Izumi:BAABNQAECn8jAAIZAAkK/xfuEQCMAgAZAAkK/xfuEQCMAgABNQAECgoKHQAaADEfAA==.',
Ja='Jab:BAABNQAECn8VAAILAAgKCg6QRwDEAAALAAgKCg6QRwDEAAAAAA==.Jamama:BAAANQADCgMIAwAAAA==.Jasperr:BAABNQAECn82AAILAAoKvhd7FAAFAgALAAoKvhd7FAAFAgAAAA==.Jaywalker:BAAANQADCgYIBgAAAA==.',
Je='Jenai:BAAANQADCgMIBQAAAA==.',
Ji='Jigsaw:BAAANQADCgYIBgAAAA==.Jinmoso:BAAANQADCgcICwAAAA==.Jinsha:BAABNQAECn8cAAIDAAkKMRlCHgCXAQADAAkKMRlCHgCXAQAAAA==.Jiéqu:BAABNQAECn8bAAIbAAkKVBZUDgAQAgAbAAkKVBZUDgAQAgAAAA==.',
Jo='Jojodimojo:BAAANQADCgYIEwAAAA==.Joker:BAAANQADCgYICgAAAA==.Jomama:BAABNQAECn8UAAIUAAkKXAvT1gBuAQAUAAkKXAvT1gBuAQAAAA==.',
['Jö']='Jörmungandr:BAAANQADCgYIFQAAAA==.',
Ka='Kaitnahar:BAAANQADCggICQABNQAECggIJgADAEkVAA==.Kalunom:BAAANQABCggIBQAAAA==.Karasendreth:BAAANQADCgEIAQAAAA==.Katiperry:BAABNQAECn8dAAIcAAYKwA61GAAxAQAcAAYKwA61GAAxAQAAAA==.',
Kk='Kk:BAABNQAECn8cAAIaAAcKzxnWPAClAQAaAAcKzxnWPAClAQAAAA==.',
Ky='Kylowren:BAAANQADCgcIBgAAAA==.',
La='Laloyd:BAAANQABCgIIAgAAAA==.Lawbreaker:BAAANQAECgMIBQAAAA==.',
Le='Leafygaga:BAAANQADCgIIAgAAAA==.Leora:BAAANQADCggIDAAAAA==.',
Li='Liana:BAAANQADCgMIAwAAAA==.',
Lo='Lobotamy:BAAANQADCgcIFQAAAA==.Lockycharms:BAAANQADCgYIFAAAAA==.Loremis:BAAANQADCgYIGAAAAA==.',
Lu='Lunary:BAAANQADCgUIBQABNQAFFAQIBgANAGUQAA==.Lunatari:BAAANQAECgQIBAAAAA==.',
Ma='Maal:BAAANQAECgEIAQAAAA==.Magetank:BAABNQAECn8rAAIdAAgKiAo3fwBEAQAdAAgKiAo3fwBEAQAAAA==.Marche:BAABNQAECn80AAIPAAoK6iJLBQCEAwAPAAoK6iJLBQCEAwAAAA==.Mathendistus:BAAANQAECgQIBwABNQAECggIJgADAEkVAA==.',
Me='Meattwo:BAAANQADCgIIAgAAAA==.Meliôdas:BAABNQAECn8ZAAIYAAcK/grQDwDvAAAYAAcK/grQDwDvAAAAAA==.Mendelson:BAAANQABCgIIAgABNQABCgYICgAHAAAAAA==.Mew:BAAANQAECggIDgAAAA==.',
Mo='Mommy:BAAANQAECgUICwAAAA==.Moonspinner:BAAANQADCgIIAgAAAA==.Mooädib:BAAANQADCggIKAAAAA==.',
Mu='Musketeer:BAAANQADCgMIAwAAAA==.',
My='Mygore:BAAANQADCgEIAQAAAA==.Myrcy:BAAANQADCggIFQAAAA==.Mysteia:BAABNQAECn8tAAITAAoKVBr/DAC0AgATAAoKVBr/DAC0AgAAAA==.',
['Mø']='Mørdréd:BAAANQAECgIIBAAAAA==.',
Na='Naughtyhuman:BAAANQABCggIFwAAAA==.',
Ne='Necrobijuan:BAAANQADCgcICQAAAA==.Neodragoon:BAABNQAECn8ZAAIeAAkKxw9xEwBxAQAeAAkKxw9xEwBxAQAAAA==.',
Ni='Nihilist:BAABNQAECn8vAAILAAkKZBhOLgBbAgALAAkKZBhOLgBbAgAAAA==.Nihlliance:BAABNQAECn8cAAMQAAcKbQ4YQAAYAQAQAAcKzA0YQAAYAQALAAUKngwIUQCkAAAAAA==.Nitequilz:BAABNQAECn80AAIaAAkKSBWhMQDbAQAaAAkKSBWhMQDbAQAAAA==.',
No='Noblessyou:BAAANQABCgUJCAABNQABCgYICgAHAAAAAA==.',
Ob='Obeejoowan:BAAANQADCggIFwAAAA==.Obeewand:BAAANQADCggIGAAAAA==.Obijuan:BAAANQADCggIQgAAAA==.',
Oh='Ohurru:BAAANQADCgUIBQAAAA==.',
Ou='Ouch:BAAANQAECgUIEgAAAA==.',
Pa='Pandapunch:BAABNQAECn8oAAIfAAgK9xNCGABzAQAfAAgK9xNCGABzAQAAAA==.',
Pl='Plateguy:BAAANQAECgUIDAAAAA==.',
Po='Poxx:BAABNQAECn8cAAIdAAgK6yBWWwDJAgAdAAgK6yBWWwDJAgABNQAFFAgIFAABAO8gAA==.',
Qu='Quigonjin:BAABNQAECn8iAAIWAAkKAxRgSQDCAQAWAAkKAxRgSQDCAQAAAA==.Quinci:BAAANQABCggIEwAAAA==.',
Ra='Raelynixii:BAAANQADCgcIEwAAAA==.Raistliin:BAAANQAECgQIBAAAAA==.Raksi:BAAANQADCgIIAgAAAA==.Ranker:BAAANQADCgUICgAAAA==.Rastion:BAAANQADCgYIFwAAAA==.',
Re='Redacted:BAAANQADCgYIGAAAAA==.Rend:BAAANQADCgQIBAAAAA==.',
Ri='Rills:BAAANQADCgQIBAAAAA==.',
Ro='Rokku:BAAANQADCgYJBgAAAA==.Rollepolle:BAAANQAECgIIAgABNQAFFAgIGgAQAAAfAA==.Rossini:BAAANQADCgEIAQAAAA==.Roxoglam:BAAANQADCgYIBgAAAA==.',
Ru='Rueittrebeck:BAAANQABCgYICgABNQABCgYICgAHAAAAAA==.Rushs:BAAANQABCgYICgAAAA==.',
Ry='Ryleigh:BAAANQADCgQIBAAAAA==.Rynron:BAAANQADCgUICAAAAA==.',
Sa='Samraj:BAAANQAECgQICgAAAA==.',
Se='Seithr:BAAANQADCgEIAQAAAA==.Selexa:BAAANQADCgIIAgAAAA==.Sempiternal:BAACNQAFFH8QAAIGAAQKhBPeCgA0AQAGAAQKhBPeCgA0AQA1AAQKfzsAAgYACgpYFRdAAGQCAAYACgpYFRdAAGQCAAAA.Sentry:BAAANQADCgQIBAAAAA==.',
Sh='Shadowreaper:BAAANQABCgQIBAAAAA==.Shambali:BAAANQAECgUICAABNQAECgkJFAAUAFwLAA==.Shaunanigans:BAAANQAECgcIBgAAAA==.Shaunwick:BAAANQADCgMIAwABNQAECgcIBgAHAAAAAA==.Shego:BAAANQAECgUICAABNQAECgcIFgACACkkAA==.Sheltered:BAABNQAECn8jAAIUAAoKRSO9DwD5AgAUAAoKRSO9DwD5AgAAAA==.Shocktopus:BAACNQAFFH8MAAIaAAQKtBpQDwBbAQAaAAQKtBpQDwBbAQA1AAQKfyYAAhoACgohHZ4eAPECABoACgohHZ4eAPECAAAA.',
Si='Silver:BAAANQAECgEIAQAAAA==.Sinakra:BAABNQAECn8cAAIUAAgKrwouvQCiAQAUAAgKrwouvQCiAQAAAA==.',
Sl='Slapdh:BAAANQADCggIDAABNQAFFAgIFAABAO8gAA==.Slaphapypapy:BAACNQAFFH8UAAMBAAgK7yB1AQBSAgABAAcKhSB1AQBSAgACAAIKYSTkEgC3AAA1AAQKfzcAAwEACgppJg8BAMYDAAEACgppJg8BAMYDAAIABAp/JJxdAEABAAAA.',
Sm='Smee:BAABNQAECn8hAAIBAAcKQhL8HwDOAQABAAcKQhL8HwDOAQAAAA==.',
Sn='Snowyscat:BAABNQAECn8YAAIgAAoKYCBzQwC/AgAgAAoKYCBzQwC/AgABNQAFFAgIGgAQAAAfAA==.',
Sp='Spirits:BAABNQAECn8dAAIaAAoKMR/6KQC7AgAaAAoKMR/6KQC7AgAAAA==.Spritz:BAAANQAECgQIEQAAAA==.',
St='Stampede:BAAANQADCggIEgAAAA==.Starshots:BAAANQADCgMIAwAAAA==.Stuey:BAAANQADCgYIGAAAAA==.',
Su='Subito:BAAANQADCgEIAQAAAA==.',
Ta='Taburiel:BAAANQADCgcICgAAAA==.Tanis:BAAANQAECgMICQAAAA==.Tarstarkas:BAAANQABCgQIBAAAAA==.Taylea:BAAANQADCgYIBgAAAA==.',
Te='Temperånce:BAABNQAECn8vAAMJAAoKGw+rLwCdAQAJAAkKiAyrLwCdAQADAAkKAAa7awAcAQAAAA==.',
Ti='Tiled:BAAANQABCggJCgAAAA==.',
To='Toosalty:BAAANQADCgQIBAAAAA==.Toothgrinder:BAABNQAECn8fAAMhAAoK0Q2oEAB9AQAhAAoK0Q2oEAB9AQAaAAIKqAeUHwEwAAAAAA==.',
Ur='Urbanfries:BAAANQADCgQIBAABNQAFFAcIEgALAP4UAA==.',
Va='Varlonn:BAAANQADCggIEAAAAA==.Varr:BAAANQAECgQIBwAAAA==.Vayeda:BAABNQAECn8dAAIcAAgKLCJhAwATAwAcAAgKLCJhAwATAwAAAA==.',
Ve='Velini:BAAANQADCggICgAAAA==.Venderic:BAAANQADCggICAAAAA==.',
Vi='Vixia:BAAANQAECgQICAAAAA==.Viz:BAAANQAECgQICwAAAA==.',
Vo='Voidpetal:BAAANQAECgQIBQAAAA==.Vozzert:BAAANQAECgIIAgAAAA==.',
Wh='Whatnow:BAAANQAECggICAAAAA==.Whítemane:BAAANQADCgYIBgAAAA==.',
Xa='Xantara:BAAANQABCgYIBgAAAA==.',
Yo='Yogi:BAAANQADCggICAABNQAECgQICAAHAAAAAA==.Yoursalad:BAACNQAFFH8FAAIUAAUKYAGBGACGAAAUAAUKYAGBGACGAAA1AAQKfx4AAx4ACApcD/svAJgAABQABQroCQjkAKYAAB4ABQpEEfsvAJgAAAAA.',
Yu='Yuuka:BAABNQAECn8hAAINAAkK/yCXFAAqAwANAAkK/yCXFAAqAwAAAA==.',
Za='Zarigar:BAAANQADCgEIAQAAAA==.',
Ze='Zerin:BAAANQAECgUICwABNQAECgoKIwAUAEUjAA==.Zeroh:BAAANQADCgYIEAAAAA==.',
Zi='Zithia:BAAANQADCgYIGAAAAA==.',
Zn='Zna:BAAANQAECgQIBAAAAA==.',
Zu='Zuezes:BAAANQADCgYIEwAAAA==.',
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
