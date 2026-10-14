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

local lookup = {'Shaman-Elemental','Warrior-Fury','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Druid-Restoration','Druid-Guardian','Warlock-Demonology','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Rogue-Assassination','Paladin-Holy','Priest-Holy','Rogue-Subtlety','Hunter-BeastMastery','Druid-Balance','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aakira:BAABNQAECn8oAAIBAAgKpRKlYwDyAQABAAgKpRKlYwDyAQAAAA==.',
Ab='Abrastal:BAAANQAECgUIBwAAAA==.',
Ai='Ailmare:BAAANQADCgUIBgAAAA==.',
Al='Alline:BAAANQADCgMIAwAAAA==.Alswaron:BAAANQAECgUICgAAAA==.',
Am='Amador:BAABNQAECn8uAAQCAAkKmyF9AwAdAwACAAgKMCN9AwAdAwADAAgKTB1fWQB8AgAEAAQKIhhnIABGAQAAAA==.',
An='Ancient:BAAANQAECggICAAAAA==.',
Ap='Aparition:BAAANQADCgcIBQAAAA==.Apsallar:BAAANQAECgYIDgAAAA==.',
Ar='Arcanedream:BAAANQADCgIIAgABNQAECgUIBwAFAAAAAA==.Arcanism:BAABNQAECn8gAAIGAAgKxhKfsAAgAgAGAAgKxhKfsAAgAgAAAA==.Arlas:BAAANQADCgcICwAAAA==.',
As='Asstalor:BAAANQADCgYIBgAAAA==.',
At='Athune:BAAANQAECggICAAAAA==.',
Au='Aurelya:BAAANQADCgYIBgAAAA==.Auryon:BAAANQAECgUIEQAAAA==.',
Av='Avadacadabra:BAAANQAECgcIEQAAAA==.',
Ba='Baraka:BAAANQAECgEJAQAAAA==.',
Be='Beercules:BAAANQADCgYIBgAAAA==.',
Bi='Bigb:BAAANQAECgUIBQABNQAFFAcKFgAGAGgdAA==.',
Bl='Bleedwoundz:BAAANQAECgIIBAAAAA==.Bluè:BAABNQAECn8aAAIBAAgKxhyIOACRAgABAAgKxhyIOACRAgAAAA==.',
Bo='Boltz:BAAANQAECgIIAgABNQAECgYICwAFAAAAAA==.Bonesplitter:BAAANQADCgQIBAAAAA==.Boozetotems:BAAANQAECgcIEAAAAA==.',
Br='Brekke:BAABNQAECn8qAAIHAAkKshIjhwAUAgAHAAkKshIjhwAUAgAAAA==.',
Bu='Bushmethsin:BAABNQAECn8cAAMIAAkKRCLRCgAYAwAIAAkKRCLRCgAYAwAJAAUKWSECGADqAQAAAA==.Buttery:BAABNQAECn8YAAIHAAkK/BhrVwCNAgAHAAkK/BhrVwCNAgAAAA==.',
Ca='Cabb:BAAANQAECgUIBwAAAA==.',
Ch='Chimkinnugge:BAAANQAECgIIAgAAAA==.',
Cr='Critable:BAAANQAECgIIAQAAAA==.',
Da='Daegan:BAAANQAECgEIAQAAAA==.Darkhelmet:BAAANQAECggICAAAAA==.Darwen:BAAANQADCgEIAQAAAA==.Dayna:BAAANQABCgQIBgAAAA==.',
De='Dergon:BAABNQAECn8mAAIKAAkKTRewVwBMAgAKAAkKTRewVwBMAgAAAA==.',
Dm='Dmonicbanshe:BAAANQADCgcIBwAAAA==.',
Do='Dogwalker:BAAANQADCgYJBgABNQAECgYICwAFAAAAAA==.Doomedturtle:BAAANQABCgYICAAAAA==.',
Du='Duergan:BAABNQAECn8oAAMLAAkKBRPqEgCzAQAMAAgKIxRDKgDGAQALAAkKCArqEgCzAQAAAA==.',
['Dà']='Dàrkblade:BAAANQADCggIGwAAAA==.',
Ea='Eatz:BAAANQAECggIEgAAAA==.',
En='Enigmaatic:BAABNQAECn8iAAMGAAgK7xBLwgD+AQAGAAgK7xBLwgD+AQANAAEKPgkZRAA5AAAAAA==.',
Fa='Fansy:BAAANQAECgIIBAAAAA==.',
Fe='Ferinsmash:BAAANQAECgEIAQAAAA==.',
Fl='Fleurelle:BAAANQADCgYIDQAAAA==.',
Fr='Frostfree:BAABNQAECn8WAAIOAAYKQQkvYQAXAQAOAAYKQQkvYQAXAQAAAA==.Frydãy:BAAANQAECgQIBAAAAA==.',
Fu='Furfiend:BAABNQAECn8dAAIPAAkK+By9KQCPAgAPAAkK+By9KQCPAgAAAA==.',
Gb='Gb:BAAANQAFFAEIAQABNQAECgcIFAAQAB4dAA==.',
Gi='Gilraen:BAABNQAECn8oAAMDAAkKTRBCigD+AQADAAkK4g5CigD+AQACAAMKyxGXHwC9AAAAAA==.Gilthy:BAAANQABCgEIAQAAAA==.Gingja:BAAANQADCgEIAQABNQAECgYIEAAFAAAAAA==.',
Go='Goldenaege:BAAANQADCggIEQAAAA==.Gorgrand:BAAANQAECggICAAAAA==.',
Gr='Greaseduppig:BAAANQADCgIIAgAAAA==.Greggy:BAAANQADCggICAAAAA==.',
Ha='Hairypotter:BAAANQADCgMIAwABNQAECgIIBAAFAAAAAA==.Happydaze:BAABNQAECn8bAAMRAAgKiQxKWgCHAQARAAgKiQxKWgCHAQAPAAEKQAhb7gAlAAAAAA==.Hardison:BAAANQAECgIIAgAAAA==.Haxthedk:BAAANQABCgEIAQAAAA==.Haxtheshaman:BAAANQABCgIIAgAAAA==.',
Ho='Hojx:BAAANQAECgUIBQAAAA==.Honeydew:BAABNQAECn8jAAIBAAkK9BVeSQBNAgABAAkK9BVeSQBNAgAAAA==.',
Hr='Hrolf:BAAANQAECgYICQABNQAECgkJKAALAAUTAA==.',
Il='Illidont:BAAANQAECgQICgAAAA==.Illijr:BAAANQAECgQIBgAAAA==.',
In='Interfector:BAEANQAECgMIAwAAAA==.',
Jk='Jkass:BAAANQAECgEIAgAAAA==.',
Ke='Kemmy:BAAANQAECgQIBwAAAA==.',
Ki='Kiandara:BAACNQAFFH8ZAAMDAAcKHBdWCQAYAgADAAYKHBdWCQAYAgACAAMKqgnZAQD5AAA1AAQKfykAAwMACAoMIzRHALECAAMACArxIjRHALECAAIABgp0HaMOAMIBAAAA.Kikkoman:BAABNQAECn8WAAISAAgKJh4RHQCSAgASAAgKJh4RHQCSAgAAAA==.Kirant:BAAANQAECgMIAwAAAA==.Kittrina:BAAANQABCgIIAgAAAA==.',
Kp='Kpot:BAAANQADCggIFQAAAA==.',
Ky='Kynrath:BAAANQAECgEIAQAAAA==.',
Le='Lelanie:BAAANQADCggIDAAAAA==.',
Li='Lightfrost:BAABNQAECn8ZAAMTAAkKcRB6XwD3AQATAAgKsxF6XwD3AQAHAAUKKQlWSQGjAAAAAA==.Lilithdawn:BAABNQAECn8eAAIUAAgKxRCQdAC6AQAUAAgKxRCQdAC6AQAAAA==.',
Lo='Lockwar:BAAANQAECgYICwAAAA==.Louvre:BAAANQAECggIEwAAAA==.Lowehigh:BAAANQADCgUIBgAAAA==.',
Lu='Lukarian:BAAANQADCggIFAAAAA==.Luminaughty:BAAANQADCgcIDAAAAA==.',
Ma='Madmarrtigan:BAAANQADCgUICAAAAA==.Madmarttigan:BAAANQADCgUICQAAAA==.Maheehoo:BAAANQAECgQICgAAAA==.Maheewhat:BAAANQADCgYIBgABNQAECgQICgAFAAAAAA==.Mashka:BAAANQAECgYICwAAAA==.',
Me='Melbuki:BAAANQAECgEIAQAAAA==.Meric:BAAANQADCggIGgAAAA==.Mesotusky:BAAANQADCgYICgABNQAECgQICgAFAAAAAA==.',
Mi='Millerlight:BAAANQADCgYJCgAAAA==.',
Mo='Moardotz:BAAANQADCgYIDgABNQAECgUIBwAFAAAAAA==.Molasses:BAABNQAECn80AAINAAkKKR3pAwD5AgANAAkKKR3pAwD5AgAAAA==.',
['Mï']='Mïkasa:BAAANQAECgIIAgABNQAECgYIEwAFAAAAAA==.',
['Mú']='Músic:BAAANQADCggICAABNQAECgQIBAAFAAAAAA==.',
Na='Nacho:BAAANQAECgIIAgAAAA==.Naptime:BAAANQADCgUIBQAAAA==.',
Ni='Nifkin:BAAANQADCgMIAwAAAA==.Nilse:BAAANQAECgEIAgABNQAECggICgAFAAAAAA==.',
Nu='Nubkselk:BAAANQAECgYIEwAAAA==.Nurishment:BAACNQAFFH8SAAIIAAUKiBCFBwB8AQAIAAUKiBCFBwB8AQA1AAQKfyUAAggACQo2H4YMAAIDAAgACQo2H4YMAAIDAAAA.',
On='Onitvchi:BAAANQAECgMIAwAAAA==.',
Op='Optistriker:BAABNQAECn8mAAIIAAgK1BSBJQDzAQAIAAgK1BSBJQDzAQAAAA==.',
Pa='Painfree:BAAANQADCggIAgAAAA==.Papabear:BAAANQADCgEIAQAAAA==.',
Pe='Peregrine:BAAANQADCgYIBgAAAA==.',
Ph='Philjaa:BAAANQAECgEIAQAAAA==.',
Po='Potatoe:BAAANQAECgcICwABNQAECgkJGQATAHEQAA==.',
Pr='Prettyfun:BAAANQADCgUIBQAAAA==.Prometeo:BAAANQABCgQIDAAAAA==.',
Qi='Qira:BAAANQAECgYIDQAAAA==.',
Ra='Radicalism:BAAANQAECgMIAwAAAA==.Raechan:BAAANQAECgMIAwAAAA==.Rantioc:BAAANQADCgIIAgAAAA==.Rastasparkly:BAAANQADCggICAAAAA==.',
Re='Remag:BAAANQABCgIIBAAAAA==.Reparations:BAAANQAECggIBwAAAA==.Rexbriefs:BAAANQADCgMIAwAAAA==.',
Ro='Rockypalboa:BAABNQAECn8cAAMTAAkKhh0yGwAHAwATAAkKhh0yGwAHAwAHAAUKgRKhCAEKAQAAAA==.',
Ru='Rulfnor:BAABNQAECn8fAAMHAAgKHw9otACwAQAHAAgKHw9otACwAQATAAUK7gRN4AC7AAAAAA==.',
Sa='Sacrifice:BAAANQADCggICgAAAA==.Sapodillà:BAAANQAECgUICwAAAA==.Saurax:BAAANQAECgEIAQAAAA==.',
Se='Seldaa:BAAANQADCgYIBgAAAA==.Sevrin:BAACNQAFFH8dAAMVAAcKJBtTAgAkAgAVAAYKOR5TAgAkAgASAAQKnR2bBwCXAQA1AAQKfykAAxUACQrEJA0FADoDABUACQpsJA0FADoDABIABQpAIVE8ANoBAAAA.Sevro:BAAANQABCgEIAQAAAA==.',
Sh='Shammazing:BAAANQADCgcIBwABNQAECggIIwAWAP8HAA==.Shìft:BAAANQADCggICAABNQAECgkJKwAVAHIiAA==.Shîft:BAABNQAECn8rAAMVAAkKciJzAwBqAwAVAAkKciJzAwBqAwASAAMKQBGSegC+AAAAAA==.',
Sl='Slice:BAAANQAECgEIAQAAAA==.',
So='Sok:BAAANQAECgQIBAAAAA==.Soktear:BAAANQAECgUIBQAAAA==.Soladaris:BAAANQABCggICwAAAA==.Solicide:BAABNQAECn8fAAMJAAgKTxrkDgBxAgAJAAgKTBrkDgBxAgAXAAUKuhfbYwA6AQAAAA==.',
Sp='Sparkle:BAACNQAFFH8KAAIYAAQKRxTzBQAvAQAYAAQKRxTzBQAvAQA1AAQKfyoAAxgACQpoH4QDAPcCABgACQpoH4QDAPcCABkAAQpdEr46ADkAAAAA.',
Sv='Svets:BAABNQAECn8XAAIUAAgKjx8YJQDVAgAUAAgKjx8YJQDVAgAAAA==.',
Sw='Swenzy:BAAANQABCgMIAwAAAA==.',
Sy='Sylphrenna:BAAANQADCggICwAAAA==.',
Te='Teeanna:BAAANQADCgYICQABNQADCgcICwAFAAAAAA==.Tempers:BAABNQAECn8ZAAIGAAcKdhGF2ADTAQAGAAcKdhGF2ADTAQAAAA==.',
Th='Thornum:BAAANQADCgQIBAAAAA==.Thottyshotty:BAAANQABCgUIAwAAAA==.',
Ti='Tinnman:BAAANQAECgUIDgAAAA==.',
To='Toteschaos:BAAANQADCggIDAAAAA==.',
Tw='Twiz:BAAANQAECggIEwAAAA==.Twizzly:BAAANQAECgMIBAAAAA==.Twizzy:BAABNQAECn8jAAIWAAgK/wdUoQC/AQAWAAgK/wdUoQC/AQAAAA==.',
Tz='Tzechan:BAABNQAECn8tAAMTAAkKRSBeDgBWAwATAAkKRSBeDgBWAwAHAAEKAAB2mgE3AAAAAA==.',
Ur='Urlshekk:BAAANQAECggIDAAAAA==.Urrdad:BAAANQADCgMIBQAAAA==.',
Va='Valtirya:BAAANQADCgIIAgAAAA==.Varumn:BAAANQAECgEIAQAAAA==.',
Ve='Veex:BAAANQADCgUIBgAAAA==.Velithari:BAAANQADCgQIBAAAAA==.',
Vi='Viaugra:BAAANQADCgEIAQAAAA==.',
Vo='Vorhees:BAAANQABCgEIAQAAAA==.',
We='Wearegroot:BAAANQADCgcICAAAAA==.',
Wi='Wihtè:BAAANQADCgcIBwABNQAECggIGgABAMYcAA==.Wind:BAAANQADCggIDgAAAA==.',
Wr='Wraithscythe:BAAANQABCgUIBgAAAA==.',
Xa='Xandera:BAAANQADCgcJDgABNQAECgcIHgAPAHIZAA==.',
Xp='Xpally:BAABNQAECn8XAAITAAgKWxMLXQD/AQATAAgKWxMLXQD/AQAAAA==.',
Yt='Ytoshi:BAAANQADCgYIBgAAAA==.',
['Yè']='Yèlloow:BAAANQADCgMIAwABNQAECggIGgABAMYcAA==.',
Za='Zarcissa:BAAANQAECgEIBAAAAA==.',
Zo='Zosebalie:BAAANQAECgQIBQAAAA==.',
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
