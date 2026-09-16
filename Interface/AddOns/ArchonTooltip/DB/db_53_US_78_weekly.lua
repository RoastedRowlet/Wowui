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

local lookup = {'Priest-Holy','DemonHunter-Havoc','DeathKnight-Unholy','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Paladin-Protection','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','DemonHunter-Devourer','Druid-Guardian','Druid-Balance','Druid-Restoration','Warrior-Protection','Warrior-Arms','Warrior-Fury','Paladin-Holy','Mage-Frost',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECoEfAAIBAAcJnA+6QQCCAQABAAcJnA+6QQCCAQAAAA==.',
Ak='Akirik:BAAANQADCgMIAwAAAA==.',
Al='Alf:BAAANQADCgYIDAAAAA==.Allayt:BAAANQAECgQIBAAAAA==.',
Am='Ametrigos:BAAANQAECgQIBgAAAA==.',
Ar='Artzlayer:BAAANQAECgcIEgAAAA==.Aríes:BAABNQAECoEjAAICAAcJRRFKHgDRAQACAAcJRRFKHgDRAQAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAAANQAECgUIBQAAAA==.',
Aw='Awry:BAEBNQAECoEfAAIDAAgJ1hlZGQB3AgADAAgJ1hlZGQB3AgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECgUIEQAEAAAAAA==.Aww:BAAANQADCgEIAQAAAA==.',
Az='Azmo:BAABNQAECoEgAAQFAAkJ1CCLAgAKAwAFAAgJ7CCLAgAKAwAGAAYJ0BwpNgD6AQAHAAIJByHoDwCNAAAAAA==.',
Ba='Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCgcICwAAAA==.Berserkk:BAAANQADCgcIDQAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcICAAEAAAAAA==.',
Bi='Bicksmage:BAAANQAECgcIEAAAAA==.Bigdaddyclap:BAAANQAECgMIAgABNQAFFAYIDAAGAHYYAA==.Bigdaddylock:BAACNQAFFIEMAAQGAAYJdhj8AgBqAQAGAAQJGxb8AgBqAQAFAAIJaBu9AgDIAAAHAAEJthQDBABSAAA1AAQKgRkABAYACQnxIugQANgCAAYACAmuIugQANgCAAUABglHGIkTALEBAAcAAQngJoARAHUAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAECgkJHwAIAAAjAA==.',
Bo='Bobafatt:BAAANQADCgcIFAAAAA==.Bombdiggity:BAAANQAECgIIAgAAAA==.Bonnierotted:BAAANQADCgcIBwABNQAECgkJFAAJACQgAA==.',
Br='Bräinfreeze:BAAANQAECggIBwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.Chud:BAAANQAECgUIBQABNQAECgUIBgAEAAAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAAANQAECgYICgAAAA==.Cloneofhunt:BAABNQAECoEXAAMKAAkJ4SVSAQDXAwAKAAkJ4SVSAQDXAwALAAEJYRzvQwBUAAAAAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQADCgMIAwAAAA==.Comillazz:BAAANQAECgcIEAAAAA==.',
Cr='Crusher:BAAANQADCggICAABNQAFFAQIBgAMANoEAA==.',
Cu='Cultiran:BAAANQAECgUIBgAAAA==.Curby:BAABNQAECoEjAAINAAcJVAxkGABSAQANAAcJVAxkGABSAQAAAA==.Cursedfennec:BAAANQADCgIIAgAAAA==.',
Da='Damge:BAAANQAECgQIBAAAAA==.Damnnyou:BAAANQAECgcICwAAAA==.Danky:BAAANQAECgMIBAAAAA==.',
De='Deadicated:BAABNQAECoEdAAIBAAYJwQaYWAATAQABAAYJwQaYWAATAQAAAA==.Deathshunter:BAAANQAECgQIBwABNQAECgkJHAADANckAA==.Debsi:BAAANQADCgcICAAAAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAAANQAECgYICAAAAA==.Deepest:BAAANQAECgcIBwAAAA==.Deloraine:BAACNQAFFIEOAAMOAAUJySO3AwAxAQAOAAMJFiK3AwAxAQABAAIJNw2+DQCkAAA1AAQKgTUAAw4ACQnNIIQDAIADAA4ACQnNIIQDAIADAAEAAQkxBWmHAD8AAAAA.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAGAKcLAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Destrohacka:BAAANQAECgUICQAAAA==.',
Di='Disckin:BAAANQADCgEIAQAAAA==.',
Dr='Dracaena:BAAANQAECgQIBAABNQAECgcICwAEAAAAAA==.Dracodeath:BAABNQAECoEcAAIPAAkJLR5PBgASAwAPAAkJLR5PBgASAwAAAA==.Dracular:BAAANQAECgcIEQAAAA==.Draining:BAAANQAECgcIEgAAAA==.Drakos:BAAANQAECgEIAQAAAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAAANQAECgQIBwABNQAECgYICwAEAAAAAA==.Ejzox:BAAANQAECgYICwAAAA==.',
El='Elibaba:BAAANQAECgcIBwAAAA==.',
Em='Emopapa:BAABNQAECoEfAAIQAAkJKx/7BwA6AwAQAAkJKx/7BwA6AwAAAA==.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAAANQAECgIIAgAAAA==.Err:BAAANQAECgcIDQAAAA==.',
Ez='Ezelia:BAAANQAECgcIDwABNQAFFAUICAABAMQRAA==.',
Fa='Faelune:BAAANQADCggICgAAAA==.',
Fu='Fullmoonride:BAAANQADCgQIBQAAAA==.Funkymajik:BAAANQADCggIFAAAAA==.Furiosa:BAAANQABCgYIBgAAAA==.Furyfork:BAAANQAECgcICwAAAA==.',
Ga='Ganin:BAAANQAECgUICQAAAA==.Garugala:BAAANQAECgcIEAAAAA==.',
Ge='Gengár:BAAANQADCggIDgABNQAECgEIAgAEAAAAAA==.',
Gh='Ghalorin:BAAANQAECgEIAQAAAA==.',
Gi='Gigachad:BAAANQAECggIDAAAAA==.Gingarthas:BAAANQAECgUICQAAAA==.',
Gr='Grapespliter:BAAANQAECgYICgAAAA==.Grimefiend:BAAANQAECgMIBAABNQAECggIEAAEAAAAAA==.Grimetime:BAAANQAECggIEAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Handwarm:BAAANQAECgMICAAAAA==.Hanokano:BAAANQADCgYIBgABNQAECgkJHQAGANoYAA==.',
He='Heartdh:BAAANQAECgUIDAAAAA==.Hellkai:BAABNQAECoEYAAIHAAYJ4SJNAgBmAgAHAAYJ4SJNAgBmAgAAAA==.Herrion:BAABNQAECoEgAAMGAAkJYyScDgDsAgAGAAcJjSScDgDsAgAFAAUJ6hYfFwCPAQAAAA==.',
Hi='Hippy:BAAANQAFFAIIAgAAAA==.',
Ho='Hog:BAAANQAECgQIBAABNQAFFAIIAgAEAAAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hukani:BAAANQAECgMIAwAAAA==.Huskar:BAAANQAECgQIBgAAAA==.',
Hw='Hwanjeabb:BAAANQAECgcIEAAAAA==.',
Ig='Ignis:BAAANQAECgcICwAAAA==.',
Il='Illiroman:BAAANQAECgYIDwAAAA==.',
Im='Imntprepared:BAAANQAECgEIAQAAAA==.',
In='Infectîon:BAAANQAECgcIEQAAAA==.',
Ji='Jimjum:BAABNQAECoEgAAIBAAkJ1RRYGgBzAgABAAkJ1RRYGgBzAgAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIDgAEAAAAAA==.',
Ka='Kaaru:BAAANQAECgYIDAAAAA==.Kagarl:BAAANQAECgIIAgABNQAECgkJIAAGAGMkAA==.Kaiforst:BAAANQADCggICAABNQAECgcIEAAEAAAAAA==.Kairon:BAAANQAECgcIEAAAAA==.',
Ki='Kickstarter:BAAANQAECgUIEQAAAA==.Kiosk:BAABNQAECoEcAAIRAAcJcxdyagAHAgARAAcJcxdyagAHAgAAAA==.Kiwichaos:BAABNQAECoEcAAISAAkJpRWRDwChAgASAAkJpRWRDwChAgAAAA==.',
Kr='Krellis:BAAANQAECgYIEQAAAA==.',
Kv='Kvôthe:BAAANQADCggIFAAAAA==.',
Ky='Kynralol:BAAANQAECgQICAAAAA==.',
La='Lagalot:BAAANQADCgMIAgAAAA==.Latrisha:BAAANQABCgcICQAAAA==.',
Le='Legham:BAAANQADCgYIBAAAAA==.Legolazz:BAAANQAECgcIDQAAAA==.Lenatheplug:BAABNQAECoEUAAIJAAkJJCD3BAAdAwAJAAkJJCD3BAAdAwAAAA==.',
Ll='Llewser:BAAANQAECgQICAAAAA==.',
Lo='Loongzokluad:BAAANQAECgcIDwAAAA==.Louisvuitton:BAAANQAECgQIBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Maggot:BAAANQADCgUIDQAAAA==.Maÿcé:BAAANQAECggIDgAAAA==.',
Mi='Mirant:BAAANQADCggICAAAAA==.Miststep:BAAANQADCggIDwAAAA==.',
Mo='Moondeity:BAAANQAECgUIBAAAAA==.Morphio:BAAANQAECgYIDQAAAA==.Morêl:BAAANQADCgEIAQAAAA==.',
My='Mythira:BAAANQADCgMIAwABNQAECgcIIwAQAFoeAA==.',
Nb='Nb:BAAANQAECgcIEQAAAA==.',
Ne='Ness:BAAANQAECgcIEgAAAA==.Nevell:BAAANQAECgcIDAABNQAECgkJIAAGAGMkAA==.',
Ni='Nikola:BAABNQAECoEjAAQTAAkJtw14CQDHAQATAAkJIQ14CQDHAQAUAAgJkwhUMQCdAQAVAAMJjhIAKQDZAAAAAA==.Nimro:BAABNQAECoEfAAIWAAkJyR4iAgAwAwAWAAkJyR4iAgAwAwAAAA==.Niub:BAAANQADCggIDgAAAA==.',
No='Nongmicky:BAAANQAECgcIDwAAAA==.',
Nu='Nueng:BAAANQADCgcICAAAAA==.Nuferax:BAAANQADCggIFAAAAA==.Nuisadv:BAAANQAECgQIBwAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Ok='Okiji:BAAANQAECgUICAAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQADCgIIAgAAAA==.',
Pa='Palliative:BAAANQAECgMICAAAAA==.Pallidnim:BAAANQAECgcIBwAAAA==.Pallystine:BAAANQAECgYIDwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECoEeAAIRAAkJ6B6YIQAOAwARAAkJ6B6YIQAOAwAAAA==.Phatwarlock:BAAANQAECgUICAABNQAECgkJHgARAOgeAA==.',
Pi='Pix:BAABNQAECoEcAAIOAAkJGSVWAQDBAwAOAAkJGSVWAQDBAwAAAA==.',
Pl='Pleasuremax:BAAANQAECgUICQAAAA==.',
Po='Poofyfeesh:BAAANQAECgcIBwAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgUICwAEAAAAAA==.',
Py='Pyrusdk:BAAANQAECggIDwAAAA==.',
Qe='Qermack:BAAANQADCgcICQAAAA==.',
Ra='Raìn:BAAANQADCgUIBQAAAA==.',
Re='Rednutts:BAAANQAECgIIAgAAAA==.Rekt:BAAANQAECgcICAAAAA==.',
Ri='Riggs:BAACNQAFFIEKAAMXAAUJGCHYAgDzAQAXAAUJDiDYAgDzAQAYAAIJhR2iAACzAAA1AAQKgRwAAxcACQnXJTYDAMoDABcACQnJJTYDAMoDABgAAQn/JeIVAGwAAAAA.',
Rn='Rnc:BAAANQAECgcIDQAAAA==.',
Ro='Rodger:BAAANQAECgUICwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAGAKcLAA==.Roninn:BAAANQAECgYIDwAAAA==.Ronlock:BAABNQAECoEXAAIGAAkJpwtmTgCRAQAGAAkJpwtmTgCRAQAAAA==.',
Rw='Rwen:BAABNQAECoEeAAIKAAYJLAY/bgBRAQAKAAYJLAY/bgBRAQAAAA==.',
['Rô']='Rôlayne:BAAANQADCggIHgAAAA==.',
Sa='Sadakos:BAAANQAECgQICwAAAA==.Salvare:BAAANQAECgcIDgAAAA==.Sarielsia:BAAANQAECgEIAgAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgEIAgAEAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECgYIEwAEAAAAAA==.',
Sc='Sciodeekay:BAABNQAECoEiAAIQAAkJZRh7EgClAgAQAAkJZRh7EgClAgAAAA==.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAAANQAECgQICwAAAA==.',
Se='Sedge:BAAANQAECggIEQAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAAANQAECgcIEgAAAA==.Shambulance:BAAANQADCgcICAAAAA==.Shammalxs:BAABNQAECoEfAAIIAAkJ2ByhFADXAgAIAAkJ2ByhFADXAgAAAA==.Shamoc:BAAANQAECgMICAABNQAECgcIEQAEAAAAAA==.Sharpknife:BAAANQAECggIEAAAAA==.Shiesty:BAAANQADCgUIBQAAAA==.Shivd:BAAANQADCgUIBQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECggIEwAEAAAAAA==.',
Sl='Slowjoe:BAAANQAECgYIDAAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.',
Sn='Sneakyfella:BAAANQAECgcIBwAAAA==.',
So='Solidus:BAAANQADCggIBgAAAA==.',
Sp='Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgAAAA==.Stgeorge:BAAANQAECgYIDQAAAA==.Stickypriest:BAABNQAECoEjAAMOAAcJCx+8FAAXAgAOAAYJsh68FAAXAgABAAIJPhv+cwCYAAAAAA==.Strawhats:BAACNQAFFIEPAAIRAAYJiRxwAQBJAgARAAYJiRxwAQBJAgA1AAQKgRsAAhEACQlWJDIJAJUDABEACQlWJDIJAJUDAAAA.Streamliner:BAAANQAECgYICgAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAAANQAECgIIBQABNQAECgYIEAAEAAAAAA==.Tarlenm:BAAANQAECgcIEQAAAA==.',
Te='Terrafirm:BAAANQADCgQIBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgAEAAAAAA==.',
Th='Thon:BAAANQAECgYIDwAAAA==.Thunderbelly:BAAANQAECgYIDwAAAA==.',
To='Totems:BAACNQAFFIEGAAIMAAQJ2gT/BAAiAQAMAAQJ2gT/BAAiAQA1AAQKgSEAAwwACQm5HlwHAEEDAAwACQm5HlwHAEEDAAgAAQksCZCxADsAAAAA.',
Tr='Traktorbeam:BAAANQADCgUIBQAAAA==.Trass:BAABNQAECoEdAAQGAAkJ2hihKwAvAgAGAAcJzxehKwAvAgAFAAMJgxRjMADNAAAHAAEJyg0xGwA9AAAAAA==.Trisse:BAAANQADCggIDQAAAA==.',
Tu='Tuzz:BAAANQAECgcIDwAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgYIDgAEAAAAAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIDwAAAA==.Varg:BAAANQAECgcICgAAAA==.Varthloukker:BAAANQABCgIIAgAAAA==.',
Ve='Vermeil:BAAANQADCgUIEQAAAA==.Vermillion:BAABNQAECoEWAAINAAgJDRg7CgBIAgANAAgJDRg7CgBIAgAAAA==.Verzik:BAAANQADCgIIAgAAAA==.',
Vi='Vib:BAAANQAECgMIBQAAAA==.Vicia:BAAANQADCgYIBgAAAA==.Viczrei:BAAANQAECgcICgAAAA==.',
Vv='Vvenator:BAAANQAECgIIBAAAAA==.',
Vy='Vynessa:BAABNQAECoEUAAIZAAcJih5RGwCGAgAZAAcJih5RGwCGAgAAAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Waterwaterz:BAABNQAECoEgAAMRAAkJPBKqaAANAgARAAkJoBGqaAANAgAaAAMJ8A7IFACvAAAAAA==.Waylm:BAAANQADCggICAABNQAECgkJIAAGAGMkAA==.',
Wc='Wchin:BAAANQAECgcIEAAAAA==.',
We='Weareleigon:BAAANQADCgYIDAAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Wendyy:BAAANQAECgQICAABNQAECgkJGwAFAF4dAA==.',
Wh='Whaka:BAAANQAECgcICAAAAA==.',
Wo='Wound:BAAANQADCgEIAgAAAA==.',
Xi='Xiera:BAAANQADCggIDgAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Ze='Zenath:BAAANQAECgQIBQABNQAECgkJIAAGAGMkAA==.Zerithra:BAABNQAECoEjAAIQAAcJWh4BGgBUAgAQAAcJWh4BGgBUAgAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.',
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
