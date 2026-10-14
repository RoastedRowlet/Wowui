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

local lookup = {'Rogue-Assassination','Druid-Balance','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Unknown-Unknown','Druid-Restoration','Druid-Feral','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Monk-Mistweaver','Paladin-Retribution','Evoker-Augmentation','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Fury','Evoker-Preservation','Mage-Arcane','Shaman-Restoration','Monk-Windwalker','Rogue-Subtlety','Paladin-Protection',}
local provider = {region='US',realm='Winterhoof',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aardin:BAABNQAECn8hAAIBAAkKNQ3zMQARAgABAAkKNQ3zMQARAgAAAA==.',
Ad='Adyrill:BAAANQADCgYICwAAAA==.',
Ai='Ailani:BAAANQADCgIIAgAAAA==.Airnantas:BAAANQADCgEIAQABNQAECgcIHgACAGwVAA==.',
Al='Allure:BAABNQAECn8XAAMDAAYKbxrSPwC5AQADAAYKwxbSPwC5AQAEAAMK4RxHIQC2AAAAAA==.',
Am='Amadin:BAABNQAECn82AAIFAAkKgR+cFgAhAwAFAAkKgR+cFgAhAwAAAA==.Amoralibash:BAAANQADCgYICwABNQAECgcIHgACAGwVAA==.',
An='Anguskhan:BAAANQADCggIFQAAAA==.Anhafal:BAAANQADCgYIDwAAAA==.',
Ao='Aoife:BAABNQAECn8hAAIFAAgKpxrAPABvAgAFAAgKpxrAPABvAgAAAA==.Aosin:BAAANQAECgMIAwABNQAECgQICQAGAAAAAA==.',
Ap='Apocalipze:BAAANQADCgUICwAAAA==.',
Ar='Aragosa:BAAANQABCgQIBQAAAA==.Archdruid:BAAANQAECggICAAAAA==.Arileous:BAAANQAECgEIAQAAAA==.Aroes:BAAANQADCgUIBgAAAA==.Artemiza:BAAANQABCgcJDgAAAA==.',
As='Ashariel:BAAANQADCgYICwAAAA==.Asylum:BAAANQAECgQIBgAAAA==.',
Ay='Ayeamanoob:BAAANQABCgIIAgABNQABCgYICgAGAAAAAA==.',
Ba='Bambiná:BAAANQADCgQIBQAAAA==.Bar:BAAANQAECgMIBAAAAA==.Batshaun:BAAANQADCgYIBgAAAA==.',
Be='Benadryl:BAAANQAECgUIEAAAAA==.',
Bh='Bhalen:BAAANQADCggIDQAAAA==.',
Bl='Bloodpear:BAAANQAECgMIAwABNQAFFAEIAQAGAAAAAA==.',
Br='Brakey:BAAANQAECgYIDQAAAA==.Briar:BAABNQAECn8dAAQHAAgKuwcGOwBDAQAHAAgKuwcGOwBDAQACAAYKBQcucQABAQAIAAUKYAngJQDbAAAAAA==.Britnysteers:BAAANQADCgEIAQAAAA==.Brungar:BAAANQAECggIDQAAAA==.',
Bu='Bubblybear:BAAANQAECgQIBgAAAA==.Bucksdk:BAAANQAECgcIEAAAAA==.Buckshotheal:BAAANQADCgMIAwABNQAECgcIEAAGAAAAAA==.Butterworm:BAAANQAECgEIAQAAAA==.',
Ca='Castiél:BAAANQADCgYIDAAAAA==.Caín:BAAANQADCgcICgAAAA==.',
Ch='Chuckroast:BAAANQAECgUIDgAAAA==.',
Cy='Cynastus:BAAANQAECgYIDAAAAA==.Cyrandalord:BAABNQAECn8kAAQJAAkK8BvqMwCVAgAJAAkKzhvqMwCVAgAKAAIKxxjMGwCGAAALAAEKAACliwAdAAAAAA==.Cyrandalorr:BAAANQAECgYICwABNQAECgkJJAAJAPAbAA==.',
Da='Danteghost:BAAANQADCgYIBgAAAA==.',
De='Deathzdemize:BAACNQAFFH8XAAMMAAcKqh+QAgAVAgAMAAYKqh+QAgAVAgANAAEKAABoKQBOAAA1AAQKf14ABAwACQoGJzMAAA0EAAwACQoGJzMAAA0EAA4AAgrfJsCOAOgAAA0AAQooHi65AFIAAAAA.Demonbane:BAABNQAECn8aAAMPAAgKgg2vLwDAAQAPAAgKgg2vLwDAAQADAAEKlAMJnQAgAAAAAA==.Demíse:BAAANQADCgEIAQAAAA==.',
Di='Dinduscuffin:BAAANQADCgcIBwABNQAFFAcIFwAMAKofAA==.Dirtpear:BAAANQAFFAEIAQAAAA==.',
Do='Doci:BAAANQADCggJFQABNQAECgcIDwAGAAAAAA==.',
Dr='Dragundeznut:BAAANQAECgMIAwABNQAFFAcIFwAMAKofAA==.Drakythor:BAAANQAECgEIAQABNQAECgkJJQAQAJMbAA==.Dreadnought:BAAANQADCgUIBQAAAA==.Druisy:BAAANQAECgQIBQAAAA==.',
Dy='Dyrillin:BAABNQAECn8dAAIRAAgKyBTVhgAVAgARAAgKyBTVhgAVAgAAAA==.',
El='Eleonna:BAAANQADCgEIAQAAAA==.',
Em='Emiragosa:BAAANQAECgEIAwAAAA==.',
Er='Erazar:BAAANQADCgUIBQABNQAECgkJJAAJAPAbAA==.',
Ev='Evoker:BAACNQAFFH8HAAISAAQKLwm8BgD7AAASAAQKLwm8BgD7AAA1AAQKfyUAAhIACQoVHBwFAJwCABIACQoVHBwFAJwCAAAA.',
Ex='Exorcizim:BAAANQADCgIIAgAAAA==.',
Fa='Facethegon:BAABNQAECn85AAMTAAkKZh3IEwDAAgATAAkKPBjIEwDAAgAUAAgKdiCSPACyAgAAAA==.Facethezoom:BAAANQAECgQIBAABNQAECgkJOQATAGYdAA==.Father:BAAANQAECgQIBgAAAA==.',
Fe='Feld:BAAANQADCgYIDQAAAA==.Felreaper:BAAANQADCgMIAwAAAA==.Feziwig:BAAANQADCgYICwAAAA==.',
Fi='Fizbar:BAAANQADCgQIBAABNQAECgUIEAAGAAAAAA==.Fiztweaver:BAAANQADCggIDgABNQAECgUIEAAGAAAAAA==.Fizzywater:BAAANQAECgUIEAAAAA==.',
Fo='Forloyn:BAAANQAECgIIAgAAAA==.',
Fr='Frozarath:BAAANQADCggICAAAAA==.Frozntempest:BAAANQADCgYIDgAAAA==.',
Ga='Galairn:BAAANQAECgQICAAAAA==.Garlatha:BAABNQAECn8fAAIVAAgKixKPCwAHAgAVAAgKixKPCwAHAgAAAA==.',
Ge='Gellicaan:BAAANQADCgYIEAAAAA==.Geves:BAAANQAECgMIBAAAAA==.',
Go='Gortry:BAAANQAECgQIBAAAAA==.',
Gr='Gromdred:BAAANQADCgEIAQAAAA==.Gryfter:BAAANQADCggIDAAAAA==.',
Ha='Harrinarr:BAAANQAFFAEIAQAAAA==.',
He='Hedgehog:BAAANQADCgYIBQAAAA==.Helbrecht:BAAANQADCgUJBQAAAA==.Hellgar:BAAANQAECgQIDQAAAA==.Hellraid:BAABNQAECn8eAAICAAcKbBUmQwDlAQACAAcKbBUmQwDlAQAAAA==.',
Ho='Holysquid:BAAANQADCggIDAAAAA==.Hordebreaker:BAAANQADCggICAAAAA==.',
Hu='Humblépié:BAAANQADCgMIAwAAAA==.',
Hy='Hydrosavior:BAAANQAECgYIEAAAAA==.',
Il='Illbegood:BAAANQADCgQIBAAAAA==.',
Im='Impearing:BAAANQADCgcIBwABNQAFFAEIAQAGAAAAAA==.',
In='Indaback:BAAANQADCgEIAQAAAA==.Initalog:BAAANQADCgUIBQAAAA==.',
It='Ithlaris:BAAANQADCgUIBQAAAA==.',
Iz='Izakura:BAAANQAECgUIBQAAAA==.Izumi:BAABNQAECn8jAAIWAAkK/xfMEQCNAgAWAAkK/xfMEQCNAgAAAA==.',
Ja='Jasperr:BAABNQAECn8lAAINAAgKMxnuKwBmAgANAAgKMxnuKwBmAgAAAA==.',
Je='Jenai:BAAANQADCgMIBQAAAA==.',
Ji='Jigsaw:BAAANQADCgYIBgAAAA==.Jinmoso:BAAANQADCgcICwAAAA==.Jinsha:BAAANQAECgYIEwAAAA==.Jiéqu:BAAANQAECgYIEAAAAA==.',
Jo='Jojodimojo:BAAANQADCgYIDQAAAA==.Joker:BAAANQADCgYICgAAAA==.Jomama:BAAANQAECgYICwAAAA==.',
['Jö']='Jörmungandr:BAAANQADCgYIEgAAAA==.',
Ka='Kaitnahar:BAAANQADCggICQABNQAECgcIHgACAGwVAA==.Kalunom:BAAANQABCggIBQAAAA==.Karasendreth:BAAANQADCgEIAQAAAA==.Katiperry:BAAANQAECgUIDgAAAA==.',
Kk='Kk:BAAANQAECgUIDgAAAA==.',
Ky='Kylowren:BAAANQADCgcIBgAAAA==.',
La='Laloyd:BAAANQABCgIIAgAAAA==.Lawbreaker:BAAANQAECgMIBQAAAA==.',
Le='Leafygaga:BAAANQADCgIIAgAAAA==.Leora:BAAANQADCggIDAAAAA==.',
Li='Liana:BAAANQADCgMIAwAAAA==.',
Lo='Lobotamy:BAAANQADCgYIDgAAAA==.Lockycharms:BAAANQADCgUIEAAAAA==.Loremis:BAAANQADCgYIEgAAAA==.',
Lu='Lunary:BAAANQADCgUIBQABNQAECgkJJAAJAPAbAA==.Lunatari:BAAANQADCggIFAAAAA==.',
Ma='Maal:BAAANQAECgEIAQAAAA==.Magetank:BAABNQAECn8dAAIXAAcK7wjoBwF8AQAXAAcK7wjoBwF8AQAAAA==.Marche:BAABNQAECn8uAAILAAkKRiM1BQCEAwALAAkKRiM1BQCEAwAAAA==.Mathendistus:BAAANQAECgEIAQABNQAECgcIHgACAGwVAA==.',
Me='Meliôdas:BAAANQAECgQIBwAAAA==.Mendelson:BAAANQABCgIIAgABNQABCgYICgAGAAAAAA==.Mew:BAAANQAECgYICwAAAA==.',
Mo='Mommy:BAAANQAECgUICwAAAA==.Moonspinner:BAAANQADCgIIAgAAAA==.Mooädib:BAAANQADCggIKAAAAA==.',
Mu='Musketeer:BAAANQADCgMIAwAAAA==.',
My='Mygore:BAAANQADCgEIAQAAAA==.Myrcy:BAAANQADCggIFQAAAA==.Mysteia:BAABNQAECn8lAAIQAAkKkxvIDAC0AgAQAAkKkxvIDAC0AgAAAA==.',
['Mø']='Mørdréd:BAAANQAECgEIAQAAAA==.',
Na='Naughtyhuman:BAAANQABCggIEwAAAA==.',
Ne='Necrobijuan:BAAANQADCgcICQAAAA==.Neodragoon:BAAANQAECggICQAAAA==.Neodragoonz:BAAANQADCggIDQABNQAECggICQAGAAAAAA==.',
Ni='Nihilist:BAABNQAECn8jAAINAAgK/xi7LQBcAgANAAgK/xi7LQBcAgAAAA==.Nihlliance:BAAANQAECgUIDgAAAA==.Nitequilz:BAABNQAECn8lAAIYAAgKARWOWQAAAgAYAAgKARWOWQAAAgAAAA==.',
No='Noblessyou:BAAANQABCgUJCAABNQABCgYICgAGAAAAAA==.',
Ob='Obeejoowan:BAAANQADCggIFwAAAA==.Obeewand:BAAANQADCggIGAAAAA==.Obijuan:BAAANQADCggIQQAAAA==.',
Ou='Ouch:BAAANQAECgQICQAAAA==.',
Pa='Pandapunch:BAABNQAECn8eAAIZAAgKdxHoJwDdAQAZAAgKdxHoJwDdAQAAAA==.',
Pl='Plateguy:BAAANQAECgUICQAAAA==.',
Po='Poxx:BAABNQAECn8ZAAIXAAgKcx9OWgDLAgAXAAgKcx9OWgDLAgABNQAFFAcIEgAaAAMhAA==.',
Qu='Quigonjin:BAAANQAECgQIEQAAAA==.Quinci:BAAANQABCggIEwAAAA==.',
Ra='Raelynixii:BAAANQADCgcIEwAAAA==.Raksi:BAAANQADCgIIAgAAAA==.Ranker:BAAANQADCgUICgAAAA==.Rastion:BAAANQADCgYIEQAAAA==.',
Re='Redacted:BAAANQADCgYIEgAAAA==.Rend:BAAANQADCgQIBAAAAA==.',
Ri='Rills:BAAANQADCgQIBAAAAA==.',
Ro='Rokku:BAAANQADCgYJBgAAAA==.Rollepolle:BAAANQAECgIIAgABNQAFFAcIFwAMAKofAA==.Rossini:BAAANQADCgEIAQAAAA==.Roxoglam:BAAANQADCgYIBgAAAA==.',
Ru='Rueittrebeck:BAAANQABCgYICgABNQABCgYICgAGAAAAAA==.Rushs:BAAANQABCgYICgAAAA==.',
Ry='Ryleigh:BAAANQADCgQIBAAAAA==.Rynron:BAAANQADCgUICAAAAA==.',
Sa='Samraj:BAAANQAECgQIBQAAAA==.',
Se='Seithr:BAAANQADCgEIAQAAAA==.Selexa:BAAANQADCgIIAgAAAA==.Sempiternal:BAACNQAFFH8IAAIFAAMKMAuKGADaAAAFAAMKMAuKGADaAAA1AAQKfzMAAgUACQrOFXY/AGQCAAUACQrOFXY/AGQCAAAA.Sentry:BAAANQADCgQIBAAAAA==.',
Sh='Shadowreaper:BAAANQABCgQIBAAAAA==.Shambali:BAAANQAECgUICAABNQAECgYICwAGAAAAAA==.Shaunanigans:BAAANQAECgUIBQAAAA==.Shaunwick:BAAANQADCgMIAwABNQAECgUIBQAGAAAAAA==.Shego:BAAANQAECgUICAAAAA==.Sheltered:BAAANQAECggIEgAAAA==.Shocktopus:BAACNQAFFH8KAAIYAAQKsxnlDgBbAQAYAAQKsxnlDgBbAQA1AAQKfyEAAhgACQoPGykeAPECABgACQoPGykeAPECAAAA.',
Si='Silver:BAAANQAECgEIAQAAAA==.Sinakra:BAABNQAECn8aAAIRAAgKewpWugCiAQARAAgKewpWugCiAQAAAA==.',
Sl='Slapdaddy:BAAANQADCggIDgAAAA==.Slapdh:BAAANQADCggIDAABNQAFFAcIEgAaAAMhAA==.Slaphapypapy:BAACNQAFFH8SAAMaAAcKAyFkAQBSAgAaAAYKhCBkAQBSAgABAAIKYSRsEgC3AAA1AAQKfywAAxoACQplJgwBAMcDABoACQplJgwBAMcDAAEAAwqNJAlcAEABAAAA.',
Sm='Smee:BAABNQAECn8hAAIaAAcKQhKrHwDOAQAaAAcKQhKrHwDOAQAAAA==.',
Sn='Snowyscat:BAAANQAECggIEQABNQAFFAcIFwAMAKofAA==.',
Sp='Spirits:BAAANQAECgcIEgABNQAECgkJIwAWAP8XAA==.Spritz:BAAANQAECgQIDgAAAA==.',
St='Stampede:BAAANQADCggIEgAAAA==.Starshots:BAAANQADCgMIAwAAAA==.Stuey:BAAANQADCgYIEgAAAA==.',
Su='Subito:BAAANQADCgEIAQAAAA==.',
Ta='Taburiel:BAAANQADCgcICgAAAA==.Tanis:BAAANQAECgMIBgAAAA==.Tarstarkas:BAAANQABCgIIAgAAAA==.Taylea:BAAANQADCgYIBgAAAA==.',
Te='Temperånce:BAABNQAECn8nAAMHAAkKfg9ALwCdAQAHAAgKpQxALwCdAQACAAcKIAa0agAcAQAAAA==.',
Th='Thekingelvis:BAAANQABCgYICAABNQABCgYICgAGAAAAAA==.',
Ti='Tiled:BAAANQABCggJCgAAAA==.',
To='Toosalty:BAAANQADCgQIBAAAAA==.Toothgrinder:BAAANQAECgYIDgAAAA==.',
Ug='Uglycow:BAAANQADCgcICAAAAA==.',
Ur='Urbanfries:BAAANQADCgQIBAABNQAFFAYIEQANABEWAA==.',
Va='Varlonn:BAAANQADCgYIBwAAAA==.Varr:BAAANQAECgEIAQAAAA==.Vayeda:BAAANQAECgcIEgAAAA==.',
Ve='Velini:BAAANQADCggICAAAAA==.Venderic:BAAANQADCgYIBgAAAA==.',
Vi='Vixia:BAAANQAECgMIBAAAAA==.Viz:BAAANQAECgQICwAAAA==.',
Vo='Voidpetal:BAAANQAECgQIBAAAAA==.Vozzert:BAAANQAECgIIAgAAAA==.',
Wh='Whítemane:BAAANQADCgYIBgAAAA==.',
Xa='Xantara:BAAANQABCgYIBgAAAA==.',
Yo='Yoursalad:BAABNQAECn8VAAMbAAcKpg7URgDPAAAbAAQKvxLURgDPAAARAAMKgQj5XAGDAAAAAA==.',
Yu='Yuuka:BAABNQAECn8YAAIJAAkKNBtBFAAqAwAJAAkKNBtBFAAqAwAAAA==.',
Za='Zarigar:BAAANQADCgEIAQAAAA==.',
Ze='Zerin:BAAANQAECgUICwABNQAECggIEgAGAAAAAA==.Zeroh:BAAANQADCgUIDQAAAA==.',
Zi='Zithia:BAAANQADCgYIEgAAAA==.',
Zn='Zna:BAAANQABCggIDgAAAA==.',
Zu='Zuezes:BAAANQADCgYIDQAAAA==.',
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
