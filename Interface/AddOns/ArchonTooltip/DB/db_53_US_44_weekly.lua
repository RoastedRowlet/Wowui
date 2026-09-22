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

local lookup = {'Hunter-BeastMastery','Warrior-Arms','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Druid-Guardian','Evoker-Preservation','Paladin-Retribution','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Restoration','Druid-Feral','Warlock-Demonology','Priest-Holy','Priest-Discipline','Priest-Shadow','Shaman-Elemental','Monk-Brewmaster','Warlock-Destruction','Mage-Frost','Evoker-Devastation','DeathKnight-Frost','Shaman-Enhancement','Paladin-Holy','Monk-Mistweaver',}
local provider = {region='US',realm='Boulderfist',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abobadrin:BAAANQADCgcIDgAAAA==.Abrakadaver:BAAANQAECgcIEQAAAA==.',
Ac='Acceb:BAAANQADCgQJBAAAAA==.',
Ad='Adventureux:BAABNQAECoEZAAIBAAgK1xgnOABUAgABAAgK1xgnOABUAgAAAA==.',
Ae='Aedx:BAAANQAECggIEwAAAA==.Aerolorea:BAAANQADCgYICQAAAA==.',
Al='Alastar:BAABNQAECoEZAAICAAgKqx/XKgDCAgACAAgKqx/XKgDCAgABNQABCgYIBgADAAAAAA==.Alexmage:BAAANQADCgYIBgABNQADCgcIBwADAAAAAA==.Alios:BAAANQAECgQIBAAAAA==.Alucard:BAAANQAECgYJCQAAAA==.Alunadoom:BAAANQAECgUIBQAAAA==.Alvera:BAABNQAECoEfAAIEAAkKRSCkCgA7AwAEAAkKRSCkCgA7AwAAAA==.',
Am='Ambellìna:BAAANQADCgIIAgAAAA==.',
An='Ancestor:BAAANQAECgUJDgAAAA==.Angechi:BAEANQADCgIJAgABNQAECggJHQAFAN4HAA==.Angrydk:BAAANQADCggJHgAAAA==.Antisocial:BAABNQAECoEXAAIEAAkKiB76DQATAwAEAAkKiB76DQATAwABNQAECgkKFwAEAIgeAA==.',
Ar='Arm:BAABNQAECoEeAAQGAAkKEgtuGADtAQAGAAkKEgtuGADtAQAHAAUKVAk6WQDnAAAIAAEKehPmMwAtAAAAAA==.Armee:BAAANQAECgcJDgAAAA==.Armz:BAAANQABCgEIAQAAAA==.',
As='Astrael:BAAANQAECgYICwAAAA==.Aszea:BAAANQADCggJHgAAAA==.',
Ax='Axra:BAAANQAECgYJDAAAAA==.',
Az='Azzman:BAAANQADCgMIAwAAAA==.Azóg:BAAANQAECgQICgAAAA==.',
Ba='Balsin:BAAANQAECgUJDgAAAA==.Bambii:BAAANQADCgUIBwAAAA==.Bangungot:BAAANQAECgMJAwABNQAFFAcJDgAJAMIVAA==.Barlaf:BAABNQAECoEaAAIBAAgKhxtTKwCGAgABAAgKhxtTKwCGAgABNQADCggIDQADAAAAAA==.Batou:BAAANQAECgUICAAAAA==.',
Be='Beeski:BAAANQADCgQJCgAAAA==.Beeto:BAABNQAECoEdAAIKAAkKFBURPgBaAgAKAAkKFBURPgBaAgAAAA==.Belyndris:BAAANQAECgYIBgAAAA==.Benlian:BAEBNQAECoEdAAIFAAgK3geURgBsAQAFAAgK3geURgBsAQAAAA==.',
Bl='Blâze:BAABNQAECoEbAAILAAkKgBm5RgC3AgALAAkKgBm5RgC3AgAAAA==.',
Bo='Bonknsmash:BAABNQAECoEbAAICAAgKuRE9XAD+AQACAAgKuRE9XAD+AQAAAA==.Boof:BAAANQAECgcJEwAAAA==.Boregut:BAAANQAECggICAAAAA==.',
Br='Brewdock:BAAANQABCgIIAgAAAA==.Bronxor:BAAANQAECgcIEwAAAA==.',
Bu='Bubbleoshift:BAAANQADCgQIBAABNQAECgUJDgADAAAAAA==.Bushgarden:BAAANQADCgYIBwABNQADCgYICgADAAAAAA==.Buzsmash:BAAANQAECgYIBgAAAA==.Buzzbuzz:BAAANQAECgMIBQABNQAECgYJCgADAAAAAA==.',
['Bó']='Bóba:BAACNQAFFIEQAAIJAAYKth9/AQBRAgAJAAYKth9/AQBRAgA1AAQKgSMAAgkACQqSIxsEAEwDAAkACQqSIxsEAEwDAAAA.',
['Bö']='Böba:BAAANQAFFAEIAgABNQAFFAYJEAAJALYfAA==.',
Ca='Cadiva:BAAANQADCgQIBAABNQAECgUJDgADAAAAAA==.Cadroyd:BAAANQAECgEIAQAAAA==.Caelin:BAABNQAECoEYAAMMAAgKrQ4/JwDVAQAMAAcKkBA/JwDVAQANAAEKegG9WAAjAAAAAA==.Cailand:BAAANQAECgUJCAAAAA==.Caishana:BAABNQAECoEZAAIOAAgK8B+iFwDLAgAOAAgK8B+iFwDLAgAAAA==.Cambium:BAAANQAECgUIBwAAAA==.Camerbunne:BAAANQADCgYIDwAAAA==.Catdude:BAAANQAECgQJBQAAAA==.',
Ce='Cecil:BAAANQADCgYIBgAAAA==.',
Ch='Chaddingus:BAAANQAECgcJBwAAAA==.Chopadk:BAABNQAECoEgAAIFAAkK6Q5jNADLAQAFAAkK6Q5jNADLAQAAAA==.Chumlëy:BAAANQADCgUJBQAAAA==.',
Cl='Clash:BAAANQADCgUICAAAAA==.Clique:BAAANQAECgUJCAAAAA==.',
Co='Coldbreeze:BAAANQAECgQICQAAAA==.Collateral:BAAANQADCgcIBwAAAA==.Colomel:BAAANQAECgQJBwAAAA==.Comegetsum:BAAANQADCgYIEQAAAA==.Compaktdisc:BAAANQADCgYJBgABNQAECgUJDgADAAAAAA==.Conqbine:BAAANQADCgcJDQAAAA==.Corg:BAAANQADCgUIBQAAAA==.Countchocula:BAAANQAECgQICAAAAA==.',
Cr='Crimmi:BAAANQAECgQIBAAAAA==.Critzilla:BAAANQADCgYJDAAAAA==.',
Cu='Cuddy:BAAANQADCgYICgAAAA==.',
Cy='Cybuster:BAAANQADCgUJBQABNQAECgcIDgADAAAAAA==.Cyndle:BAABNQAECoEdAAIOAAkKaQk5RwDOAQAOAAkKaQk5RwDOAQAAAA==.',
Da='Daddythicc:BAABNQAECoEZAAILAAgKsQoynwDKAQALAAgKsQoynwDKAQAAAA==.Darrkness:BAAANQADCgYIBgAAAA==.',
De='Deadgirljd:BAAANQADCgcICwAAAA==.Deadillusion:BAAANQADCgUIBQABNQADCggIDwADAAAAAA==.Deathpockets:BAAANQAECgMIBAAAAA==.Deran:BAAANQAECgUJCgAAAA==.',
Di='Diante:BAAANQADCggICAAAAA==.Dimple:BAAANQAECgIJAgAAAA==.Dirtmonkgirt:BAAANQAECgYICwAAAA==.',
Do='Doofus:BAAANQADCgEIAQAAAA==.Doompockets:BAAANQAECgcIEgAAAA==.',
Dr='Dracara:BAAANQAECgcICgAAAA==.Dracia:BAAANQAECgYIEAAAAA==.Drakulya:BAAANQABCgQIBAAAAA==.Dreadz:BAAANQAECgYJEQAAAA==.Drewish:BAABNQAECoEZAAIPAAgKRBxGBQCiAgAPAAgKRBxGBQCiAgAAAA==.Drg:BAAANQADCgQIBAABNQADCgUIBQADAAAAAA==.Drizzle:BAAANQAECgcJEwAAAA==.Drktotem:BAAANQAECgYIDAAAAA==.Druidia:BAAANQADCgIIAgAAAA==.',
Du='Dulezlok:BAAANQADCgUIBQAAAA==.Dumbdog:BAACNQAFFIEPAAIGAAUK3iIcAQD5AQAGAAUK3iIcAQD5AQA1AAQKgSQAAgYACQq3Iu0DAFgDAAYACQq3Iu0DAFgDAAAA.Dumbledwarf:BAAANQADCggICAAAAA==.Dusan:BAAANQAECgUJDAAAAA==.',
['Dï']='Dïvinity:BAAANQADCgIIAgAAAA==.',
Ea='Ea:BAAANQADCgEIAQAAAA==.',
Ec='Echeyaket:BAAANQAECgUJDAAAAA==.',
Ed='Edonsian:BAABNQAECoEbAAICAAgK3RNbWAAMAgACAAgK3RNbWAAMAgAAAA==.',
Eg='Egmont:BAAANQADCgUIBwAAAA==.',
El='Elektabuzz:BAAANQADCggIEAABNQAECgUICgADAAAAAA==.Elelusion:BAAANQADCggIDwAAAA==.Elliekins:BAAANQADCgUJCgAAAA==.Ellunaris:BAEANQADCgUJBQABNQAECggJHQAFAN4HAA==.Elçhapo:BAAANQAECgIIAwAAAA==.',
En='Enoka:BAABNQAECoEXAAILAAgKmBbBcwA4AgALAAgKmBbBcwA4AgAAAA==.',
Es='Estelá:BAAANQADCgYIBgAAAA==.',
Et='Etikwa:BAAANQAECgUICQAAAA==.',
Eu='Euclid:BAAANQAECgMIAwAAAA==.',
Ev='Evilguard:BAABNQAECoEZAAIFAAgKhA0EPgCWAQAFAAgKhA0EPgCWAQAAAA==.',
Ex='Excessive:BAAANQADCggICwAAAA==.Exroastbeef:BAAANQADCggICAAAAA==.',
Fa='Falador:BAAANQAECgIIAgAAAA==.Fariebubbles:BAAANQADCggJFwAAAA==.',
Fe='Felene:BAAANQAECgcIEwAAAA==.',
Fi='Firitako:BAAANQAECgIJAgAAAA==.',
Fr='Frailey:BAAANQAECgUIDQAAAA==.Frankiejr:BAAANQADCggJFwABNQAECgMJBgADAAAAAA==.Fraubles:BAAANQAECgIIAgAAAA==.Friedpickel:BAAANQADCgYIBwAAAA==.Friter:BAAANQADCggICQAAAA==.Frostnite:BAAANQAECgQJBwAAAA==.Frostpoptart:BAAANQAECgYJCwAAAA==.Frozenblade:BAABNQAECoEWAAIFAAgK1BZlKgAJAgAFAAgK1BZlKgAJAgAAAA==.',
Fu='Furball:BAAANQADCgYIBgABNQAECgkJHAAQACIfAA==.Furiousgeorg:BAAANQAECgUIDAAAAA==.',
Ga='Gagabooney:BAAANQAFFAEJAQAAAA==.Garabashi:BAAANQADCgcJBwAAAA==.Gazze:BAAANQAECgUJDAAAAA==.',
Ge='Gennissa:BAAANQAECgMIBAAAAA==.Gethsemane:BAAANQAECgYJEwAAAA==.',
Gi='Gigadoot:BAAANQABCgQIAgAAAA==.Gigglez:BAAANQADCgcJCQAAAA==.',
Gn='Gnryderp:BAAANQADCgUIBQAAAA==.',
Go='Goam:BAAANQADCggJFwAAAA==.Goonielama:BAABNQAECoEaAAIFAAkK4h+oCgAtAwAFAAkK4h+oCgAtAwABNQAFFAEJAQADAAAAAA==.Goonietai:BAAANQAECgQJBAABNQAECgkJHwALANAdAA==.',
Gr='Griitz:BAAANQAECgQIBAAAAA==.Grimmsheeper:BAABNQAECoEoAAILAAkKKiDNJgAfAwALAAkKKiDNJgAfAwAAAA==.Gryff:BAAANQADCgUJBQAAAA==.',
Gu='Guess:BAAANQAECgQIBAAAAA==.Gurtdk:BAACNQAFFIEOAAMEAAYK6h4JAQD1AQAEAAUKoR4JAQD1AQAFAAEKVSCwFgBcAAA1AAQKgR8AAgQACQplJbkCAMADAAQACQplJbkCAMADAAAA.',
Gy='Gyat:BAAANQADCgMJAwAAAA==.',
Ha='Hairynujabes:BAAANQAECggIDgAAAA==.Hanyuu:BAAANQAECgYJDgAAAA==.',
He='Heiter:BAABNQAECoEbAAIRAAcKIhpcOgACAgARAAcKIhpcOgACAgAAAA==.Hellbound:BAAANQAECgcIEQAAAA==.Hellinhunt:BAAANQAECgYIBgAAAA==.',
Ho='Holyekko:BAAANQADCgEIAQAAAA==.Honk:BAAANQAECgUIBQABNQAECgYJCgADAAAAAA==.Hornivore:BAAANQADCgcJBwAAAA==.',
Hy='Hyrja:BAAANQADCgUJBgABNQAECgcICgADAAAAAA==.',
Ic='Icefrosting:BAAANQAECgQIBwAAAA==.',
Id='Idistroya:BAAANQAECgQJBgABNQAECgYIEwADAAAAAA==.',
Ig='Iggnogg:BAAANQADCggJGQAAAA==.',
Ik='Ikura:BAABNQAECoEeAAQSAAkKHBI6CACIAQARAAkKpgxEQgDcAQASAAcKMg06CACIAQATAAEKbwhxWwAmAAAAAA==.',
Il='Ilithiya:BAAANQAECgYIDwAAAA==.Ilk:BAAANQAECgUIBQAAAA==.',
Im='Imangry:BAAANQADCgEJAQAAAA==.',
Is='Isaidnoice:BAAANQADCgYICgAAAA==.Ishiftmyself:BAAANQAECgUJDgAAAA==.Ishton:BAAANQAECgcIEAAAAA==.Istompgnomes:BAAANQAECgYIEwAAAA==.',
It='Itsnowz:BAAANQADCgQIBAAAAA==.',
Ja='Jasøn:BAAANQADCgcIDgABNQAECgQJCAADAAAAAA==.',
Je='Jecthyr:BAAANQAECgcIDQAAAA==.Jefeson:BAAANQAECgMIAwAAAA==.Jermdaga:BAAANQADCgQIBAAAAA==.',
Ji='Jinnasaiquoi:BAAANQADCggIDgAAAA==.',
Js='Jsdruid:BAAANQAECgEIAQAAAA==.',
Ka='Kaelosu:BAABNQAECoElAAIQAAkKuhtrFADvAgAQAAkKuhtrFADvAgAAAA==.Kakum:BAAANQADCgYIFQAAAA==.Kaldrogo:BAAANQADCgcJCQAAAA==.Kalnuggets:BAAANQADCggIFwAAAA==.Kalrathen:BAABNQAECoEfAAMRAAkKlBADMAA3AgARAAkKlBADMAA3AgATAAEKewFjYwAZAAAAAA==.Kanda:BAABNQAECoEcAAIBAAgKWBR5OABTAgABAAgKWBR5OABTAgAAAA==.Karsh:BAAANQAECgUJDAAAAA==.Kazadax:BAAANQAECgUIDAAAAA==.',
Ke='Kealosu:BAAANQADCggIDgAAAA==.Keuaakepo:BAAANQAECgYIEwAAAA==.',
Ki='Kienne:BAAANQAECgUICwAAAA==.Kiljaedra:BAAANQADCgQIBAAAAA==.Kinomi:BAAANQADCgYJBgABNQAECgUJDgADAAAAAA==.Kitenna:BAAANQAECgMIAwAAAA==.',
Kl='Kleenex:BAAANQADCgEIAQAAAA==.',
Ko='Korbanhavoc:BAAANQAECgYJCwAAAA==.Korogar:BAAANQAECgIJAQAAAA==.',
Kp='Kpes:BAAANQADCgUJBQAAAA==.',
Kr='Kreamyumyums:BAAANQAECgUIBQAAAA==.Krisp:BAAANQADCgUICAAAAA==.Krizzl:BAAANQADCgUIBQABNQAECgkJIAAEAI8kAA==.Kronknar:BAAANQABCgQJBAABNQAECggJGAAUAEgXAA==.',
Ky='Kymira:BAABNQAECoEcAAIVAAgKbhnLBwBSAgAVAAgKbhnLBwBSAgAAAA==.',
La='Lace:BAABNQAECoElAAMQAAgK8x1MGwDEAgAQAAgKzRxMGwDEAgAWAAIKUyEHNwDCAAAAAA==.Lanzen:BAAANQADCgEIAQAAAA==.Larrfena:BAABNQAECoEZAAIBAAgKFBfjNQBcAgABAAgKFBfjNQBcAgAAAA==.Lazarou:BAAANQADCgUJCgAAAA==.',
Le='Legsday:BAAANQADCgQJBQAAAA==.Lementz:BAACNQAFFIEMAAIUAAQK8BTlBgBUAQAUAAQK8BTlBgBUAQA1AAQKgSAAAhQACQrLH5MOAEEDABQACQrLH5MOAEEDAAAA.',
Li='Liadres:BAAANQADCgIIAgAAAA==.Liante:BAAANQADCgcJEgABNQADCggICAADAAAAAA==.Libellule:BAAANQABCgQIBAAAAA==.Lilboat:BAAANQAECgEIAQAAAA==.Lillia:BAAANQAECgUJDAAAAA==.Lillybell:BAAANQADCgUIBQAAAA==.Littleboyz:BAAANQADCgcIBwAAAA==.',
Lo='Loop:BAAANQAECggICAAAAA==.Loopku:BAAANQAECggICAAAAA==.Lorinash:BAAANQADCgYICQAAAA==.Lothelo:BAAANQAECgEIAgABNQAECggJGQAKAIscAA==.',
Lu='Lumpia:BAAANQAECgcIEQAAAA==.',
Lv='Lvel:BAAANQADCgYICgAAAA==.',
Ma='Maey:BAABNQAECoEcAAMLAAgKrhUodAA3AgALAAgKExModAA3AgAXAAEKASGEJABfAAAAAA==.Magoobers:BAAANQADCgEIAQAAAA==.Maktah:BAABNQAECoEYAAIUAAgKSBdzMABHAgAUAAgKSBdzMABHAgAAAA==.Malpractice:BAAANQABCgQIBAABNQAECgUJDgADAAAAAA==.Maybesinged:BAABNQAECoEXAAILAAgKdhEigQAVAgALAAgKdhEigQAVAgAAAA==.',
Me='Meanboy:BAAANQAECgMIAwAAAA==.Meishra:BAAANQADCgcICQAAAA==.Mentos:BAABNQAECoEcAAIYAAgKhh0sCAC/AgAYAAgKhh0sCAC/AgAAAA==.',
Mi='Midgetninja:BAAANQADCgQIBAABNQAECgUJDgADAAAAAA==.Miltank:BAABNQAECoEaAAIKAAcKZBsEVgAAAgAKAAcKZBsEVgAAAgAAAA==.Minaqt:BAAANQADCgEIAQAAAA==.Minatory:BAABNQAECoEXAAINAAgK/BY3GABQAgANAAgK/BY3GABQAgAAAA==.Mionn:BAAANQAECgUICgAAAA==.Misfires:BAAANQABCggJEQAAAA==.',
Ml='Mlleena:BAAANQAECgUJDAAAAA==.',
Mo='Moddim:BAAANQADCgUIBQAAAA==.Modotz:BAAANQADCgEIAQAAAA==.Mogg:BAAANQAECgEIAQAAAA==.Moghoul:BAAANQAECgQIBQAAAA==.Montorgo:BAAANQADCgYIBgAAAA==.Moofi:BAAANQADCgYJCwABNQAECgIJAwADAAAAAA==.Mooncake:BAAANQAECgYJEQAAAA==.Moosiah:BAAANQADCgcIBwAAAA==.Motoko:BAAANQAECgYJDgAAAA==.',
Mu='Musesong:BAAANQADCgMIAwAAAA==.',
['Mø']='Møø:BAAANQADCggJCQABNQAECgQJCAADAAAAAA==.Møøfi:BAAANQAECgIJAwAAAA==.',
Na='Naianasha:BAAANQAECgQJBAAAAA==.Nameless:BAABNQAECoEXAAILAAcKdginvgCFAQALAAcKdginvgCFAQAAAA==.Narc:BAAANQAECgEIAQAAAA==.',
Ne='Necroraise:BAAANQADCgIIAgAAAA==.Neeraj:BAAANQAECgMIBgAAAA==.',
No='Nokzash:BAAANQAECgUJCAAAAA==.Noova:BAABNQAECoEbAAILAAkKARsQPQDVAgALAAkKARsQPQDVAgAAAA==.',
Ny='Nyang:BAAANQAECgYICwAAAA==.Nythendrac:BAAANQADCgQIBAABNQAECgcICgADAAAAAA==.',
Ob='Obliverat:BAAANQAECggICAAAAA==.',
Ok='Okiedokie:BAAANQADCgQIBAABNQAECgUIDQADAAAAAA==.',
Oo='Oongaboonga:BAABNQAECoEUAAICAAcKWRMhawDMAQACAAcKWRMhawDMAQAAAA==.',
Or='Orcaneblast:BAABNQAECoEfAAILAAkK0B2qMQD5AgALAAkK0B2qMQD5AgAAAA==.Orcsoup:BAAANQAECgYJEAAAAA==.',
Pa='Paranoià:BAAANQADCgIIAgABNQADCgIIAgADAAAAAA==.',
Pe='Penance:BAAANQAECgYICwAAAA==.',
Pi='Pivnert:BAAANQAECgQICgAAAA==.',
Po='Popdkook:BAAANQADCgYIEgAAAA==.',
Pr='Proko:BAAANQADCggICAAAAA==.',
Ps='Psychopump:BAAANQAECgQIBQAAAA==.',
['Pü']='Pünish:BAABNQAECoEuAAQEAAkKCCBTDwADAwAEAAgKDiJTDwADAwAZAAMKcxSgRwDRAAAFAAEKXwX4mgAuAAAAAA==.',
Qq='Qqpewpew:BAAANQAECggIBAAAAA==.',
Qu='Quinn:BAAANQADCgIJAgABNQAECgUJDgADAAAAAA==.',
Ra='Rabit:BAAANQADCgUIBQAAAA==.Raelina:BAABNQAECoEaAAMLAAkKmR35MgD1AgALAAkKVRz5MgD1AgAXAAIKRRplGgCuAAABNQAFFAcIEwAXAEIQAA==.Ragingiscool:BAAANQADCggIDQAAAA==.Rail:BAAANQADCggJBwAAAA==.Rajank:BAAANQADCgQIBAAAAA==.Rallek:BAAANQAECgcIEQAAAA==.Ranuggul:BAAANQAECgEIAQAAAA==.Raza:BAAANQAECgIIBQABNQAECgkJLgAEAAggAA==.',
Re='Reddawn:BAAANQADCgcIBwAAAA==.Remeras:BAAANQAECgMIAwAAAA==.',
Ri='Riken:BAAANQAECgUIDQAAAA==.',
Ro='Roadi:BAAANQAECgMJAwABNQAECggJGQAQADUbAA==.Roxer:BAAANQAECgUICQAAAA==.',
Ru='Rummyy:BAAANQAECggJAQAAAA==.',
Ry='Rycken:BAAANQAECgUJCgAAAA==.',
Sa='Saeylva:BAAANQADCgcJDgAAAA==.Saosis:BAAANQADCgYICgAAAA==.Savage:BAAANQADCgIIAgAAAA==.Sayurri:BAAANQADCgEJAQAAAA==.',
Sc='Scribble:BAAANQAECgMIBAAAAA==.Sculper:BAAANQAECgUICwAAAA==.',
Se='Seriphina:BAAANQADCggICAAAAA==.',
Sg='Sgornyweaver:BAAANQADCgUJBQAAAA==.',
Sh='Shabbarankzz:BAAANQAECgYJEQAAAA==.Shadetotem:BAAANQAECgQJBwAAAA==.Shammyblammy:BAAANQABCgEIAQAAAA==.Sheshotu:BAAANQADCggIEQAAAA==.Shinedown:BAAANQADCgMIAwAAAA==.Shmoopy:BAAANQADCgcIEwAAAA==.Shradehn:BAAANQAECgcJDgAAAA==.Shutitdown:BAAANQADCggIFQAAAA==.',
Si='Sisterswede:BAABNQAECoEaAAITAAkKXxpKCwDzAgATAAkKXxpKCwDzAgAAAA==.Sizzle:BAAANQAECgYJCgAAAA==.',
Sm='Smokeahontas:BAAANQAECgQIBAAAAA==.Smokindots:BAAANQAECgUJBQABNQAECgkJHwAOAJUiAA==.Smokingreen:BAAANQADCggJCAABNQAECgkJHwAOAJUiAA==.Smokinmyrrh:BAAANQADCggJDgABNQAECgkJHwAOAJUiAA==.Smokintotem:BAABNQAECoEfAAMOAAkKlSLkBACCAwAOAAkKlSLkBACCAwAUAAUKrRQCawBTAQAAAA==.',
Sn='Snawkin:BAAANQADCgEIAQAAAA==.',
Sp='Spaghet:BAEANQAECgIIAwABNQAFFAMIBQACAG8UAA==.Sparklnmagic:BAAANQABCgYJCQAAAA==.Spore:BAAANQADCgIIAgAAAA==.',
Sq='Squigboogalo:BAAANQADCgEIAQAAAA==.',
St='Steadyrock:BAAANQAECgcJEAAAAA==.Stemi:BAAANQADCgcJBwAAAA==.Steveirwin:BAAANQADCggJCAAAAA==.Stiffsheets:BAAANQADCgYJBgABNQAECgUJDgADAAAAAA==.Stiltz:BAAANQADCgEIAQAAAA==.Stormywind:BAAANQAECgQIBAAAAA==.Stormz:BAAANQAECgcIEQAAAA==.',
Su='Sunblade:BAAANQAECgMIAwABNQAECgcIFwALAHYIAA==.Sundowning:BAAANQAECgUIBQAAAA==.Supercappy:BAAANQAECgEIAQAAAA==.Suraegi:BAAANQAECgIIAgAAAA==.',
Sw='Swiftdragon:BAAANQAECgUJDgAAAA==.',
Ta='Taapfer:BAAANQAECgMIAwABNQAECgcIEQADAAAAAA==.Tackyh:BAAANQAECgUIDwAAAA==.Takamatsu:BAAANQAECgYJDwAAAA==.Taku:BAAANQAECgIIAgAAAA==.Tar:BAAANQAECgQJCAAAAA==.Taxii:BAAANQAECgcIEAAAAA==.',
Te='Tealnujabes:BAAANQAECgYIBgAAAA==.Tenpiece:BAAANQADCgMIAwAAAA==.',
Th='Thedeus:BAAANQAECgUICQABNQAECggJGQAKAIscAA==.Thellira:BAAANQADCgEIAQAAAA==.Thermaul:BAABNQAECoEYAAIaAAkKnBFVCQCKAgAaAAkKnBFVCQCKAgAAAA==.Threebeans:BAAANQAECgYJCgABNQAECgYJEAADAAAAAA==.Thromir:BAABNQAECoEVAAMbAAkKEh9jCgBCAwAbAAkKEh9jCgBCAwAKAAUKJSPhWAD2AQAAAA==.Thyrn:BAAANQAECgYJEgAAAA==.',
Ti='Tirare:BAAANQAECgUJCgAAAA==.',
Tr='Tri:BAAANQAECgMJBgAAAA==.Tristam:BAAANQAECgEIAQAAAA==.',
Tu='Tulzsyncha:BAAANQADCgYIBgABNQAECggIGAAOADkeAA==.Tuneleitor:BAAANQAECgMIBwAAAA==.Turgrok:BAAANQAECgUJCgAAAA==.',
Tw='Twothang:BAAANQAECgUIDAAAAA==.',
Ty='Tyllan:BAAANQAECgcIDgAAAA==.',
['Tâ']='Tâku:BAAANQADCggJEgAAAA==.',
Va='Vainhellsing:BAAANQADCggJGwAAAA==.Vanzier:BAAANQAECgQICQAAAA==.Vaxis:BAAANQAECgcJEAAAAA==.',
Vi='Vid:BAABNQAECoEeAAIcAAkKHyAWBAAwAwAcAAkKHyAWBAAwAwAAAA==.',
Wa='Watooie:BAAANQADCgYIBgAAAA==.',
We='Weave:BAAANQABCgIIAgABNQAECggIJQAQAPMdAA==.Wernov:BAAANQAECgcIEgABNQAECgcIGwARACIaAA==.',
Wh='Whitetail:BAAANQADCgEJAQAAAA==.',
Wi='Wichan:BAAANQAECgcIEAAAAA==.Wildstrike:BAAANQADCgYIBgABNQAECgYJDgADAAAAAA==.Wiziviji:BAAANQAECgYICQAAAA==.',
Wo='Woodrow:BAAANQADCgcIBwAAAA==.',
Xa='Xanorea:BAAANQADCgYIBgABNQAECgQIBgADAAAAAA==.',
Xd='Xdknight:BAAANQABCgIIAwAAAA==.',
Xe='Xerø:BAAANQAECgUIBwAAAA==.',
Xr='Xray:BAAANQAECgUIEQAAAA==.',
Xt='Xtra:BAAANQAECgMIAwAAAA==.Xtreme:BAAANQADCggIDQAAAA==.',
Ya='Yamii:BAAANQAECgEIAQABNQAECgcIEQADAAAAAA==.Yaphetkotto:BAAANQADCgcJCAAAAA==.',
Yu='Yunsky:BAAANQADCggJGwAAAA==.',
Za='Zanber:BAAANQADCgIIAgAAAA==.Zandrakar:BAAANQAECgYJEwAAAA==.Zanosuke:BAAANQAECggIEQAAAA==.Zaria:BAAANQAECgUIEAAAAA==.Zaryor:BAAANQAECgYJDwAAAA==.Zaun:BAAANQAECgUIBQAAAA==.',
Ze='Zentul:BAAANQAECgQIBAAAAA==.Zerika:BAABNQAECoEYAAIRAAgKlyB5FQDVAgARAAgKlyB5FQDVAgAAAA==.',
Zh='Zhaohu:BAAANQADCgYIBgAAAA==.',
Zi='Zigzwag:BAAANQAECgIIBAAAAA==.Zionna:BAAANQAECgUJDgABNQAECgUJDgADAAAAAA==.',
Zo='Zomgqq:BAAANQAECgcIDAAAAA==.',
Zy='Zydis:BAAANQADCggIEgAAAA==.Zyggy:BAAANQADCggIEgAAAA==.Zynfanatic:BAAANQAECgEIAQAAAA==.',
['Än']='Ännihilation:BAAANQAECgIJAgAAAA==.',
['Èe']='Èepy:BAAANQAECgEJAQABNQAECgUIBQADAAAAAA==.',
['És']='Éstéla:BAABNQAECoEXAAIBAAgKDBLgTwACAgABAAgKDBLgTwACAgAAAA==.',
['Ío']='Ío:BAAANQAECgEIAQAAAA==.',
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
