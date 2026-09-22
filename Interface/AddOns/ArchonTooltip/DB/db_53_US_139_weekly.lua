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

local lookup = {'Priest-Holy','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Shaman-Restoration','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Unholy','Druid-Balance','Druid-Guardian','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Mistweaver','Warrior-Arms','Monk-Windwalker','Priest-Discipline','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Protection','DeathKnight-Frost','Mage-Frost','Paladin-Holy','Rogue-Subtlety','Paladin-Retribution','Shaman-Elemental','Druid-Restoration',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acanaline:BAAANQADCgYJBgAAAA==.Achannara:BAAANQAECgYIDwAAAA==.',
Ae='Aeoliana:BAAANQAECgQIBQAAAA==.',
Aj='Ajier:BAABNQAECoEeAAIBAAkKjxdmLwA6AgABAAkKjxdmLwA6AgAAAA==.',
Al='Aleraz:BAABNQAECoEfAAMCAAgKzRvZDgCxAgACAAgKzRvZDgCxAgABAAgKOwzjTQClAQAAAA==.Allcapwne:BAAANQADCggIFwAAAA==.Alucart:BAAANQAECgEIAgAAAA==.',
An='Angela:BAABNQAECoEYAAIBAAgKnR3XGwCqAgABAAgKnR3XGwCqAgAAAA==.Animalchin:BAAANQABCgEJAQABNQAECgcJDgADAAAAAA==.Annadanna:BAAANQAECgQIBgAAAA==.Annalunà:BAAANQAECgIJAgAAAA==.',
Ap='Apeople:BAABNQAECoEeAAIEAAgK2h1zDwCYAgAEAAgK2h1zDwCYAgAAAA==.Apocalýpsè:BAAANQAECgQJBgAAAA==.Applebottum:BAAANQAECgIJAgAAAA==.Applebottumj:BAAANQADCgIIAgAAAA==.Appärition:BAAANQAECgUJCwAAAA==.',
Ar='Arondael:BAAANQAECgUJBgAAAA==.',
As='Ashelaandrii:BAABNQAECoEgAAIFAAkKLyO0BgBnAwAFAAkKLyO0BgBnAwAAAA==.Astryd:BAAANQAECgYICAAAAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAAANQAECgUICwAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgEJAQAAAA==.Bagmaster:BAABNQAECoEeAAIBAAgKCCbGBQBsAwABAAgKCCbGBQBsAwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAAANQAECgYJDgAAAA==.Barthallomew:BAAANQAECgEJAQABNQAECgQICgADAAAAAA==.Bayonetta:BAAANQAECgMJBAAAAA==.',
Be='Bellann:BAAANQADCggJDQAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQAECgIIAwAAAA==.',
Bl='Blackdracula:BAAANQADCgcJFAAAAA==.Blasphemar:BAAANQABCggICAAAAA==.Blazefury:BAAANQADCggJGwAAAA==.Blazeknight:BAAANQAECgcJCwAAAA==.Blazemaker:BAAANQAECgMIAwAAAA==.Blazemaster:BAAANQADCggIIgAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.',
Bo='Bonecrushers:BAAANQAECgMIBQAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAAANQAECgUIBQABNQAECgYICgADAAAAAA==.Books:BAAANQAECgYICgAAAA==.',
Br='Brainbread:BAAANQAECgQJCAAAAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQADCggIHQAAAA==.Broadside:BAAANQADCgUIBQAAAA==.Brokil:BAAANQAECgEJAQAAAA==.Brolymorph:BAABNQAECoEaAAIGAAkKhho1OwDaAgAGAAkKhho1OwDaAgAAAA==.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQAECgEIAQAAAA==.Bru:BAAANQAECgYICgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAAANQAECgUICQAAAA==.Burninglight:BAAANQADCgYJBgAAAA==.Burningtree:BAAANQAECgEIAQAAAA==.Buthunter:BAAANQAECgIIAwAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECggJJAAHABMdAA==.',
Ca='Camamoonmana:BAAANQAECgcIDAAAAA==.Caplevi:BAAANQAECgQJBAAAAA==.Caskket:BAAANQADCgMIAwAAAA==.Catdog:BAAANQADCgYJBgAAAA==.Catechism:BAAANQAECgEIAgAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAABNQAECoEeAAIIAAgK5SKQCgAZAwAIAAgK5SKQCgAZAwAAAA==.',
Ch='Chaningtotèm:BAAANQADCgUIBQAAAA==.Chickennuggi:BAAANQADCgQJBwABNQAECgkJIwAJAJshAA==.Chiphoof:BAAANQAECgEJAgAAAA==.Chopndot:BAAANQAECgQJBwAAAA==.',
Cl='Clarabuns:BAAANQAECgcIDwAAAA==.Clawdragoon:BAEBNQAECoEgAAMKAAgK0h3UGwCUAgAKAAgK0h3UGwCUAgALAAUKGQRLIgCrAAAAAA==.',
Co='Corine:BAAANQADCgEIAQAAAA==.Corndogmatt:BAAANQADCgIJAgAAAA==.',
Cr='Creatlach:BAABNQAECoEkAAIFAAkKkCJdBwBfAwAFAAkKkCJdBwBfAwAAAA==.Creeptoken:BAAANQADCgQIBQAAAA==.Crystallight:BAAANQAECgIIAgAAAA==.',
Cy='Cytherea:BAAANQAECgcJCQAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgQJCAADAAAAAA==.Dalinek:BAAANQAECgYJCQAAAA==.Danicarkel:BAABNQAECoEeAAQMAAgKbxpOAgClAgAMAAgKbxpOAgClAgANAAQKUg4NLgDtAAAOAAIKtQln0ABoAAAAAA==.Darkdlord:BAAANQAECgQJBAABNQAECgQIBQADAAAAAA==.',
Dd='Ddpaladini:BAAANQAECgQIBQAAAA==.',
De='Deathtracker:BAAANQAECgQJBgAAAA==.Demise:BAACNQAFFIEJAAIGAAYKWgv+BgDmAQAGAAYKWgv+BgDmAQA1AAQKgSUAAgYACQqdHXA4AOMCAAYACQqdHXA4AOMCAAAA.Demontickler:BAAANQADCggIDQABNQAECgYJEAADAAAAAA==.',
Di='Dianabol:BAAANQADCgIIAgABNQAECggIEwADAAAAAA==.Diego:BAAANQADCgYIDAABNQADCggICAADAAAAAA==.Dirkuatah:BAAANQAECgIIAgAAAA==.Dista:BAAANQAECgUIEAAAAA==.Divinebovine:BAAANQAECgEJAQAAAA==.Divinedragon:BAAANQAECgUICwAAAA==.',
Do='Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Drakin:BAAANQAECgcJDAAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAABNQAECoEZAAIFAAgKZw2HUACmAQAFAAgKZw2HUACmAQAAAA==.Drinkoolaide:BAAANQADCgIIAgABNQAECggJGQAFAGcNAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAABNQAECoEUAAIGAAcKfREjlwDeAQAGAAcKfREjlwDeAQAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgMIBAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFIEGAAMPAAQKbBDMCAA1AQAPAAQKiQ7MCAA1AQAQAAEKvhu/GQBYAAA1AAQKgSQAAxAACQpHJlkEAKADABAACQpHJlkEAKADAA8ACQpDHJ8OAL4CAAAA.',
El='Eldrene:BAAANQAECgUICQAAAA==.Elyseia:BAAANQAECgUICwAAAA==.',
En='Enpower:BAAANQADCgYICwABNQAECgkJGwARAIUYAA==.',
Es='Escata:BAAANQADCgYJCgAAAA==.Españamor:BAEANQAECgcIEAAAAA==.',
Eu='Eunite:BAABNQAECoEkAAIJAAgK2RVbJgAxAgAJAAgK2RVbJgAxAgAAAA==.',
Fa='Falkorne:BAAANQAECgMIBAABNQAECggIHAARAP4YAA==.Farael:BAAANQABCgQIBgAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felorc:BAAANQAECgQIBwAAAA==.',
Fi='Fintan:BAAANQADCggICAABNQAECgkJJAAFAJAiAA==.',
Fo='Forsakenemp:BAAANQADCgEIAQABNQAECgQIBQADAAAAAA==.',
Fr='Frassk:BAAANQAECgUICAAAAA==.Froggystyle:BAAANQAECgQJCAAAAA==.Frozenheart:BAAANQAECgQICQAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgIIBAADAAAAAA==.',
Ft='Ftx:BAABNQAECoEcAAISAAgKTBtTOACFAgASAAgKTBtTOACFAgAAAA==.',
Fu='Fundidos:BAAANQADCggICAAAAA==.',
Ga='Garbarn:BAAANQADCgcJDQAAAA==.',
Ge='Geminichi:BAABNQAECoEbAAMRAAkKhRjNBwDGAgARAAkKhRjNBwDGAgATAAEKhRBtRAA9AAAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.',
Gi='Gia:BAAANQAECgUJCwAAAA==.Giraffage:BAAANQAECgYIDQABNQADCggICAADAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAABNQAECoEbAAIQAAgKNxtyLACCAgAQAAgKNxtyLACCAgAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grís:BAAANQAECgcJDwAAAA==.',
Ha='Hazed:BAAANQAECgMIAwAAAA==.',
He='Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Ho='Holier:BAAANQAECgYIEwAAAA==.Holybishh:BAAANQADCgYICwAAAA==.Holyregerts:BAAANQAECgcJDQAAAA==.Honk:BAAANQAECgQJCAAAAA==.Hoochurcooch:BAAANQADCgcJBwAAAA==.Hopperstotem:BAAANQADCgcICgAAAA==.Horsebiter:BAAANQAECggICQAAAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQADCgYIDwAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
In='Infamus:BAAANQAECgIJAwAAAA==.Invysion:BAABNQAECoEfAAIUAAkKkAVBBwCoAQAUAAkKkAVBBwCoAQAAAA==.',
Ja='Jackychang:BAAANQADCgUICgAAAA==.Jaidess:BAAANQADCggICAAAAA==.Jakeypoo:BAAANQADCgYIDAAAAA==.',
Je='Jellybea:BAAANQAECgYICgAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQADCggJDgAAAA==.Jurisdiction:BAAANQAECgEIAgAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAAANQAECgcIEQAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kasey:BAAANQAECgUIDwAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAAANQAECgEIAgAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAABNQAECoEnAAMVAAkKnB/wCwDzAgAVAAkKTx7wCwDzAgAIAAkKlxmrEQC5AgABNQADCggICAADAAAAAA==.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kilgreed:BAAANQADCgUICAAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAAANQAECgIIAwAAAA==.Kimberlyhárt:BAAANQAECgYJEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYJEAADAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECoEeAAIOAAgKhg9nVQDNAQAOAAgKhg9nVQDNAQAAAA==.',
Ko='Kohman:BAABNQAECoEdAAMOAAkKNBLfQwANAgAOAAgK9RDfQwANAgANAAMKMg0SQwCUAAAAAA==.',
Kr='Krftpnk:BAACNQAFFIENAAIIAAYKNSHSAABvAgAIAAYKNSHSAABvAgA1AAQKgSkAAggACQr4JewAAOYDAAgACQr4JewAAOYDAAAA.Kronas:BAAANQAECgQJBQAAAA==.Kronosity:BAAANQAECgUIBwABNQAECggIHgAWAE4gAA==.Kronotality:BAABNQAECoEeAAIWAAgKTiBPEADnAgAWAAgKTiBPEADnAgAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECggIHgAWAE4gAA==.Kronotide:BAAANQADCgQIBAABNQAECggIHgAWAE4gAA==.',
Ku='Kungfukittn:BAAANQAECgQJCAAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECgQIBAAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
La='Laimaster:BAAANQADCgcJEQAAAA==.Lakiri:BAAANQAECgUICwAAAA==.Lascivia:BAABNQAECoEYAAIXAAgKsx2YBQCmAgAXAAgKsx2YBQCmAgAAAA==.Laylahh:BAAANQADCgQIBAAAAA==.',
Le='Leademon:BAAANQAECgUICAAAAA==.Leadmln:BAAANQAECgMIAwABNQAECgUICAADAAAAAA==.Lebwonsamdi:BAAANQAECgEIAQABNQAECgcJDwADAAAAAA==.',
Li='Lighterfluîd:BAAANQABCgIIAgABNQAECggIGAARAJkbAA==.Ligmadk:BAAANQADCgUIBQABNQADCggICgADAAAAAA==.Lilflea:BAAANQAECgcJDgAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJIAAWAF8iAA==.Lilzuki:BAAANQAECgEIAQAAAA==.Lilïth:BAABNQAECoEgAAIWAAkKXyLyBQBzAwAWAAkKXyLyBQBzAwAAAA==.Linguine:BAAANQADCggICAABNQAECggJHwACAM0bAA==.Lisalisa:BAAANQAECgQJCAAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECoEcAAIRAAgK/hjLDABGAgARAAgK/hjLDABGAgAAAA==.',
Lo='Logaothe:BAAANQAECgUIBgAAAA==.',
Lu='Lucky:BAAANQAECgEIAQAAAA==.Lunaa:BAAANQAECgQJBAAAAA==.Lusid:BAAANQABCgQIBAAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.',
Me='Medikus:BAAANQAECgQJCAAAAA==.Megajoo:BAAANQAECgEIAQAAAA==.Melianni:BAAANQADCggIGwAAAA==.Melkinov:BAAANQABCgYIBgAAAA==.Merryl:BAAANQAECgUJBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECoEcAAIGAAkKMiKvIAA0AwAGAAkKMiKvIAA0AwAAAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAABNQAECoEgAAIGAAgKrBI0egAmAgAGAAgKrBI0egAmAgAAAA==.Montera:BAEANQAECgQJBgABNQAECgcIEAADAAAAAA==.Moohammered:BAAANQADCggIDgAAAA==.Moolou:BAAANQAECgcIDwAAAA==.Mordiggian:BAAANQAFFAEIAQAAAA==.Morechie:BAAANQAECgUICQAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgEJAQAAAA==.Mortiferon:BAABNQAECoEYAAIJAAgKPxlCHwBqAgAJAAgKPxlCHwBqAgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgEJAgADAAAAAA==.Munnkypox:BAAANQAECgEJAgAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.',
Ne='Nealite:BAAANQABCgQIBwAAAA==.Neerem:BAAANQABCgYIAwAAAA==.Neferata:BAAANQAECgcJEQAAAA==.Nertmage:BAABNQAECoEkAAMHAAgKEx26AADKAgAHAAgKEx26AADKAgAGAAEKsxD1VwFJAAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQADCgcJGAAAAA==.Nineiota:BAAANQAECgQJCAAAAA==.',
No='Noblewarrior:BAACNQAFFIEPAAISAAUKRBJ8CQBsAQASAAUKRBJ8CQBsAQA1AAQKgSQAAhIACQrqIdMNAGwDABIACQrqIdMNAGwDAAAA.Noctilus:BAAANQADCgcIDwAAAA==.Noke:BAAANQAECgIJAgAAAA==.Notakoala:BAABNQAECoEeAAIKAAkKbxx5EwDpAgAKAAkKbxx5EwDpAgAAAA==.Nothnx:BAAANQAECgcICgAAAA==.Notoriouspat:BAAANQADCggJDgAAAA==.Novia:BAAANQADCggJEgABNQAECgcJDwADAAAAAA==.Noxeternis:BAABNQAECoEZAAMCAAgKnBnOEgBzAgACAAgKnBnOEgBzAgAUAAIKMgaXFwBTAAAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgIIAgAAAA==.Nínebreaker:BAAANQADCggICgAAAA==.',
Ob='Obern:BAAANQAECgcJDAAAAA==.Oblïna:BAAANQAECgEIAgAAAA==.',
Od='Oddishh:BAAANQAECgUIBQAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcJDAAAAA==.',
On='Onsen:BAAANQAECgQJBwAAAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Pa='Pajl:BAAANQAECgUICgABNQAECgkJGgAYACsiAA==.Pandablaze:BAAANQADCggJHQAAAA==.Pandajoy:BAAANQADCgEJAQAAAA==.Panterarey:BAAANQADCgUJCAAAAA==.Papanurrgle:BAAANQAECgQIBAAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECgIIAgAAAA==.Pawp:BAAANQAECgQIBwABNQAECgkJHwABAJQQAA==.Paxiel:BAAANQAECgQIBgAAAA==.',
Pe='Pearagon:BAAANQADCgQIBAABNQAFFAMIBQAFAHoYAA==.Pepsidew:BAAANQAECgMIAwAAAA==.Pepsisprite:BAAANQAECgUIBQAAAA==.',
Ph='Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQADCggIFQAAAA==.',
Pi='Picklez:BAAANQAECgMJBAAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.',
Ps='Psyop:BAAANQADCgYIDAABNQAECgkJHQABAM8fAA==.Psyrax:BAAANQADCgUJBwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgEIAQABNQAECgkJHgAKAG8cAA==.Repete:BAAANQAECgIJAwAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECoEkAAIZAAgKjh7UAgDDAgAZAAgKjh7UAgDDAgAAAA==.Reven:BAAANQAECgUICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ro='Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAAANQAECgQJCAAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.',
['Rõ']='Rõx:BAABNQAECoEkAAIaAAgKOBqZJQB3AgAaAAgKOBqZJQB3AgAAAA==.',
Sa='Sackoss:BAAANQAECgMIBAAAAA==.Saffronspark:BAAANQAECgMIAwABNQAECgYJEQADAAAAAA==.Sainsei:BAAANQAECgQJBQABNQAECgcJDwADAAAAAA==.Sandwitch:BAABNQAECoEkAAINAAgK4Q3iDwDjAQANAAgK4Q3iDwDjAQAAAA==.Sargatanas:BAAANQAECgcIDwAAAA==.Sars:BAAANQADCgUIBQABNQAECgIJAgADAAAAAA==.',
Sc='Schrodinger:BAAANQAECgEIAgAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAAANQAECgUICQAAAA==.',
Sh='Shadrad:BAAANQAECgcIDAAAAA==.Shallot:BAABNQAECoEZAAIGAAgKpRzqRAC8AgAGAAgKpRzqRAC8AgAAAA==.Shammoo:BAAANQAECgIJAgAAAA==.Shantz:BAAANQAECgUJCgAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAAANQADCgUIBQAAAA==.',
Sk='Skatervan:BAAANQADCggJEwABNQAECggJGAACAGcRAA==.Skylie:BAAANQADCgUJCQAAAA==.',
Sm='Smorthian:BAAANQADCgcJEwAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQADCgMIAwAAAA==.',
So='Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAAANQAECgUICwAAAA==.Sparkyy:BAAANQAECgIIAgAAAA==.Sphaeram:BAAANQAECgUIBQAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAAANQAECgUJDQAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQADCggIFQADAAAAAA==.Stinkydragon:BAAANQADCggIFQAAAA==.Stormknight:BAAANQADCggJGwAAAA==.',
Su='Superpi:BAAANQADCgYIBgABNQAECgUICAADAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQAECgMJAwAAAA==.',
Sw='Swíper:BAABNQAECoEXAAMEAAkKOB4jBgAtAwAEAAkKOB4jBgAtAwAbAAUKLgv0KgAMAQAAAA==.',
Sy='Sylphièl:BAABNQAECoEZAAMEAAkKTg3yIADUAQAEAAkK6wfyIADUAQAbAAYKmw0MIQB+AQAAAA==.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgYIBgAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECoEaAAIcAAkKOiEIHAACAwAcAAkKOiEIHAACAwAAAA==.Tankenstine:BAAANQAECgUJBwABNQAECgUICwADAAAAAA==.Tawnii:BAAANQAECgEIAQAAAA==.Taírn:BAAANQADCgUIBgAAAA==.',
Te='Tenderloin:BAAANQAECgEIAgAAAA==.',
Th='Thanitose:BAAANQAECgEJAQAAAA==.Thevelo:BAAANQADCggIEAABNQAECgEIAgADAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAABNQAECoElAAIdAAkKyhIZLwBPAgAdAAkKyhIZLwBPAgAAAA==.',
Ti='Timmayy:BAAANQAECgIIAgABNQAECggIHAARAP4YAA==.Tindrill:BAAANQADCgMJAwABNQAECggJGAAeAD0hAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAAANQAECgUICQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAYJDQAIADUhAA==.Totemagoat:BAABNQAECoEfAAMFAAkKahoIGQDCAgAFAAkKahoIGQDCAgAdAAcK3xZBRADjAQAAAA==.',
Tr='Treefist:BAAANQADCgMIAwAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAABNQAECoEaAAIeAAkKJg/2FAAeAgAeAAkKJg/2FAAeAgAAAA==.',
Un='Undeadmonks:BAAANQADCgYIBgAAAA==.',
Va='Vagalion:BAAANQADCgUIBQAAAA==.Vale:BAAANQADCgYICgAAAA==.Valeshot:BAABNQAECoEYAAIQAAgKYQy0VQDvAQAQAAgKYQy0VQDvAQAAAA==.Valimyr:BAAANQABCgMIBAABNQABCgUIBQADAAAAAA==.Valthyrion:BAAANQADCggIGwAAAA==.Vanhellsin:BAAANQAECgQJBwAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgAcAPoiAA==.Vedronas:BAABNQAECoEWAAIcAAkK+iIKCgCHAwAcAAkK+iIKCgCHAwAAAA==.Veos:BAABNQAECoEXAAIZAAgKDRxyAwCeAgAZAAgKDRxyAwCeAgAAAA==.Verdict:BAAANQADCgYJBgAAAA==.Vern:BAAANQAECgQIBAAAAA==.Vernah:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Vorn:BAABNQAECoEkAAIWAAgKUhZXKAAWAgAWAAgKUhZXKAAWAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAAANQAECgUICAAAAA==.Waamchifu:BAAANQAECgEJAQAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgEIAQAAAA==.Whoforted:BAAANQAECgYJCwAAAA==.',
Wo='Wormchild:BAAANQABCgUIBQAAAA==.',
Wu='Wulrat:BAAANQAECgYICAAAAA==.',
Wy='Wyle:BAAANQADCgcIDwAAAA==.',
Xe='Xelí:BAABNQAECoEiAAIFAAgK7RVkMgAtAgAFAAgK7RVkMgAtAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAAANQAECgYICwABNQAECgkJJAAFAJAiAA==.',
Xt='Xtremes:BAAANQADCggICwABNQAECgkJGwARAIUYAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.',
Yu='Yudah:BAAANQAECgEIAQAAAA==.',
Za='Zanghonghua:BAAANQAECgYJEQAAAA==.',
Ze='Zemy:BAABNQAECoEYAAMKAAkKryUNBQCYAwAKAAkKryUNBQCYAwALAAcK6xhwDADXAQAAAA==.Zeneca:BAAANQAECgEIAQABNQAECggJHwACAM0bAA==.',
Zo='Zodstrike:BAAANQAECgQICAAAAA==.Zooboo:BAAANQAECgQIBwAAAA==.',
Zu='Zugzuggler:BAAANQAECgYJDgAAAA==.',
Zy='Zyrick:BAAANQABCgcICAAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgQICgADAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgIIBQABNQAECgQICgADAAAAAA==.',
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
