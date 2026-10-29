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
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aakira:BAABNQAECn85AAIBAAoKuBEBMwCLAQABAAoKuBEBMwCLAQAAAA==.',
Ab='Abrastal:BAAANQAECgUIEAAAAA==.',
Ai='Ailmare:BAAANQADCgUIBgAAAA==.',
Al='Alline:BAAANQADCgMIAwAAAA==.Alswaron:BAAANQAECgUICgAAAA==.',
Am='Amador:BAABNQAECn8xAAQCAAoKbR6DAwAdAwACAAgKMCODAwAdAwADAAgKTB1nWgB9AgAEAAUKJBTmIABGAQAAAA==.Amyra:BAAANQABCggIEQAAAA==.',
An='Ancient:BAAANQAECggICAAAAA==.',
Ap='Aparition:BAAANQADCgcIBQAAAA==.Apsallar:BAABNQAECn8XAAIFAAgKNxwLtwAVAgAFAAgKNxwLtwAVAgAAAA==.',
Ar='Arcanedream:BAAANQADCgIIAgABNQAECgQICAAGAAAAAA==.Arcanism:BAABNQAECn8wAAIFAAoKzRP9NgAWAgAFAAoKzRP9NgAWAgAAAA==.Arlas:BAAANQADCgcICwAAAA==.',
As='Asstalor:BAAANQADCgYIBgAAAA==.',
At='Athune:BAAANQAECggICAAAAA==.',
Au='Aurelya:BAAANQAECgEIBwAAAA==.Auryon:BAABNQAECn8kAAIHAAgKtBzDIABlAgAHAAgKtBzDIABlAgAAAA==.',
Av='Avadacadabra:BAABNQAECn8YAAMIAAkKwxMAVgAQAgAIAAkKwxMAVgAQAgAJAAEKAADDOgAjAAAAAA==.',
Ba='Baraka:BAAANQAECgEJAgAAAA==.Baulder:BAAANQADCgEIAQAAAA==.',
Be='Beercules:BAAANQADCgYIBgAAAA==.',
Bi='Bigb:BAAANQAECgUIBgABNQAFFAgKFwAFAOseAA==.',
Bl='Bleedwoundz:BAAANQAECgIIBgAAAA==.Bluè:BAABNQAECn8aAAIBAAgKxhxlOQCRAgABAAgKxhxlOQCRAgAAAA==.',
Bo='Boltz:BAAANQAECgIIAgABNQAECggIHAAKAD4WAA==.Bonesplitter:BAAANQADCgQIBAAAAA==.Boozetotems:BAABNQAECn8dAAMIAAoKmhekRgBHAgAIAAoKmhekRgBHAgABAAEKAABr5wAAAAAAAA==.',
Br='Brekke:BAABNQAECn80AAILAAoKcRJhiQAUAgALAAoKcRJhiQAUAgAAAA==.',
Bu='Bushmethsin:BAABNQAECn8eAAMMAAkKRCIICwAZAwAMAAkKRCIICwAZAwANAAUKWSGFGADqAQAAAA==.Buttery:BAABNQAECn8jAAILAAoKMBorWQCMAgALAAoKMBorWQCMAgAAAA==.',
Ca='Cabb:BAAANQAECgcIEgAAAA==.',
Ch='Cheesey:BAAANQAECgYIBgABNQAECgoKJgAOANQSAA==.Chimkinnugge:BAAANQAECgIIAgAAAA==.',
Cr='Critable:BAAANQAECgcICQAAAA==.',
Da='Daegan:BAAANQAECgEIAwAAAA==.Darkhelmet:BAAANQAECggICAAAAA==.Darwen:BAAANQADCgEIAQAAAA==.Dayna:BAAANQAECgUIBwAAAA==.',
De='Dergon:BAABNQAECn8qAAIPAAoKaBgfWQBLAgAPAAoKaBgfWQBLAgAAAA==.',
Dm='Dmonicbanshe:BAAANQADCgcIBwAAAA==.',
Do='Dogwalker:BAAANQADCgYJBgABNQAECggIHAAKAD4WAA==.Doomedturtle:BAAANQAECgEIAQAAAA==.',
Du='Duergan:BAACNQAFFH8HAAIQAAMK9QRIBQBlAAAQAAMK9QRIBQBlAAA1AAQKfzQAAxAACgotEssKACMBABEACAo2FMQqAMYBABAACgp9C8sKACMBAAAA.',
['Dà']='Dàrkblade:BAAANQADCggIGwAAAA==.',
Ea='Eatz:BAAANQAECggIEgAAAA==.',
Em='Emo:BAAANQAECgcICAAAAA==.',
En='Enigmaatic:BAABNQAECn8xAAMFAAoKJRM/PAADAgAFAAoKJRM/PAADAgASAAIK0AvsRAA5AAAAAA==.',
Er='Errisa:BAAANQAECgEIAgAAAA==.',
Fa='Fansy:BAAANQAECgQIBwAAAA==.',
Fe='Felwind:BAAANQAECgQICAAAAA==.Ferinsmash:BAAANQAECgEIAQAAAA==.',
Fl='Fleurelle:BAAANQADCgYIDQAAAA==.',
Fr='Frostfree:BAABNQAECn8jAAITAAYKQQkCSAD2AAATAAYKQQkCSAD2AAAAAA==.Frydãy:BAAANQAECgQIBwAAAA==.',
Fu='Furfiend:BAABNQAECn8gAAIUAAoKdh0aKgCPAgAUAAoKdh0aKgCPAgAAAA==.',
Gb='Gb:BAABNQAECn8YAAIVAAkKkxLMHgBaAgAVAAkKkxLMHgBaAgABNQAECgcIFAAWAB4dAA==.',
Gi='Gilraen:BAABNQAECn8oAAMDAAkKTRDtiwD+AQADAAkK4g7tiwD+AQACAAMKyxH5HwC9AAAAAA==.Gilthy:BAAANQABCgEIAQAAAA==.Gingja:BAAANQADCgEIAQABNQAECgcIHAAEAPkUAA==.',
Go='Goldenaege:BAAANQADCggIEgAAAA==.Gorgrand:BAAANQAECggICAAAAA==.',
Gr='Greaseduppig:BAAANQADCgIIAgAAAA==.Greggy:BAAANQADCggICAAAAA==.',
Ha='Hairypotter:BAAANQADCgYICQABNQAECgIIBgAGAAAAAA==.Happydaze:BAABNQAECn8jAAMXAAoKvQ8ZLgA3AQAXAAoKvQ8ZLgA3AQAUAAEKQAgK8QAlAAAAAA==.Hardison:BAAANQAECgIIAwAAAA==.Haxthedk:BAAANQAECgEIAgAAAA==.Haxthemonk:BAAANQAECgEIAgAAAA==.Haxthepally:BAAANQAECgEIAgAAAA==.Haxtheshaman:BAAANQAECgEIAgAAAA==.',
Ho='Hojx:BAAANQAECgcIDwAAAA==.Honeydew:BAABNQAECn8kAAIBAAoK8hM5SgBNAgABAAoK8hM5SgBNAgAAAA==.',
Hr='Hrolf:BAABNQAECn8aAAINAAgK6g9rHwANAQANAAgK6g9rHwANAQABNQAFFAMIBwAQAPUEAA==.',
Il='Illidont:BAAANQAECgQIDAAAAA==.Illijr:BAAANQAECgQIBgAAAA==.',
In='Interfector:BAAANQAECgYICgAAAA==.',
Jk='Jkass:BAAANQAECgEIAgAAAA==.',
Ju='Judgementdày:BAAANQAECgYIBgAAAA==.',
Ke='Kemmy:BAAANQAECgQICAAAAA==.',
Ki='Ki:BAAANQAECgEIAgAAAA==.Kiandara:BAACNQAFFH8eAAMDAAcKIRixCQAYAgADAAYKIRixCQAYAgACAAMKqgndAQD5AAA1AAQKfzQAAwMACgoyI6IJABwDAAMACgoaI6IJABwDAAIABgp0Ha8OAMMBAAAA.Kikkoman:BAABNQAECn8kAAMYAAoKax2KHAA4AgAZAAkKLx2qHQCSAgAYAAkK1BqKHAA4AgAAAA==.Kirant:BAAANQAECgMIAwAAAA==.Kittlynia:BAAANQAECgEIBgAAAA==.Kittofdark:BAAANQAECgEIAgAAAA==.Kittrina:BAAANQAECgEIBAAAAA==.',
Kp='Kpot:BAAANQADCggIFQAAAA==.',
Ky='Kynrath:BAAANQAECgEIAQAAAA==.',
Le='Lelanie:BAAANQADCggIDAAAAA==.',
Li='Lightfrost:BAABNQAECn8mAAMOAAoK1BJXYAD3AQAOAAoK1BJXYAD3AQALAAkKMhE+hgBEAQAAAA==.Lilithdawn:BAABNQAECn8uAAIaAAkKFBVRMQD5AQAaAAkKFBVRMQD5AQAAAA==.',
Lo='Lockkitt:BAAANQAECgEIAwAAAA==.Lockwar:BAABNQAECn8cAAIKAAgKPhbcBACgAQAKAAgKPhbcBACgAQAAAA==.Louvre:BAABNQAECn8fAAIZAAoKkROrCgDZAQAZAAoKkROrCgDZAQAAAA==.Lowehigh:BAAANQADCgUIBgAAAA==.',
Lu='Lukarian:BAAANQADCggIFAAAAA==.Luminaughty:BAAANQADCgcIDAAAAA==.',
Ma='Madmarrtigan:BAAANQADCgUICAAAAA==.Madmarttigan:BAAANQADCgUICQAAAA==.Maheehoo:BAAANQAECgQIDQAAAA==.Maheewhat:BAAANQADCgYIBgABNQAECgQIDQAGAAAAAA==.Mahok:BAAANQADCgMIAwAAAA==.Mashka:BAAANQAECgcIEwAAAA==.',
Me='Melbuki:BAAANQAECgEIBwAAAA==.Mennathil:BAAANQAECgEIAgAAAA==.Meric:BAAANQADCggIGgAAAA==.Mesotusky:BAAANQADCgYICgABNQAECgQIDQAGAAAAAA==.',
Mi='Millerlight:BAAANQADCgYJCgAAAA==.',
Mo='Moardotz:BAAANQADCgYIDgABNQAECgQICAAGAAAAAA==.Molasses:BAABNQAECn9CAAISAAoKyx3zAwD4AgASAAoKyx3zAwD4AgAAAA==.',
['Mê']='Mêphisto:BAAANQAECgEIAQAAAA==.',
['Mï']='Mïkasa:BAAANQAECgIIAgABNQAECgkJIQADACESAA==.',
['Mú']='Músic:BAAANQADCggICAABNQAECgQIBwAGAAAAAA==.',
Na='Nacho:BAAANQAECgIIAgAAAA==.Naptime:BAAANQADCgYIBwAAAA==.',
Ni='Nifkin:BAAANQADCgMIAwAAAA==.Nilse:BAAANQAECgEIAgABNQAECggICQAGAAAAAA==.',
Nu='Nubkselk:BAABNQAECn8eAAIbAAkKeBsuHgBfAgAbAAkKeBsuHgBfAgAAAA==.Nurishment:BAACNQAFFH8TAAIMAAYKQBDBBwB8AQAMAAYKQBDBBwB8AQA1AAQKfycAAgwACQrPH7kMAAIDAAwACQrPH7kMAAIDAAAA.',
On='Onitvchi:BAAANQAECgMIBAAAAA==.',
Op='Optistriker:BAABNQAECn83AAIMAAoKbRPQFADdAQAMAAoKbRPQFADdAQAAAA==.',
Pa='Painfree:BAAANQADCggIAgAAAA==.Papabear:BAAANQAECgEIAQAAAA==.Papamuzan:BAAANQAECgEIAQAAAA==.',
Pe='Peregrine:BAAANQADCgYIBgAAAA==.',
Ph='Philjaa:BAAANQAECgEIAQAAAA==.',
Po='Potatoe:BAABNQAECn8ZAAQWAAkK5AsqHgAXAQAWAAcKmggqHgAXAQAcAAUK/gPYGACpAAAaAAgKQgaTlACmAAABNQAECgoKJgAOANQSAA==.',
Pr='Prettyfun:BAAANQADCgUIBQAAAA==.Prometeo:BAAANQAECgEIAQAAAA==.',
Qi='Qira:BAAANQAECgYIEAAAAA==.',
Ra='Radicalism:BAAANQAECgMIAwAAAA==.Raechan:BAAANQAECgQIDQAAAA==.Rantioc:BAAANQADCgIIAgAAAA==.Rastasparkly:BAAANQADCggICAAAAA==.',
Re='Remag:BAAANQABCgQIBgAAAA==.Reparations:BAAANQAECggIBwAAAA==.Rexbriefs:BAAANQADCgMIAwAAAA==.',
Ro='Rockypalboa:BAABNQAECn8eAAMOAAoKwByzGwAGAwAOAAoKwByzGwAGAwALAAUKgRKMDAEKAQAAAA==.',
Ru='Rulfnor:BAABNQAECn8mAAMLAAoKSQ4htwCwAQALAAoKSQ4htwCwAQAOAAUK7gSm4gC7AAAAAA==.',
Sa='Sacrifice:BAAANQADCggICgAAAA==.Sapodillà:BAAANQAECgUIDgAAAA==.Saurax:BAAANQAECgEIAQAAAA==.',
Sc='Scorench:BAAANQAECgEIAQAAAA==.Scrubzor:BAAANQAECgEIAgAAAA==.',
Se='Seldaa:BAAANQADCgYIBgAAAA==.Seraxx:BAAANQADCgIIAgAAAA==.Sevrin:BAACNQAFFH8iAAMZAAgKBRq8AADXAQAYAAYKOR5jAgAkAgAZAAYK+Rm8AADXAQA1AAQKfzMAAxkACgrjJPYBABkDABgACQpsJBcFADkDABkACQocIvYBABkDAAAA.Sevro:BAAANQAECgEIAwAAAA==.',
Sh='Shammazing:BAAANQADCgcIBwABNQAECgoKKAAHAAcJAA==.Shìft:BAAANQADCggICAABNQAECgoKMQAYAOIiAA==.Shîft:BAABNQAECn8xAAMYAAoK4iJ5AwBqAwAYAAoK4iJ5AwBqAwAZAAMKQBEDfQC/AAAAAA==.',
Si='Siiwwy:BAAANQAECgIIAwAAAA==.',
Sl='Slice:BAAANQAECgEIAwAAAA==.',
So='Sok:BAAANQAECgQIDQAAAA==.Soktear:BAAANQAECgYIDgAAAA==.Soladaris:BAAANQABCggICwAAAA==.Solicide:BAABNQAECn8jAAMNAAkKEhobDwByAgANAAkKEBobDwByAgAdAAUKuhfIZAA6AQAAAA==.',
Sp='Sparkle:BAACNQAFFH8TAAIeAAUKOhBbAwAcAQAeAAUKOhBbAwAcAQA1AAQKfy8AAx4ACgpZH5ADAPcCAB4ACgpZH5ADAPcCAB8AAQpdEkk7ADkAAAAA.',
St='Stolenhearth:BAAANQAECgEIBgAAAA==.',
Sv='Svets:BAABNQAECn8XAAIaAAgKjx/JJQDUAgAaAAgKjx/JJQDUAgAAAA==.',
Sw='Swenzy:BAAANQABCgMIAwAAAA==.',
Sy='Sylphrenna:BAAANQADCggICwAAAA==.',
Te='Teeanna:BAAANQADCgYICQABNQADCgcICwAGAAAAAA==.Tempers:BAABNQAECn8bAAIFAAgKTw/l2gDSAQAFAAgKTw/l2gDSAQAAAA==.',
Th='Thornum:BAAANQADCgQIBAAAAA==.Thottyshotty:BAAANQAECgEIAQAAAA==.',
Ti='Tinnman:BAABNQAECn8dAAIPAAkKNRDAWQBWAQAPAAkKNRDAWQBWAQAAAA==.',
To='Toteschaos:BAAANQADCggIDAAAAA==.',
Tw='Twiz:BAABNQAECn8aAAILAAoKzwlXuwCmAQALAAoKzwlXuwCmAQAAAA==.Twizzly:BAAANQAECgQICQAAAA==.Twizzy:BAABNQAECn8oAAIHAAoKBwmKowC/AQAHAAoKBwmKowC/AQAAAA==.',
Tz='Tzechan:BAABNQAECn87AAMOAAoKqSOWDgBWAwAOAAoKqSOWDgBWAwALAAEKAACNoAE3AAAAAA==.',
Ur='Urlshekk:BAAANQAECggIEwAAAA==.Urrdad:BAAANQADCgcICQAAAA==.',
Va='Valtirya:BAAANQADCgIIAgAAAA==.Varumn:BAABNQAECn8fAAQgAAkKvQ1fEACaAQAgAAkKvQ1fEACaAQAOAAIK3AH5vQA9AAALAAEK3QIswgEnAAABNQAFFAIIBQAaAGoRAA==.',
Ve='Veex:BAAANQADCgUIBgAAAA==.Velithari:BAAANQADCgQIBAAAAA==.',
Vi='Viaugra:BAAANQADCgEIAQAAAA==.',
Vo='Vorhees:BAAANQAECgIIBgAAAA==.',
We='Wearegroot:BAAANQADCgcICAAAAA==.',
Wi='Wihtè:BAAANQADCgcIBwABNQAECggIGgABAMYcAA==.Wind:BAAANQADCggIDgAAAA==.',
Wr='Wraithscythe:BAAANQAECgEIAQAAAA==.',
Xa='Xandera:BAAANQADCgcJDgAAAA==.',
Xp='Xpally:BAABNQAECn8mAAIOAAkKFRMNQQCSAQAOAAkKFRMNQQCSAQAAAA==.',
Yt='Ytoshi:BAAANQADCgYIBgAAAA==.',
['Yè']='Yèlloow:BAAANQADCgMIAwABNQAECggIGgABAMYcAA==.',
Za='Zarcissa:BAAANQAECgQICwAAAA==.',
Zo='Zosebalie:BAAANQAECgQICQAAAA==.',
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
