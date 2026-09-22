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

local lookup = {'DeathKnight-Blood','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DeathKnight-Frost',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abeblinkin:BAAANQADCgEIAQAAAA==.Abraxîs:BAAANQAECgUIBQAAAA==.',
Ac='Acindis:BAABNQAECoEmAAIBAAgK7gr+QgB9AQABAAgK7gr+QgB9AQAAAA==.',
Ae='Aeless:BAAANQAECgIJAgAAAA==.Aelless:BAAANQADCgEIAQAAAA==.',
Ah='Ahzure:BAAANQAECgIIAgABNQAECgUIDgACAAAAAA==.',
Ai='Aithinne:BAAANQADCgUICQAAAA==.',
Al='Alch:BAAANQADCgQIBAAAAA==.Aleandi:BAAANQADCgUIBQAAAA==.Alynara:BAAANQAECgYJCwAAAA==.',
Am='Amalthea:BAAANQAECgUJBgAAAA==.Amoredis:BAAANQABCgcIDwAAAA==.',
An='Anume:BAAANQADCgUIBgAAAA==.Anwas:BAAANQABCgIJAgAAAA==.',
Ap='Apally:BAAANQADCgUIBQAAAA==.',
Ar='Aragan:BAAANQADCgQIBAAAAA==.Arellean:BAAANQADCgQIBAAAAA==.Arese:BAAANQAECgUIDgAAAA==.',
As='Asmodea:BAAANQADCgUJBQAAAA==.',
Az='Azzif:BAAANQAECgEIAQAAAA==.',
Ba='Babybluz:BAAANQADCggIHAAAAA==.Baifeng:BAAANQABCggJDgAAAA==.Bandayde:BAAANQADCgEJAQAAAA==.',
Be='Beauriley:BAAANQAECgYJDAAAAA==.Behomethan:BAAANQAECgYJCwAAAA==.Berian:BAAANQAECgIIAgAAAA==.',
Bi='Bigpapafreez:BAAANQADCggIDQABNQAECgcIEgACAAAAAA==.Billbetaray:BAAANQAECgEJAQAAAA==.',
Bl='Blux:BAAANQADCgEIAQAAAA==.Bløødsong:BAAANQADCgEIAQAAAA==.',
Bo='Bombchele:BAAANQAECgQICQAAAA==.Bowogibrann:BAAANQADCgQIBAAAAA==.',
Br='Bratticusrex:BAAANQAECgYIDAAAAA==.Brazier:BAAANQADCggICAAAAA==.Bresowar:BAAANQADCgIIAgAAAA==.',
Bu='Bunnylicious:BAAANQAECgUIDgAAAA==.Bunnymedic:BAAANQAECgIJAgABNQAECgUIDgACAAAAAA==.',
Ca='Caebrylla:BAAANQAECgMJBgAAAA==.Callipygea:BAAANQADCgIIAgAAAA==.Cang:BAAANQABCgYIDwAAAA==.Catalina:BAAANQAECgcJEwAAAA==.',
Ce='Cecimorte:BAAANQAECgMJBgAAAA==.',
Ch='Chargeasap:BAAANQADCgUIBQAAAA==.Chinashop:BAAANQAECgIIAgAAAA==.Chonker:BAAANQAECgYIEAAAAA==.Chuckforrest:BAAANQADCgIIAgABNQAECgYJBgACAAAAAA==.',
Ci='Cihato:BAAANQAECgYJDgAAAA==.',
Cl='Cleveistic:BAAANQADCgMIBAABNQADCggIDwACAAAAAA==.Cleveland:BAAANQADCggIDwAAAA==.',
Co='Coldshoulder:BAAANQAECgMJBAAAAA==.Corelas:BAAANQADCggJGAAAAA==.Couchdad:BAAANQADCgYJCQAAAA==.',
Cr='Crazymadman:BAAANQADCggJEAAAAA==.Crysallis:BAAANQADCggIFgAAAA==.',
Cy='Cynide:BAAANQADCgYJBgAAAA==.',
Da='Dall:BAAANQAECgIIAwAAAA==.Damo:BAAANQAECgYJCAAAAA==.Danale:BAAANQADCgYJCgAAAA==.Danknugz:BAAANQAECgIJAwAAAA==.Dawnson:BAAANQAECgEJAQAAAA==.',
De='Deathlich:BAAANQAECgEIAQAAAA==.Demogless:BAAANQAECgIJAgAAAA==.Desyrel:BAAANQADCggIDgABNQAECgIIBAACAAAAAA==.',
Dh='Dharknight:BAAANQAECgQIBQAAAA==.Dharkuul:BAAANQABCgYICAABNQAECgQIBQACAAAAAA==.',
Di='Didimissfire:BAEANQAECgYIDQAAAA==.Diefatty:BAAANQADCgMIAwAAAA==.Dilaudid:BAAANQAECggICAAAAA==.',
Dr='Draeven:BAAANQABCgIIAgAAAA==.Dranalis:BAAANQADCgYJCAAAAA==.Dredlok:BAAANQADCgYJEAAAAA==.',
Du='Dumonster:BAAANQADCgUIDwAAAA==.',
Ea='Eamishal:BAAANQADCgMIAwAAAA==.',
El='Elev:BAAANQADCgMIAwAAAA==.',
Er='Eris:BAAANQADCggJCAAAAA==.',
Es='Estrogen:BAAANQAECgYJEwAAAA==.',
Ev='Eventhorizon:BAAANQAECgYIAgAAAA==.Evolett:BAAANQADCgQJBAAAAA==.',
Fa='Fatbox:BAAANQAECgUIDgAAAA==.Fayth:BAAANQAECgYJDgAAAA==.',
Fe='Fearkin:BAAANQAECgQIBAAAAA==.Fenastic:BAAANQAECgUICgAAAA==.Feyrah:BAAANQAECgEJAQAAAA==.',
Fi='Fiobhe:BAAANQADCggJGAAAAA==.Fixeruper:BAAANQAECgMJAwAAAA==.',
Fo='Fonz:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.',
Ge='Geauxt:BAAANQAECgQIBgABNQAFFAIJBwADAMkVAA==.',
Gl='Glenlizzo:BAAANQADCgEJAQABNQADCggIDwACAAAAAA==.Glenroyce:BAAANQADCggIDwAAAA==.Gless:BAAANQAECgUIDgAAAA==.',
Gn='Gnoretreat:BAAANQAECgYIDwAAAA==.',
Ha='Haill:BAAANQABCgIJAgABNQADCgcIHQACAAAAAA==.Hamhock:BAAANQAECgIJAgABNQAECgUIDgACAAAAAA==.',
He='Hellìos:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Hy='Hyborian:BAAANQADCgcJFAABNQADCgIIAgACAAAAAA==.',
Ic='Icecuber:BAAANQADCgMIAwAAAA==.',
Ih='Ihatepallys:BAAANQADCgYJCQAAAA==.',
Ii='Iikeomgikr:BAAANQAECgQIBAAAAA==.',
Il='Ilya:BAAANQAECgYJBgAAAA==.',
In='Indigo:BAAANQAECgUIDgAAAA==.Ineffablyss:BAAANQABCgYICAABNQAECgQIBAACAAAAAA==.Innron:BAAANQAECgYIDQAAAA==.',
Io='Iol:BAAANQADCgIIAgAAAA==.',
Je='Jezzea:BAAANQADCgUIAwAAAA==.',
Ji='Jinjix:BAAANQADCgUIBQAAAA==.',
Jo='Jonly:BAAANQADCgQIBAAAAA==.Jonoa:BAAANQADCggIEAAAAA==.',
['Jú']='Júdgemental:BAAANQAECgYIAwAAAA==.',
Ka='Kair:BAAANQADCgcIBwAAAA==.Kalsium:BAAANQADCgUJDAAAAA==.Kami:BAAANQAECgIIAwAAAA==.Katteya:BAAANQADCgcJHAAAAA==.Kattia:BAAANQAECgUIDgAAAA==.',
Ki='Killinkair:BAAANQAECgIJAgAAAA==.Kinomihime:BAAANQAECgYJDgAAAA==.Kirajoy:BAAANQAECgUIDgAAAA==.Kisses:BAAANQADCgYICgAAAA==.',
Kn='Knyghtt:BAAANQAECgIJAgAAAA==.',
Kr='Kraviz:BAAANQADCgcICgAAAA==.Krystle:BAAANQAECgQIBAAAAA==.',
Le='Leorna:BAAANQADCgQIBQAAAA==.',
Li='Lilfonz:BAAANQAECgEIAQAAAA==.Littlejohn:BAAANQAECgQJBgAAAA==.',
Lo='Logarth:BAAANQADCggJGQABNQAECgIIAgACAAAAAA==.Londonfog:BAAANQADCggICwAAAA==.Loppandload:BAAANQADCggIEgAAAA==.Loppsang:BAAANQADCgEJAQAAAA==.Lorcan:BAAANQAECgYIDgAAAA==.',
Lr='Lroye:BAACNQAFFIEHAAMDAAIKyRVnCACvAAADAAIKyRVnCACvAAAEAAEKWAgwDwBSAAA1AAQKgScAAwMACQpmIwYCAIkDAAMACQpmIwYCAIkDAAQAAQo3DCZdAD4AAAAA.',
Lu='Lucyfer:BAAANQADCgYIBgABNQAECgIIBAACAAAAAA==.Lucyferr:BAAANQAECgIIBAAAAA==.Luliak:BAAANQAECgIIAgABNQAFFAIJAgACAAAAAA==.Lunabren:BAAANQADCgcIBgAAAA==.Lunamina:BAAANQADCgYJGQAAAA==.',
['Lì']='Lìllith:BAAANQAECgEIAQABNQAECgcIEQACAAAAAA==.',
Ma='Mariophra:BAAANQAECgMJBgAAAA==.Maxpal:BAAANQADCgUIBgAAAA==.',
Mc='Mcnastyqt:BAAANQADCgIIAgAAAA==.',
Me='Mesdel:BAAANQABCgMIAwABNQAECggJGAAFAGAcAA==.',
Mi='Mikki:BAAANQADCgIIAgAAAA==.Misstorgo:BAAANQADCgcJGQAAAA==.',
Mo='Mohegian:BAAANQABCgEIAQAAAA==.Monfro:BAAANQAECgEJAQAAAA==.Monnethir:BAAANQADCgUIBQAAAA==.Moogatoo:BAAANQADCgMIAwAAAA==.Moonbane:BAABNQAECoEQAAMGAAcK7xbEDAALAgAGAAcK7xbEDAALAgAHAAQKNA77pADlAAAAAA==.Moonmist:BAAANQABCgUIBQABNQADCgcIHQACAAAAAA==.Mordecai:BAAANQAECgUIBwAAAA==.',
My='Myaquean:BAAANQADCgUIBgAAAA==.Mystogan:BAAANQADCgYIDgAAAA==.Myth:BAAANQAECgQICwAAAA==.',
Na='Nakeefa:BAAANQADCgYIBgAAAA==.Natsuu:BAAANQAECgUIDQAAAA==.',
Ne='Neron:BAAANQAECgcIEQAAAA==.',
Ni='Niany:BAAANQADCggIEgAAAA==.',
Nj='Njoror:BAAANQAECgIJAgAAAA==.',
No='Norky:BAAANQABCgUICQABNQABCgMIAwACAAAAAA==.',
Os='Ossiferous:BAAANQAECgQJBwAAAA==.',
Ou='Outerlimits:BAAANQAECgQIBQAAAA==.',
Pa='Pamboo:BAAANQAECgYIEAAAAA==.',
Pe='Penthesilea:BAAANQABCgYIBwAAAA==.',
Pr='Priestiô:BAAANQABCgIJAgAAAA==.Pringo:BAAANQADCgYICwAAAA==.',
Ra='Ramindizzle:BAAANQAECgYIEAAAAA==.',
Re='Refreshing:BAAANQADCgUIBwAAAA==.Rekki:BAAANQAECgEJAgABNQAECgIIBAACAAAAAA==.Retastic:BAAANQADCgUIBQAAAA==.',
Ri='Rigmarole:BAAANQAECgIIAgAAAA==.',
Ro='Rocksmasher:BAAANQADCgEIAQABNQADCggJGAACAAAAAA==.Ronun:BAAANQADCgIJAwAAAA==.Rook:BAAANQAECgEIAQAAAA==.Rooklyn:BAAANQAECgYIDQAAAA==.Roye:BAAANQAECggJEwABNQAFFAIJBwADAMkVAA==.',
Ru='Rugrahh:BAAANQADCgYIBgAAAA==.Rugzco:BAAANQAECgcJEQAAAA==.Ruìn:BAAANQAECgIJBQAAAA==.',
Ry='Ryalla:BAAANQABCgEIAQAAAA==.',
['Ræ']='Ræñ:BAAANQADCgQJBAAAAA==.',
Sa='Sabina:BAAANQAECgYJDgAAAA==.Sadako:BAAANQADCgcIHAABNQAECgIIBAACAAAAAA==.Sadness:BAAANQADCgcJFgAAAA==.Sadorick:BAAANQADCgcJHAAAAA==.Sageguy:BAAANQADCgcJDwAAAA==.Saintkitiara:BAAANQABCgMIAwAAAA==.Sango:BAAANQAECgYJDgAAAA==.Savagelykill:BAAANQADCggIDgAAAA==.',
Sc='Scotch:BAAANQAECgUIDgAAAA==.Scratchies:BAAANQAECgIJAwAAAA==.',
Se='Seiwar:BAAANQAFFAEIAQAAAA==.',
Sh='Shadornia:BAAANQAECgMIBwAAAA==.Shadowcrwlr:BAAANQADCgQIBAAAAA==.Shamanio:BAABNQAECoEYAAIIAAgKkyNfDAAoAwAIAAgKkyNfDAAoAwAAAA==.Shamsham:BAAANQABCgIIAgAAAA==.Sharaaz:BAAANQADCgUIBQAAAA==.Shatoya:BAAANQADCgcIAwAAAA==.',
Si='Silverytwo:BAAANQADCgcJBwAAAA==.Silverywolfe:BAAANQADCgYIFQAAAA==.',
Sk='Skovak:BAAANQAECgMIBAAAAA==.',
So='Sorayae:BAAANQAECgYIEAAAAA==.',
Sp='Specialk:BAAANQADCgcJHAAAAA==.Splooshh:BAAANQADCggIDgABNQAECgYJDgACAAAAAA==.',
St='Steeler:BAAANQADCgcIBwABNQADCgIIAgACAAAAAA==.Stinkfoot:BAAANQAECgQIBAAAAA==.Stormkissed:BAAANQADCgcJGQAAAA==.Strawman:BAAANQADCgcIEAAAAA==.',
Su='Sugarush:BAAANQADCgQIBAABNQADCgcIHQACAAAAAA==.Sulvazud:BAAANQADCgEIAQAAAA==.Sunil:BAAANQAECgUIDgAAAA==.',
Sy='Syclone:BAAANQADCgMIAwABNQAECgkJOwAJAKkhAA==.',
Ta='Taetheras:BAAANQADCgcJEAAAAA==.Tahlyn:BAAANQADCgYIBgABNQAECgUIDgACAAAAAA==.Tattianna:BAAANQADCgYJEQAAAA==.Tavendar:BAAANQAECgYJDgABNQABCgMIAwACAAAAAA==.',
Te='Texgrebner:BAAANQADCgEIAQAAAA==.',
Th='Theeyedoctor:BAAANQADCggIBwABNQADCggJGAACAAAAAA==.Thunderslate:BAAANQADCggJGAAAAA==.Thyrok:BAAANQAECgEIAQAAAA==.',
Ti='Tigreth:BAAANQAECgYJDgAAAA==.Tinkerballa:BAAANQADCggJEgAAAA==.',
To='Toastal:BAAANQAECgIIAgAAAA==.Totemzasap:BAAANQAECgQICAAAAA==.',
Tr='Traductus:BAAANQAECgIIAgAAAA==.Tragik:BAAANQAECgYIEAAAAA==.Trisandra:BAAANQAECgEIAQAAAA==.',
Tu='Tuugadark:BAAANQAECgYIDwAAAA==.',
Tz='Tzulari:BAAANQAECgQIBAABNQAECgQIBQACAAAAAA==.',
Ul='Ulyaoth:BAAANQADCgUIBQAAAA==.',
Un='Unbroken:BAAANQADCgMIAwAAAA==.Unprepared:BAAANQABCgEIAQABNQAECgMJBAACAAAAAA==.',
Va='Vasdeferens:BAAANQABCgMIAwAAAA==.',
Ve='Vedros:BAAANQADCgEIAQAAAA==.Verbina:BAAANQAECgQIBAABNQAECgUIDgACAAAAAA==.',
Vo='Vorukh:BAAANQAECgIIBAAAAA==.',
Wa='Walkley:BAAANQAECgYIBgAAAA==.Warriorgroo:BAAANQADCgYJFQAAAA==.',
Wi='Wickedslicks:BAAANQAECgMJBgAAAA==.',
Wr='Wreckshop:BAAANQADCgYIDwABNQAECgQICQACAAAAAA==.',
Xe='Xenøcide:BAAANQADCgcICwAAAA==.',
Xi='Xiatus:BAAANQAECgQIBAAAAA==.',
Xx='Xxpallyz:BAAANQAECgMJBgAAAA==.',
Yo='Yohh:BAAANQAECgQJBgAAAA==.',
Yu='Yuriko:BAAANQAECgYJDgAAAA==.',
Za='Zadory:BAAANQADCggIDAAAAA==.Zaidan:BAAANQADCgYIBgAAAA==.',
Zi='Zippitydooda:BAAANQADCgcIHQAAAA==.',
Zo='Zodiacc:BAAANQAECgYIEAAAAA==.Zorrn:BAAANQADCgUJBwABNQADCgYJCQACAAAAAA==.',
['Zí']='Zílch:BAAANQADCgcJGAAAAA==.',
['Zö']='Zölä:BAAANQAECgIJAgABNQAECgUIBQACAAAAAA==.',
['Çh']='Çhrìs:BAAANQAECgIIBAAAAA==.',
['Çú']='Çúrsè:BAAANQADCgIIAwAAAA==.',
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
