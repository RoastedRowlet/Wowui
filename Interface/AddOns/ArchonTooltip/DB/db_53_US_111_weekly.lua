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

local lookup = {'Shaman-Elemental','Warrior-Fury','Warrior-Arms','Warrior-Protection','Mage-Arcane','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Shaman-Enhancement','Warlock-Affliction','Paladin-Retribution','Druid-Restoration','Druid-Guardian','Paladin-Holy','Warlock-Demonology','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Priest-Shadow','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','DemonHunter-Devourer','Priest-Discipline','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Paladin-Protection',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aakira:BAABNQAECn9CAAIBAAoKsRKENADLAQABAAoKsRKENADLAQAAAA==.Aathea:BAAANQADCgEIAQAAAA==.',
Ab='Abrastal:BAAANQAECgYIEQAAAA==.',
Ai='Ailmare:BAAANQADCgUIBgAAAA==.',
Al='Alline:BAAANQADCgMIAwAAAA==.Alswaron:BAAANQAECgUICgAAAA==.',
Am='Amador:BAABNQAECn8xAAQCAAoKbR6DAwAdAwACAAgKMCODAwAdAwADAAgKTB1nWgB9AgAEAAUKJBTmIABGAQAAAA==.Amyra:BAAANQABCggIEQAAAA==.',
An='Ancient:BAAANQAECggICAAAAA==.',
Ap='Aparition:BAAANQADCgcIBQAAAA==.Apsallar:BAABNQAECn8ZAAIFAAkKSBsLtwAVAgAFAAkKSBsLtwAVAgAAAA==.',
Ar='Arcanedream:BAAANQADCgIIAgABNQAECgcIDAAGAAAAAA==.Arcanism:BAABNQAECn85AAIFAAoKGBb+PwApAgAFAAoKGBb+PwApAgAAAA==.Arlas:BAAANQADCgcICwAAAA==.',
As='Asstalor:BAAANQADCgYIBgAAAA==.',
At='Athune:BAAANQAECggICAAAAA==.',
Au='Aurelya:BAAANQAECgIIAQAAAA==.Auryon:BAABNQAECn8wAAIHAAgKoB7LJQB+AgAHAAgKoB7LJQB+AgAAAA==.',
Av='Avadacadabra:BAABNQAECn8ZAAMIAAkKwxMAVgAQAgAIAAkKwxMAVgAQAgAJAAEKAADDOgAjAAAAAA==.',
Ba='Baraka:BAAANQAECgEJAQAAAA==.Baulder:BAAANQADCgEIAQAAAA==.',
Be='Beercules:BAAANQADCgYIBgAAAA==.',
Bi='Bigb:BAAANQAECgUIBQABNQAFFAkKGQAFAAweAA==.',
Bl='Bleedwoundz:BAAANQAECgIIBAAAAA==.Bluè:BAABNQAECn8bAAIBAAgKxhxlOQCRAgABAAgKxhxlOQCRAgAAAA==.',
Bo='Boltz:BAAANQAECgIIAgABNQAECggIIwAKAC4aAA==.Bonesplitter:BAAANQADCgQIBAAAAA==.Boozetotems:BAABNQAECn8lAAMIAAoKrxxcFgDYAgAIAAoKrxxcFgDYAgABAAEKAACoCgEAAAAAAA==.',
Br='Brekke:BAABNQAECn89AAILAAoKgBM0bgC0AQALAAoKgBM0bgC0AQAAAA==.',
Bu='Buffalotrace:BAAANQADCgMIAwAAAA==.Bushmethsin:BAABNQAECn8hAAMMAAoKWiIICwAZAwAMAAoKWiIICwAZAwANAAUKWSGFGADqAQAAAA==.Buttery:BAABNQAECn8nAAILAAoKrRsrWQCMAgALAAoKrRsrWQCMAgAAAA==.',
Ca='Cabb:BAAANQAECgcIEgAAAA==.',
Ch='Cheesey:BAAANQAECgYIBgABNQAECgoKLAAOAHsVAA==.Chimkinnugge:BAAANQAECgIIAgAAAA==.',
Cr='Critable:BAAANQAECgcICAAAAA==.',
Da='Daegan:BAAANQAECgEIAQAAAA==.Darkhelmet:BAAANQAECggICAAAAA==.Darwen:BAAANQADCgEIAQAAAA==.Dayna:BAAANQAECgUICAAAAA==.',
De='Dergon:BAABNQAECn8rAAIPAAoKaBgfWQBLAgAPAAoKaBgfWQBLAgAAAA==.',
Dm='Dmonicbanshe:BAAANQADCgcIBwAAAA==.',
Do='Dogwalker:BAAANQADCgYJBgABNQAECggIIwAKAC4aAA==.Doomedturtle:BAAANQABCgYICAAAAA==.',
Du='Duergan:BAACNQAFFH8IAAIQAAMK9QSFBgBlAAAQAAMK9QSFBgBlAAA1AAQKfzgAAxAACgrAEhYTALIBABEACAo2FMQqAMYBABAACgoQDBYTALIBAAAA.',
['Dà']='Dàrkblade:BAAANQADCggIGwAAAA==.',
Ea='Eatz:BAAANQAECggIEgAAAA==.',
Em='Emo:BAAANQAFFAQIBAAAAA==.',
En='Enigmaatic:BAABNQAECn86AAMFAAoKWRQ+SQAMAgAFAAoKWRQ+SQAMAgASAAMK2A1THgCzAAAAAA==.',
Er='Errisa:BAAANQAECgEIAQAAAA==.',
Fa='Fansy:BAAANQAECgQICAAAAA==.',
Fe='Felwind:BAAANQAECgQICAAAAA==.Ferinsmash:BAAANQAECgEIAQAAAA==.',
Fl='Fleurelle:BAAANQADCgYIDQAAAA==.',
Fr='Frostfree:BAABNQAECn8jAAITAAYKQQkrYwAXAQATAAYKQQkrYwAXAQAAAA==.Frydãy:BAAANQAECgQIBgAAAA==.',
Fu='Furfiend:BAABNQAECn8hAAIUAAoKdh0aKgCPAgAUAAoKdh0aKgCPAgAAAA==.',
Gb='Gb:BAABNQAECn8YAAIVAAkKkxLMHgBaAgAVAAkKkxLMHgBaAgABNQAECgcIFAAWAB4dAA==.',
Gi='Gilraen:BAABNQAECn8oAAMDAAkKTRDtiwD+AQADAAkK4g7tiwD+AQACAAMKyxH5HwC9AAAAAA==.Gilthy:BAAANQABCgEIAQAAAA==.Gingja:BAAANQADCgEIAQABNQAECgcIIQAEABYVAA==.',
Go='Goldenaege:BAAANQAECgEIAQAAAA==.Gorgrand:BAAANQAECggICAAAAA==.',
Gr='Greaseduppig:BAAANQADCgIIAgAAAA==.Greggy:BAAANQADCggICAAAAA==.',
Ha='Hairypotter:BAAANQADCgYICQABNQAECgIIBAAGAAAAAA==.Happydaze:BAABNQAECn8sAAMXAAoK/xANIwC2AQAXAAoK/xANIwC2AQAUAAEKQAgK8QAlAAAAAA==.Hardison:BAAANQAECgIIAgAAAA==.Haxthedk:BAAANQABCgEIAQAAAA==.Haxtheshaman:BAAANQABCgIIAgAAAA==.',
Ho='Hojx:BAAANQAECggIDAAAAA==.Honeydew:BAABNQAECn8kAAIBAAoK8hM5SgBNAgABAAoK8hM5SgBNAgAAAA==.',
Hr='Hrolf:BAABNQAECn8jAAINAAkKzA+0IABEAQANAAkKzA+0IABEAQABNQAFFAMICAAQAPUEAA==.',
Il='Illidont:BAAANQAECgQIDAAAAA==.Illijr:BAAANQAECgQIBgAAAA==.',
In='Interfector:BAAANQAECgUICgAAAA==.',
Jk='Jkass:BAAANQAECgEIAgAAAA==.',
Ju='Judgementdày:BAAANQAECgYIDAAAAA==.',
Ke='Kemmy:BAAANQAECgQIBwAAAA==.',
Ki='Ki:BAAANQAECgEIAgAAAA==.Kiandara:BAACNQAFFH8eAAMDAAcKIRixCQAYAgADAAYKIRixCQAYAgACAAMKqgndAQD5AAA1AAQKfz4AAwMACgraI5gLACgDAAMACgrBI5gLACgDAAIABgp0Ha8OAMMBAAAA.Kikkoman:BAABNQAECn8oAAMYAAoKcB7CHgBnAgAZAAkKLx2qHQCSAgAYAAkKRR3CHgBnAgAAAA==.Kirant:BAAANQAECgMIAwAAAA==.Kittlynia:BAAANQAECgEIAQAAAA==.Kittofdark:BAAANQAECgEIAQAAAA==.Kittrina:BAAANQAECgIIAgAAAA==.',
Kp='Kpot:BAAANQADCggIFQAAAA==.',
Ky='Kynrath:BAAANQAECgEIAQAAAA==.',
Le='Lelanie:BAAANQADCggIDAAAAA==.',
Li='Lightfrost:BAABNQAECn8sAAMOAAoKexXHOwD1AQAOAAoKexXHOwD1AQALAAkKMhFosgAsAQAAAA==.Lilithdawn:BAABNQAECn8xAAIaAAoKABajMgBAAgAaAAoKABajMgBAAgAAAA==.',
Lo='Lockkitt:BAAANQAECgMIAgAAAA==.Lockwar:BAABNQAECn8jAAIKAAgKLhqtBgDBAQAKAAgKLhqtBgDBAQAAAA==.Louvre:BAABNQAECn8hAAIZAAoKoxNADADkAQAZAAoKoxNADADkAQAAAA==.Lowehigh:BAAANQADCgUIBgAAAA==.',
Lu='Lukarian:BAAANQADCggIFAAAAA==.Luminaughty:BAAANQADCgcIDAAAAA==.',
Ma='Madmarrtigan:BAAANQADCgUICAAAAA==.Madmarttigan:BAAANQADCgUICQAAAA==.Maheehoo:BAAANQAECgQICgAAAA==.Maheewhat:BAAANQADCgYIBgABNQAECgQICgAGAAAAAA==.Mahok:BAAANQADCgMIAwAAAA==.Mashka:BAAANQAECgcIEQAAAA==.',
Me='Melbuki:BAAANQAECgIICAAAAA==.Meric:BAAANQADCggIGgAAAA==.Mesotusky:BAAANQADCgYICgABNQAECgQICgAGAAAAAA==.',
Mi='Microbrew:BAAANQAECgIIAwABNQAECgkJKQANABIaAA==.Millerlight:BAAANQADCgYJCgAAAA==.',
Mo='Moardotz:BAAANQADCgYIDgABNQAECgcIDAAGAAAAAA==.Molasses:BAABNQAECn9MAAISAAoK5R3zAwD4AgASAAoK5R3zAwD4AgAAAA==.',
['Mê']='Mêphisto:BAAANQAECgEIAQAAAA==.',
['Mï']='Mïkasa:BAAANQAECgIIAgABNQAECgkJKgADAIESAA==.',
['Mú']='Músic:BAAANQADCggICAABNQAECgQIBgAGAAAAAA==.',
Na='Nacho:BAAANQAECgIIAgAAAA==.Naptime:BAAANQADCgYIBwAAAA==.',
Ni='Nifkin:BAAANQADCgMIAwAAAA==.Nilse:BAAANQAECgUICAAAAA==.',
Nu='Nubkselk:BAABNQAECn8gAAIbAAoKlRouHgBfAgAbAAoKlRouHgBfAgAAAA==.Nurishment:BAACNQAFFH8TAAIMAAYKQBDBBwB8AQAMAAYKQBDBBwB8AQA1AAQKfygAAgwACQrmILkMAAIDAAwACQrmILkMAAIDAAAA.',
On='Onitvchi:BAAANQAECgMIAwAAAA==.',
Op='Opartos:BAAANQADCggICAAAAA==.Optistriker:BAABNQAECn9BAAIMAAoKVhXHGAD+AQAMAAoKVhXHGAD+AQAAAA==.',
Pa='Painfree:BAAANQADCggIAgAAAA==.Papabear:BAAANQADCgEIAQAAAA==.',
Pe='Peregrine:BAAANQADCgYIBgAAAA==.',
Ph='Philjaa:BAAANQAECgEIAQAAAA==.',
Po='Potatoe:BAABNQAECn8bAAQWAAkK5AutJgASAQAWAAgKmgitJgASAQAcAAUK/gPYGACpAAAaAAgKQgbKrQCmAAABNQAECgoKLAAOAHsVAA==.',
Pr='Prettyfun:BAAANQADCgUIBQAAAA==.Prometeo:BAAANQADCgMIAwAAAA==.',
Qi='Qira:BAAANQAECgYIDgAAAA==.',
Ra='Radicalism:BAAANQAECgMIAwAAAA==.Raechan:BAAANQAECgQIDQAAAA==.Rantioc:BAAANQADCgIIAgAAAA==.Rastasparkly:BAAANQADCggICAAAAA==.',
Re='Remag:BAAANQABCgQIBgAAAA==.Reparations:BAAANQAECggICAAAAA==.Rexbriefs:BAAANQADCgMIAwAAAA==.',
Ro='Rockypalboa:BAABNQAECn8fAAMOAAoKtx2zGwAGAwAOAAoKtx2zGwAGAwALAAUKgRKMDAEKAQAAAA==.',
Ru='Rulfnor:BAABNQAECn8nAAMLAAoKSQ4htwCwAQALAAoKSQ4htwCwAQAOAAUK7gSm4gC7AAAAAA==.',
Sa='Sacrifice:BAAANQADCggICgAAAA==.Sapodillà:BAAANQAECgUIDQAAAA==.Saurax:BAAANQAECgEIAQAAAA==.',
Sc='Scorench:BAAANQAECgIIBAAAAA==.Scrubzor:BAAANQAECgEIAQAAAA==.',
Se='Seldaa:BAAANQADCgYIBgAAAA==.Seraxx:BAAANQADCgIIAgAAAA==.Sevrin:BAACNQAFFH8jAAMZAAkKeBjMAAAWAgAYAAYKOR5jAgAkAgAZAAcKbRjMAAAWAgA1AAQKfzQAAxkACgrjJDsDAPgCABgACQpsJBcFADkDABkACQocIjsDAPgCAAAA.Sevro:BAAANQABCgEIAQAAAA==.',
Sh='Shammazing:BAAANQADCgcIBwABNQAECgoKLAAHAGMJAA==.Shìft:BAAANQADCggICAABNQAECgoKMwAYACkjAA==.Shîft:BAABNQAECn8zAAMYAAoKKSN5AwBqAwAYAAoKKSN5AwBqAwAZAAMKQBEDfQC/AAAAAA==.',
Si='Siiwwy:BAAANQAECgEIAgAAAA==.',
Sl='Slice:BAAANQAECgEIAQAAAA==.',
So='Sok:BAAANQAECgYIDQAAAA==.Soktear:BAAANQAECggIDwAAAA==.Soladaris:BAAANQABCggICwAAAA==.Solicide:BAABNQAECn8pAAMNAAkKEhobDwByAgANAAkKEBobDwByAgAdAAUKuhfIZAA6AQAAAA==.',
Sp='Sparkle:BAACNQAFFH8TAAIeAAUKOhAKBQAXAQAeAAUKOhAKBQAXAQA1AAQKfzkAAx4ACgqfH5ADAPcCAB4ACgqfH5ADAPcCAB8AAQpdEkk7ADkAAAAA.',
Sv='Svets:BAABNQAECn8XAAIaAAgKjx/JJQDUAgAaAAgKjx/JJQDUAgAAAA==.',
Sw='Swenzy:BAAANQABCgMIAwAAAA==.',
Sy='Sylphrenna:BAAANQADCggICwAAAA==.',
Te='Teeanna:BAAANQADCgYICQABNQADCgcICwAGAAAAAA==.Tempers:BAABNQAECn8bAAIFAAgKTw/l2gDSAQAFAAgKTw/l2gDSAQAAAA==.',
Th='Thornum:BAAANQADCgQIBAAAAA==.Thottyshotty:BAAANQABCgUIAwAAAA==.',
Ti='Tinnman:BAABNQAECn8eAAIPAAkKphFIcQBMAQAPAAkKphFIcQBMAQAAAA==.',
To='Toteschaos:BAAANQADCggIDAAAAA==.',
Tw='Twiz:BAABNQAECn8cAAILAAoKzwlXuwCmAQALAAoKzwlXuwCmAQAAAA==.Twizzly:BAAANQAECgQICwAAAA==.Twizzy:BAABNQAECn8sAAIHAAoKYwmKowC/AQAHAAoKYwmKowC/AQAAAA==.',
Tz='Tzechan:BAABNQAECn9NAAMOAAoKqSOWDgBWAwAOAAoKqSOWDgBWAwALAAEKAACNoAE3AAAAAA==.',
Ur='Urlshekk:BAABNQAECn8VAAQgAAoKhhowHgD3AQAgAAgKJRkwHgD3AQAOAAMKhwhp/gB/AAALAAIK6wmhjQFHAAAAAA==.Urrdad:BAAANQADCggIDwAAAA==.',
Va='Valtirya:BAAANQADCgIIAgAAAA==.Varumn:BAACNQAFFH8GAAIgAAIKqwSuCgBbAAAgAAIKqwSuCgBbAAA1AAQKfysABCAACQrAEs0RAM8BACAACQrAEs0RAM8BAA4AAgrcAWXYADoAAAsAAQrdAizCAScAAAE1AAUUAwgIABoAJhIA.',
Ve='Veex:BAAANQADCgUIBgAAAA==.Velithari:BAAANQADCgQIBAAAAA==.',
Vi='Viaugra:BAAANQADCgEIAQAAAA==.',
Vo='Vorhees:BAAANQAECgIIBQAAAA==.',
We='Wearegroot:BAAANQADCgcICAAAAA==.',
Wi='Wihtè:BAAANQADCgcIBwABNQAECggIGwABAMYcAA==.Wind:BAAANQADCggIDgAAAA==.',
Wr='Wraithscythe:BAAANQABCgUIBgAAAA==.',
Xa='Xandera:BAAANQADCgcJDgABNQAECgoKNgAUANsYAA==.',
Xp='Xpally:BAABNQAECn8oAAIOAAkKFRPhXQD/AQAOAAkKFRPhXQD/AQAAAA==.',
Yt='Ytoshi:BAAANQADCgYIBgAAAA==.',
['Yè']='Yèlloow:BAAANQADCgMIAwABNQAECggIGwABAMYcAA==.',
Za='Zaquel:BAAANQAECgYIBgABNQAECgoKNgAUANsYAA==.Zarcissa:BAAANQAECgUIEAAAAA==.',
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
