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

local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Shaman-Restoration','Paladin-Protection','Priest-Shadow','Priest-Holy','Mage-Arcane','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Mage-Frost',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAAANQAECgUIEAAAAA==.',
Al='Alf:BAAANQADCgYICgAAAA==.Allayt:BAAANQADCgYIDwAAAA==.',
Am='Ametrigos:BAAANQAECgIIAgAAAA==.',
Ar='Artzlayer:BAAANQAECgcICwAAAA==.Aríes:BAABNQAECoEWAAIBAAcJtQ+qFACxAQABAAcJtQ+qFACxAQAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAAANQAECgUIBQAAAA==.',
Aw='Awry:BAEANQAECgYIDgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECgMICAACAAAAAA==.Aww:BAAANQADCgEIAQAAAA==.',
Az='Azmo:BAABNQAECoEXAAQDAAkJLSAGAgAbAwADAAgJMCAGAgAbAwAEAAIJSR5NbACkAAAFAAIJByF1CwCUAAAAAA==.',
Ba='Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCgEIAQAAAA==.Berserkk:BAAANQADCgcIDQAAAA==.Bewbs:BAAANQAECgQICQAAAA==.',
Bi='Bicksmage:BAAANQAECgcICgAAAA==.Bigdaddylock:BAABNQAFFIEGAAMEAAQJgRH2AgAAAQAEAAMJmRH2AgAAAQADAAIJ8Q8dAwC2AAAAAA==.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.',
Bo='Bobafatt:BAAANQADCgcIEAAAAA==.Bombdiggity:BAAANQAECgIIAgAAAA==.Bonnierotted:BAAANQADCgcIBwABNQAECgkJFAAGACQgAA==.',
Br='Bräinfreeze:BAAANQADCggIEAAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAAANQAECgQIAgAAAA==.Cloneofhunt:BAAANQAECgcIDwAAAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQADCgMIAwAAAA==.Comillazz:BAAANQAECgUICQAAAA==.',
Cr='Crusher:BAAANQADCggICAABNQAECgkJGAAHAOQcAA==.',
Cu='Cultiran:BAAANQADCggICgAAAA==.Curby:BAABNQAECoEWAAIIAAcJDQqjEQBJAQAIAAcJDQqjEQBJAQAAAA==.Cursedfennec:BAAANQADCgIIAgAAAA==.',
Da='Damnnyou:BAAANQAECgUIBQAAAA==.Danky:BAAANQAECgEIAQAAAA==.',
De='Deadicated:BAAANQAECgUIEAAAAA==.Deathshunter:BAAANQAECgMIAwABNQAECgcIEAACAAAAAA==.Debsi:BAAANQADCgYIBgAAAA==.Declined:BAAANQAECgIIAgAAAA==.Deeper:BAAANQAECgIIAgAAAA==.Deepest:BAAANQADCgcIBwAAAA==.Deloraine:BAABNQAECoEpAAMJAAkJ/h6vAwBcAwAJAAkJ/h6vAwBcAwAKAAEJzQGgZgA6AAAAAA==.Demonicfaith:BAAANQABCgQIBgABNQAECggICgACAAAAAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Destrohacka:BAAANQAECgMIBAAAAA==.',
Di='Disckin:BAAANQADCgEIAQAAAA==.',
Dr='Dracaena:BAAANQAECgQIBAABNQAECgUIBQACAAAAAA==.Dracodeath:BAAANQAECggIEwAAAA==.Dracular:BAAANQAECgcICgAAAA==.Draining:BAAANQAECgcIDQAAAA==.Drakos:BAAANQAECgEIAQAAAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAAANQAECgMIAwABNQAECgQIBQACAAAAAA==.Ejzox:BAAANQAECgQIBQAAAA==.',
Em='Emopapa:BAAANQAECgcIEgAAAA==.',
En='Endlessdh:BAAANQADCgcIDQAAAA==.',
Er='Erihunter:BAAANQADCggIDQAAAA==.Err:BAAANQAECgUICAAAAA==.',
Ez='Ezelia:BAAANQAECgYIDgAAAA==.',
Fa='Faelune:BAAANQADCgYIBgAAAA==.',
Fu='Fullmoonride:BAAANQADCgEIAQAAAA==.Funkymajik:BAAANQADCgYIDAAAAA==.Furiosa:BAAANQABCgYIBgAAAA==.Furyfork:BAAANQAECgcICwAAAA==.',
Ga='Ganin:BAAANQAECgQIBAAAAA==.Garugala:BAAANQAECgUICQAAAA==.',
Ge='Gengár:BAAANQADCgYIBgABNQAECgIIAQACAAAAAA==.',
Gh='Ghalorin:BAAANQADCgYIHQAAAA==.',
Gi='Gigachad:BAAANQAECggICQAAAA==.Gingarthas:BAAANQAECgQIBAAAAA==.',
Gr='Grapespliter:BAAANQAECgQIBQAAAA==.Grimefiend:BAAANQAECgIIAgABNQAECgcICQACAAAAAA==.Grimetime:BAAANQAECgcICQAAAA==.',
Ha='Handwarm:BAAANQAECgIIAgAAAA==.Hanokano:BAAANQADCgYIBgABNQAECggIEAACAAAAAA==.',
He='Heartdh:BAAANQAECgQIBwAAAA==.Hellkai:BAAANQAECgYIDwAAAA==.Herrion:BAABNQAECoEXAAMEAAkJFyG8DwCIAgAEAAcJ1x68DwCIAgADAAUJ/BUWFgCIAQAAAA==.',
Hi='Hippy:BAAANQAECgcICwAAAA==.',
Ho='Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Huskar:BAAANQAECgIIAgAAAA==.',
Hw='Hwanjeabb:BAAANQAECgUICQAAAA==.',
Ig='Ignis:BAAANQAECgQIBAAAAA==.',
Il='Illiroman:BAAANQAECgYICQAAAA==.',
In='Infectîon:BAAANQAECgYIDAAAAA==.',
Ji='Jimjum:BAABNQAECoEXAAIKAAgJHwt3IwDSAQAKAAgJHwt3IwDSAQAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIDQACAAAAAA==.',
Ka='Kaaru:BAAANQAECgYIBgAAAA==.Kaiforst:BAAANQADCggICAABNQAECgUICQACAAAAAA==.Kairon:BAAANQAECgUICQAAAA==.',
Ki='Kickstarter:BAAANQAECgMICAAAAA==.Kiosk:BAABNQAECoEVAAILAAYJvhJwawCfAQALAAYJvhJwawCfAQAAAA==.Kiwichaos:BAAANQAECggIEAAAAA==.',
Kr='Krellis:BAAANQAECgYICwAAAA==.',
Kv='Kvôthe:BAAANQADCgYIDAAAAA==.',
Ky='Kynralol:BAAANQAECgMIBAAAAA==.',
La='Lagalot:BAAANQADCgMIAgAAAA==.Latrisha:BAAANQABCgUIBwAAAA==.',
Le='Legham:BAAANQADCgYIBAAAAA==.Legolazz:BAAANQAECgUIBgAAAA==.Lenatheplug:BAABNQAECoEUAAIGAAkJJCApAgA+AwAGAAkJJCApAgA+AwAAAA==.',
Ll='Llewser:BAAANQAECgMIBAAAAA==.',
Lo='Loongzokluad:BAAANQAECgYICAAAAA==.Louisvuitton:BAAANQAECgQIBAAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Maggot:BAAANQADCgUIDQAAAA==.Maÿcé:BAAANQAECgEIAQAAAA==.',
Mi='Miststep:BAAANQADCggICAAAAA==.',
Mo='Moondeity:BAAANQAECgUIBAAAAA==.Morphio:BAAANQAECgQIBQAAAA==.',
My='Mythira:BAAANQADCgMIAwABNQAECgcIFgAMAHscAA==.',
Nb='Nb:BAAANQAECgcIDQAAAA==.',
Ne='Ness:BAAANQAECggICwAAAA==.Nevell:BAAANQAECgUIBQABNQAECgkJFwAEABchAA==.',
Ni='Nikola:BAAANQAECggIEwAAAA==.Nimro:BAAANQAECggIEwAAAA==.Niub:BAAANQADCggICQAAAA==.',
No='Nongmicky:BAAANQAECgUICAAAAA==.',
Nu='Nueng:BAAANQADCgcICAAAAA==.Nuferax:BAAANQADCgYIDAAAAA==.Nuisadv:BAAANQAECgQIBwAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Ok='Okiji:BAAANQAECgUIBQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQABCgIIAgAAAA==.',
Pa='Palliative:BAAANQAECgIIAgAAAA==.Pallidnim:BAAANQADCggIDgAAAA==.Pallystine:BAAANQAECgYICQAAAA==.',
Pe='Pearson:BAAANQADCgQIBAAAAA==.',
Ph='Phatmage:BAAANQAECgcIEgAAAA==.Phatwarlock:BAAANQAECgIIAgABNQAECgcIEgACAAAAAA==.',
Pi='Pix:BAAANQAECggIEgAAAA==.',
Pl='Pleasuremax:BAAANQAECgUIBQAAAA==.',
Po='Poofyfeesh:BAAANQADCggICAAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIDgAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgQIBgACAAAAAA==.',
Py='Pyrusdk:BAAANQAECggICgAAAA==.',
Qe='Qermack:BAAANQADCgcICQAAAA==.',
Ra='Raìn:BAAANQADCgUIBQAAAA==.',
Re='Rednutts:BAAANQADCggIDAAAAA==.',
Ri='Riggs:BAABNQAECoEZAAMNAAkJQiSBAgDEAwANAAkJNCSBAgDEAwAOAAEJ/yU+EABwAAAAAA==.',
Rn='Rnc:BAAANQAECgQIBgAAAA==.',
Ro='Rodger:BAAANQAECgQIBgAAAA==.Roninn:BAAANQAECgYICQAAAA==.Ronlock:BAAANQAECggICgAAAA==.',
Rw='Rwen:BAAANQAECgUIEgAAAA==.',
['Rô']='Rôlayne:BAAANQADCggIFgAAAA==.',
Sa='Sadakos:BAAANQAECgUICwAAAA==.Salvare:BAAANQAECgYICgAAAA==.Sarielsia:BAAANQAECgIIAQAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgIIAQACAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECgQICAACAAAAAA==.',
Sc='Sciodeekay:BAAANQAECggIEQAAAA==.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAAANQAECgQIBwAAAA==.',
Se='Sedge:BAAANQAECgYIBgAAAA==.',
Sh='Shadowind:BAAANQAECgYICwAAAA==.Shambulance:BAAANQADCgcICAAAAA==.Shammalxs:BAABNQAECoEZAAIPAAkJIRxVDQDeAgAPAAkJIRxVDQDeAgAAAA==.Shamoc:BAAANQAECgIIBAABNQAECgUICgACAAAAAA==.Sharpknife:BAAANQAECggIDgAAAA==.Shiesty:BAAANQADCgUIBQAAAA==.Shivd:BAAANQADCgUIBQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgYICwACAAAAAA==.',
Sl='Slowjoe:BAAANQAECgYIBgAAAA==.',
Sn='Sneakyfella:BAAANQADCggICAAAAA==.',
So='Solidus:BAAANQADCggIBgAAAA==.',
Sp='Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAECgcIDwACAAAAAA==.Stgeorge:BAAANQAECgQIBgAAAA==.Stickypriest:BAABNQAECoEWAAMJAAcJ5B1iFQCvAQAJAAUJyhxiFQCvAQAKAAIJPhvfUgCkAAAAAA==.Strawhats:BAACNQAFFIEJAAILAAUJURQ9AgDMAQALAAUJURQ9AgDMAQA1AAQKgRgAAgsACQn9Iw8EAK0DAAsACQn9Iw8EAK0DAAAA.Streamliner:BAAANQAECgYIBgAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIBgAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAAANQAECgIIAwAAAA==.Tarlenm:BAAANQAECgUICgAAAA==.',
Te='Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgACAAAAAA==.',
Th='Thon:BAAANQAECgUICQAAAA==.Thunderbelly:BAAANQAECgUICQAAAA==.',
To='Totems:BAABNQAECoEYAAIHAAkJ5BxiBQA2AwAHAAkJ5BxiBQA2AwAAAA==.',
Tr='Traktorbeam:BAAANQADCgUIBQAAAA==.Trass:BAAANQAECggIEAAAAA==.Trisse:BAAANQADCgQIBQAAAA==.',
Tu='Tuzz:BAAANQAECgUIBwAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgUICAACAAAAAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIDwAAAA==.Varg:BAAANQAECgMIAwAAAA==.Varthloukker:BAAANQABCgIIAgAAAA==.',
Ve='Vermeil:BAAANQADCgQIDAAAAA==.Vermillion:BAAANQAECgcIDQAAAA==.Verzik:BAAANQADCgIIAgAAAA==.',
Vi='Vib:BAAANQAECgIIAwAAAA==.Viczrei:BAAANQAECgMIAwAAAA==.',
Vv='Vvenator:BAAANQAECgEIAgAAAA==.',
Vy='Vynessa:BAAANQAECgcIDgAAAA==.',
Wa='Wakkytabbaky:BAAANQADCgUIDQAAAA==.Waterwaterz:BAABNQAECoEWAAMLAAgJsxGwRAAlAgALAAgJsxGwRAAlAgAQAAEJDwyeHwAyAAAAAA==.Waylm:BAAANQADCggICAABNQAECgkJFwAEABchAA==.',
Wc='Wchin:BAAANQAECgUICQAAAA==.',
We='Weareleigon:BAAANQADCgYICwAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Wendyy:BAAANQAECgQIBgABNQAECgkJFgADAEIdAA==.',
Wh='Whaka:BAAANQAECgEIAQABNQAECgYICgACAAAAAA==.',
Wo='Wound:BAAANQADCgEIAgAAAA==.',
Xi='Xiera:BAAANQADCgYIBgAAAA==.',
Yo='Yozzao:BAAANQADCggICAAAAA==.',
Ze='Zerithra:BAABNQAECoEWAAIMAAcJexwGFQA4AgAMAAcJexwGFQA4AgAAAA==.',
Zz='Zzdruid:BAAANQADCgcIBwAAAA==.',
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
