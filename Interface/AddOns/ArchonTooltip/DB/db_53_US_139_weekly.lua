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

local lookup = {'Paladin-Retribution','Priest-Holy','Unknown-Unknown','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','DeathKnight-Blood','Mage-Arcane','DemonHunter-Havoc','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Paladin-Holy','Druid-Balance','Druid-Guardian','Warlock-Affliction','Priest-Shadow','Priest-Discipline','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Mistweaver','Warrior-Arms','Monk-Windwalker','Warrior-Protection','DemonHunter-Devourer','Paladin-Protection','Shaman-Enhancement','Warrior-Fury','Rogue-Subtlety','Shaman-Elemental','Druid-Restoration',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absolutepast:BAAANQABCgQIBAAAAA==.',
Ac='Acanaline:BAAANQADCgYJBgAAAA==.Achannara:BAABNQAECoEhAAIBAAgKYwTd1QA1AQABAAgKYwTd1QA1AQAAAA==.',
Ae='Aeoliana:BAAANQAECgcIEAAAAA==.',
Aj='Ajier:BAACNQAFFIEFAAICAAMKvgxjGQDuAAACAAMKvgxjGQDuAAA1AAQKgSMAAgIACQrqF+JIACQCAAIACQrqF+JIACQCAAAA.',
Al='Allcapwne:BAAANQADCggIIAAAAA==.Alucart:BAAANQAECgQICAAAAA==.',
An='Angela:BAABNQAECoEjAAICAAgKvB3lLQCRAgACAAgKvB3lLQCRAgAAAA==.Animalchin:BAAANQABCgEJAQABNQAECgcIEQADAAAAAA==.Annadanna:BAAANQAECgUICwAAAA==.Annalunà:BAAANQAECgMIBQAAAA==.Antithicus:BAAANQADCgYIBgAAAA==.',
Ap='Apeople:BAABNQAECoEpAAIEAAgKWB90FgCjAgAEAAgKWB90FgCjAgAAAA==.Apocalýpsè:BAAANQAECgQICgAAAA==.Applebottum:BAAANQAECgUICQAAAA==.Applebottumj:BAAANQADCgIIAgAAAA==.Appärition:BAABNQAECoEbAAMFAAcKjB3pEADoAQAGAAcKxhgPYgAQAgAFAAYKdxrpEADoAQAAAA==.',
Ar='Arondael:BAAANQAECgYIEgAAAA==.',
As='Ashelaandrii:BAACNQAFFIEFAAIHAAIKpiAPFwC5AAAHAAIKpiAPFwC5AAA1AAQKgSMAAgcACQo2IzsMAEoDAAcACQo2IzsMAEoDAAAA.Astroglyde:BAAANQADCgYIBgAAAA==.Astryd:BAAANQAECgcIEQABNQAECgcIFwAIADcFAA==.Asunayu:BAAANQADCgMIAwAAAA==.',
Av='Avanti:BAABNQAECoEdAAIJAAcKZQoW6wCNAQAJAAcKZQoW6wCNAQAAAA==.',
Az='Azrael:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùvina:BAAANQADCgIJAgAAAA==.',
Ba='Badru:BAAANQAECgIIAwAAAA==.Bagmaster:BAABNQAECoEqAAICAAkKkyKsBACZAwACAAkKkyKsBACZAwAAAA==.Bahm:BAAANQADCgIIAgAAAA==.Ballocks:BAAANQAECgcIEwAAAA==.Barthallomew:BAAANQAECgEIAQABNQAECgQICgADAAAAAA==.Bayonetta:BAAANQAECgcIEAAAAA==.',
Be='Bellann:BAAANQAECgEIAQAAAA==.',
Bi='Birghid:BAAANQABCgIIAgAAAA==.Birgite:BAAANQAECgQIBwAAAA==.',
Bl='Blackdracula:BAAANQAECgMIAwAAAA==.Blasphemar:BAAANQABCggIDgAAAA==.Blazefury:BAAANQAECgMIAwAAAA==.Blazeknight:BAABNQAECoEbAAIKAAgKkRdbKgAjAgAKAAgKkRdbKgAjAgAAAA==.Blazemaker:BAABNQAECoEYAAILAAgKvRdaCAAtAgALAAgKvRdaCAAtAgAAAA==.Blazemaster:BAAANQADCggILgAAAA==.Blinktzy:BAAANQADCggIDQAAAA==.Bloodsylf:BAAANQADCgYIBgABNQAECgUIBgADAAAAAA==.',
Bo='Bonecrushers:BAAANQAECgQIDAAAAA==.Boohah:BAAANQADCgYICwAAAA==.Bookend:BAAANQAECgcIDAAAAA==.Books:BAAANQAECgcIDgABNQAECgcIDAADAAAAAA==.',
Br='Brainbread:BAAANQAECgQIDAABNQAECgkJLAAGAAUYAA==.Braski:BAAANQADCgYIBgAAAA==.Brink:BAAANQAECgQIBQAAAA==.Broadside:BAAANQAECgEIAQAAAA==.Brokil:BAAANQAECgEIAQAAAA==.Brolymorph:BAABNQAECoEgAAIJAAkKGBxDUwDJAgAJAAkKGBxDUwDJAgAAAA==.Brossiere:BAAANQADCgQIBAAAAA==.Broverheal:BAAANQAECgMIBQAAAA==.Bru:BAAANQAECggIEgAAAA==.',
Bt='Bt:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleoseven:BAAANQABCgIIAgAAAA==.Bullsmcgee:BAABNQAECoEZAAMMAAgK4RqhLwBOAgAMAAgK4RqhLwBOAgANAAIKOha1dgCDAAAAAA==.Burninglight:BAAANQADCgYIDAAAAA==.Burningtree:BAAANQAECgQIBQAAAA==.Buthunter:BAAANQAECgQIBwAAAA==.',
['Bâ']='Bâhtilâ:BAAANQAECgYIAQAAAA==.',
['Bê']='Bêarcub:BAAANQADCgUIBQABNQAECggIRAAOAP8iAA==.',
Ca='Camamoonmana:BAAANQAECgcIDQAAAA==.Caplevi:BAAANQAECgcIEQAAAA==.Carrìon:BAAANQADCgEIAQAAAA==.Caskket:BAAANQAECgQIBAAAAA==.Catdog:BAAANQADCgYJBgAAAA==.Catechism:BAAANQAECgQICAAAAA==.',
Ce='Cemeo:BAAANQADCgYICgAAAA==.Cerberusalfa:BAABNQAECoEpAAIKAAgK6CLQEgDqAgAKAAgK6CLQEgDqAgAAAA==.',
Ch='Chaningtotèm:BAAANQADCgUICgAAAA==.Charan:BAAANQADCgQIBAAAAA==.Chickennuggi:BAAANQADCgQJBwABNQAFFAMIBgAMALMjAA==.Chiphoof:BAAANQAECgQICAAAAA==.Chopndot:BAAANQAECgUIDAAAAA==.',
Cl='Clarabuns:BAABNQAECoEWAAMPAAkKmRp9OABmAgAPAAgKphl9OABmAgABAAIKaRBXQgFyAAAAAA==.Clawdragoon:BAEBNQAECoEmAAMQAAkKkhw8HwC0AgAQAAkKkhw8HwC0AgARAAYKyAWuLwDVAAAAAA==.',
Co='Corine:BAAANQADCgEIAQAAAA==.Corndogmatt:BAAANQADCgUICAAAAA==.',
Cr='Creatlach:BAACNQAFFIEOAAIHAAUKChUlCQCdAQAHAAUKChUlCQCdAQA1AAQKgSwAAgcACQoCI7YKAFcDAAcACQoCI7YKAFcDAAAA.Creeptoken:BAAANQADCgQIBQAAAA==.Crystallight:BAAANQAECgYICAAAAA==.',
Cy='Cyraxx:BAAANQADCgYIBgAAAA==.Cytherea:BAAANQAECggIEAAAAA==.',
Da='Daddybod:BAAANQADCgEIAQABNQAECgUIDgADAAAAAA==.Dalinek:BAAANQAECgcIDwAAAA==.Dandelo:BAAANQADCgYICgAAAA==.Danicarkel:BAABNQAECoEpAAQSAAgKix0hAwC1AgASAAgKLB0hAwC1AgAFAAQK9xDhLwD+AAAGAAIKtQk/EAFkAAAAAA==.Darkdlord:BAAANQAECgYICgABNQAECgcIEQADAAAAAA==.',
Dd='Ddpaladini:BAAANQAECgcIEQAAAA==.',
De='Deathtracker:BAAANQAECgYIEQAAAA==.Deathtrops:BAAANQAECgIIAgABNQAFFAYIFAAGACEfAA==.Demindan:BAAANQABCgMIAwAAAA==.Demise:BAACNQAFFIETAAIJAAYK2BM0DAD2AQAJAAYK2BM0DAD2AQA1AAQKgTUAAwkACQqQINk4AAkDAAkACQqQINk4AAkDAAsAAQr3G1k0AFMAAAAA.Demontickler:BAAANQADCggIDQABNQAECgYJEAADAAAAAA==.',
Di='Dianabol:BAAANQAECgYICAABNQAECgkJIAAHAIIkAA==.Diego:BAAANQADCgYIDAABNQADCggIEAADAAAAAA==.Dirkuatah:BAAANQAECgMIAgAAAA==.Dista:BAABNQAECoEiAAIGAAkKJRixMwCgAgAGAAkKJRixMwCgAgAAAA==.Divinebovine:BAAANQAECgEIAQAAAA==.Divinedragon:BAABNQAECoEeAAMTAAgKaxmpKQCzAQATAAYKaxipKQCzAQAUAAMKyRdYEgDoAAAAAA==.',
Do='Doboy:BAAANQAECgEIAQAAAA==.Doublevegan:BAAANQADCgMJAwAAAA==.',
Dr='Drakin:BAAANQAECgcIEAAAAA==.Drawbridge:BAAANQADCgQIBAAAAA==.Dreya:BAAANQADCgMIAwAAAA==.Drinkcoolaid:BAABNQAECoEqAAIHAAkKIhQaQwApAgAHAAkKIhQaQwApAgAAAA==.Drinkoolaide:BAAANQADCgIIAgABNQAECgkJKgAHACIUAA==.Drybooger:BAAANQABCgQIBQAAAA==.',
Du='Dumb:BAAANQADCgYIBgAAAA==.Dunamis:BAABNQAECoEXAAIJAAcKsBNMswD6AQAJAAcKsBNMswD6AQAAAA==.Dungodon:BAAANQADCggIDgAAAA==.Durrt:BAAANQAECgQICAAAAA==.Dustyolbones:BAAANQADCgcICQAAAA==.Dutchman:BAACNQAFFIEMAAMVAAUKiBFOCwBjAQAVAAUKSw9OCwBjAQAWAAIKuxLQHwCeAAA1AAQKgSoAAxYACQpHJswKAHUDABYACQpHJswKAHUDABUACQpDHI8XAIUCAAAA.',
El='Eldrene:BAABNQAECoEaAAIJAAgKuRqocQCEAgAJAAgKuRqocQCEAgAAAA==.Elizalde:BAAANQAECgQIBAAAAA==.Ellexi:BAAANQAECgQIBAAAAA==.Elyseia:BAABNQAECoEYAAIWAAgKaAomfQDkAQAWAAgKaAomfQDkAQAAAA==.',
En='Enpower:BAAANQADCgYICwABNQAECgkJJwAXAEkZAA==.',
Es='Escata:BAAANQADCggIEAAAAA==.Esdailongwe:BAAANQADCgIIAgAAAA==.Españamor:BAEANQAECggIEwAAAA==.',
Eu='Eunite:BAABNQAECoFEAAIMAAgKTx0QLgBXAgAMAAgKTx0QLgBXAgAAAA==.',
Fa='Falkorne:BAAANQAECgMIBAABNQAECggIHgAXAP4YAA==.Farael:BAAANQADCgYIBgAAAA==.Fatalmann:BAAANQAECgIIAgAAAA==.',
Fe='Felorc:BAAANQAECgYIEQABNQAECgcIFwAIADcFAA==.',
Fi='Fintan:BAAANQADCggICAABNQAFFAUIDgAHAAoVAA==.',
Fo='Forsakenemp:BAAANQADCggIDQABNQAECgcIEQADAAAAAA==.',
Fr='Frassk:BAABNQAECoEaAAMGAAgKzA3ghACsAQAGAAcKpg3ghACsAQAFAAEK1g5wbgA7AAAAAA==.Frigid:BAAANQADCgcIBwAAAA==.Froggystyle:BAAANQAECgcIDwAAAA==.Frozenheart:BAABNQAECoEXAAMIAAcKNwVodwD0AAAIAAcKNwVodwD0AAANAAIK0AENlwAvAAAAAA==.Fruk:BAAANQADCgUIBQAAAA==.Frösting:BAAANQADCgYIBgABNQAECgQIBQADAAAAAA==.',
Ft='Ftx:BAABNQAECoEhAAIYAAgKMyCUOgDEAgAYAAgKMyCUOgDEAgAAAA==.',
Fu='Fundidos:BAAANQADCggIEAAAAA==.',
Ga='Garbarn:BAAANQADCgcJDQAAAA==.',
Ge='Geminichi:BAABNQAECoEnAAMXAAkKSRmhDACYAgAXAAkKSRmhDACYAgAZAAEKhRDtXAA5AAAAAA==.',
Gh='Ghauri:BAAANQADCgYJBgAAAA==.Ghorza:BAAANQADCgYIBgAAAA==.',
Gi='Gia:BAABNQAECoEbAAIXAAcKvBWmGQC3AQAXAAcKvBWmGQC3AQAAAA==.Gigasauce:BAAANQAECgEIAQAAAA==.Giraffage:BAAANQAECgYIEwABNQADCggICAADAAAAAA==.',
Go='Golgroth:BAAANQADCgQJBAAAAA==.Gorearrow:BAABNQAECoEmAAIWAAgKjRxzOQCbAgAWAAgKjRxzOQCbAgAAAA==.',
Gr='Griffoo:BAAANQADCgEIAQAAAA==.Groggyfroggy:BAAANQADCgMJAwAAAA==.Grralt:BAAANQAECgIIAgABNQADCggIHAADAAAAAA==.Grís:BAABNQAECoEgAAMYAAgKgBVqawAvAgAYAAgKgBVqawAvAgAaAAEKwAaLPgAmAAAAAA==.',
Ha='Harrier:BAAANQADCgYIBgABNQAECgQICAADAAAAAA==.Hazed:BAAANQAECgcICAAAAA==.Hazzaa:BAAANQAECgUICQAAAA==.',
He='Herioffy:BAAANQADCgEIAQAAAA==.Hexxan:BAAANQADCgYIBgAAAA==.',
Hi='Hiawatha:BAAANQADCgQIBAAAAA==.Hiver:BAAANQAECgEIAQAAAA==.',
Ho='Holier:BAABNQAECoEmAAIBAAgKRA2snwCrAQABAAgKRA2snwCrAQAAAA==.Holybishh:BAAANQAECgUIBQAAAA==.Holyregerts:BAAANQAECggIEgAAAA==.Honk:BAAANQAECgQJCAAAAA==.Hoochurcooch:BAAANQAECgQIBAAAAA==.Hopperstotem:BAAANQAECgMIAwAAAA==.',
Hu='Hurrdurr:BAAANQADCgUIBQAAAA==.',
Ia='Iamanoobnow:BAAANQADCgQIBAAAAA==.',
Ic='Icys:BAAANQAECgIIAgAAAA==.',
Il='Illumi:BAAANQABCgYIBgAAAA==.',
In='Infamus:BAAANQAECgIIBQAAAA==.Invysion:BAACNQAFFIEFAAIUAAMK5QAWAgCiAAAUAAMK5QAWAgCiAAA1AAQKgSoAAhQACQo4EX0FADUCABQACQo4EX0FADUCAAAA.',
Is='Islander:BAAANQAECgQIBwAAAA==.',
Ja='Jackychang:BAAANQAECgQICQAAAA==.Jaidess:BAAANQADCggIDgAAAA==.Jakeypoo:BAAANQAECgQIBwAAAA==.',
Je='Jellybea:BAAANQAECggIEwAAAA==.',
Ju='Jukoti:BAAANQABCgIIBAAAAA==.Junglebrew:BAAANQADCggJDgAAAA==.Junglepino:BAAANQADCgYIBgAAAA==.Jurisdiction:BAAANQAECgQICAAAAA==.',
Ka='Kabea:BAAANQABCgMIAwAAAA==.Kadath:BAAANQADCgEIAQAAAA==.Kaizokuo:BAABNQAECoEmAAIZAAkKGR38CwD/AgAZAAkKGR38CwD/AgAAAA==.Kalypsoe:BAAANQADCgQIBAAAAA==.Kasey:BAAANQAECgUIEwAAAA==.Kazarke:BAAANQADCgUIBQAAAA==.',
Ke='Keenlan:BAAANQADCgMIAwAAAA==.Keho:BAAANQAECgQICAAAAA==.Kerzermern:BAAANQAECgEIAQAAAA==.Kevic:BAACNQAFFIEFAAIKAAMKoQ+6DgDZAAAKAAMKoQ+6DgDZAAA1AAQKgS0AAxsACQoEIPQSALwCABsACQpPHvQSALwCAAoACQo3Gw4dAIwCAAE1AAMKCAgIAAMAAAAA.',
Kh='Khurzgan:BAAANQADCgYIBgAAAA==.',
Ki='Kickdrop:BAAANQADCgQIBAAAAA==.Kilgreed:BAAANQADCgYIDgAAAA==.Killaban:BAAANQAECgcIBwAAAA==.Killbydeath:BAAANQAECgQIBgAAAA==.Kimberlyhárt:BAAANQAECgYJEAAAAA==.Kimdk:BAAANQAECgEIAQABNQAECgYJEAADAAAAAA==.Kimdruid:BAAANQADCgQIBAAAAA==.Kissmydots:BAABNQAECoE+AAIGAAgKGBl0PwB4AgAGAAgKGBl0PwB4AgAAAA==.',
Ko='Kohman:BAABNQAECoEsAAMGAAkKBRiqMwCgAgAGAAkKzBeqMwCgAgAFAAMKMg3JTQCKAAAAAA==.Komatose:BAAANQADCgYIBgAAAA==.Kong:BAAANQADCgIIAwAAAA==.',
Kr='Krftpnk:BAACNQAFFIEZAAIKAAcKRiBbAQCUAgAKAAcKRiBbAQCUAgA1AAQKgS8AAgoACQp3Jk8BAOMDAAoACQp3Jk8BAOMDAAAA.Kronas:BAAANQAECgYICwAAAA==.Kronosity:BAABNQAECoEYAAIcAAgKahtNEAByAgAcAAgKahtNEAByAgABNQAECggILQAIAAskAA==.Kronotality:BAABNQAECoEtAAIIAAgKCyTvCwBEAwAIAAgKCyTvCwBEAwAAAA==.Kronotekken:BAAANQAECgEIAQABNQAECggILQAIAAskAA==.Kronotide:BAAANQADCgQIBAABNQAECggILQAIAAskAA==.',
Ku='Kungfukittn:BAAANQAECgYIEgAAAA==.Kurze:BAAANQAECgIIAwAAAA==.',
Ky='Kylorai:BAAANQAECgQIBgAAAA==.Kyojuro:BAAANQABCgYIBgAAAA==.',
Kz='Kzorx:BAAANQADCgYICgAAAA==.',
La='Laimaster:BAAANQADCgcIHgAAAA==.Lakiri:BAABNQAECoEdAAIdAAcKGRL0FADwAQAdAAcKGRL0FADwAQAAAA==.Lascivia:BAABNQAECoEeAAMaAAgK1h5BCQCNAgAaAAgK1h5BCQCNAgAeAAQKPxfCFQAdAQAAAA==.Latrice:BAAANQAECgUIBQABNQAFFAYIEAALAC8hAA==.Laylahh:BAAANQADCgQIBAAAAA==.',
Le='Leademon:BAAANQAECgYIDgAAAA==.Leadmln:BAAANQAECgMIAwABNQAECgYIDgADAAAAAA==.Lebwonsamdi:BAAANQAECgEIAQABNQAECggIIAAYAIAVAA==.',
Li='Lighterfluîd:BAAANQABCgIIAgABNQAECggIJwAXAPgfAA==.Ligmadk:BAAANQADCgUIBQABNQAECgkJIgAKAEYZAA==.Lilbeebs:BAAANQAECgIIAgAAAA==.Lilflea:BAAANQAECgcIEQAAAA==.Lillidari:BAAANQAECgcICQABNQAECgkJJgAIAOEiAA==.Lilzuki:BAAANQAECgIIAgAAAA==.Lilïth:BAABNQAECoEmAAIIAAkK4SI9CABsAwAIAAkK4SI9CABsAwAAAA==.Linguine:BAAANQADCggICAABNQAECgkJLgATAD4fAA==.Lisalisa:BAAANQAECgYIDgAAAA==.Littlej:BAAANQAECgQJBAAAAA==.Littlejohn:BAABNQAECoEeAAIXAAgK/hhQEwAbAgAXAAgK/hhQEwAbAgAAAA==.',
Lo='Logaothe:BAAANQAECgUIDAAAAA==.',
Lu='Lucky:BAAANQAECgQIBQAAAA==.Lukethywalkr:BAAANQADCgQIBAAAAA==.Lularia:BAAANQADCgUICAAAAA==.Lunaa:BAAANQAECgQJBAAAAA==.Lusid:BAAANQABCgYIBwAAAA==.',
Ma='Magikzy:BAAANQADCgYIBgAAAA==.Maliciousrot:BAAANQADCgYIBgAAAA==.Marnix:BAAANQAECgQIBQAAAA==.',
Me='Medikus:BAAANQAECgUIEgAAAA==.Medina:BAAANQADCgQIBAAAAA==.Megajoo:BAAANQAECgEIAQAAAA==.Melianni:BAAANQADCggIHAAAAA==.Melkinov:BAAANQABCgYIBgAAAA==.Merryl:BAAANQAECgUIBwAAAA==.',
Mf='Mfive:BAAANQAECgQIBAAAAA==.',
Mi='Mike:BAEBNQAECoEcAAIJAAkKMiKTPwD4AgAJAAkKMiKTPwD4AgAAAA==.Minijeangen:BAAANQAECgMJAwAAAA==.Missluana:BAAANQABCgEIAQAAAA==.',
Mo='Mockra:BAABNQAECoFAAAIJAAgKdRaukgA+AgAJAAgKdRaukgA+AgAAAA==.Moistmunnky:BAAANQAECgIIAgABNQAECgIIBAADAAAAAA==.Montera:BAEANQAECgQJBgABNQAECggIEwADAAAAAA==.Moohammered:BAAANQAECgQIBwAAAA==.Moolou:BAABNQAECoEcAAIcAAkK9hkiEAB1AgAcAAkK9hkiEAB1AgAAAA==.Mootarded:BAAANQAECgYICgABNQAECgcIFwAIADcFAA==.Mordiggian:BAABNQAECoEmAAMMAAgK0CTVHwCtAgAMAAgKbSTVHwCtAgAIAAMKHx+zcgAGAQAAAA==.Morechie:BAABNQAECoEaAAISAAgKBA+RCADeAQASAAgKBA+RCADeAQAAAA==.Morgatho:BAAANQABCgcICQAAAA==.Morsz:BAAANQAECgUICAAAAA==.Mortiferon:BAABNQAECoEeAAIMAAgK0hwAMwA8AgAMAAgK0hwAMwA8AgAAAA==.',
Mu='Munnky:BAAANQADCgMIAwABNQAECgIIBAADAAAAAA==.Munnkypox:BAAANQAECgIIBAAAAA==.Murderella:BAAANQADCgYIBgAAAA==.Murkhoof:BAAANQADCgYIBgABNQAECgQICAADAAAAAA==.',
Na='Nakovii:BAAANQAECgUIBQAAAA==.',
Ne='Nealite:BAAANQABCgQIBwAAAA==.Neerem:BAAANQABCgYIAwAAAA==.Neferata:BAABNQAECoEjAAMGAAkKChn6NgCUAgAGAAkKChn6NgCUAgAFAAYKywtzJQA+AQAAAA==.Nerrisa:BAAANQADCgcIBwAAAA==.Nertmage:BAABNQAECoFEAAMOAAgK/yKkAAAwAwAOAAgK/yKkAAAwAwAJAAEKsxCGnQFFAAAAAA==.Neublood:BAAANQAECgQIBwAAAA==.',
Ni='Nicodemus:BAAANQAECgQIBAAAAA==.Nineiota:BAAANQAECgUIEgAAAA==.',
No='Noblewarrior:BAACNQAFFIEfAAIYAAUKWhZXDgCeAQAYAAUKWhZXDgCeAQA1AAQKgTIAAhgACQo2Ir4UAF4DABgACQo2Ir4UAF4DAAAA.Nobukawaii:BAAANQAECgMIAwAAAA==.Noctilus:BAAANQADCgcIDwAAAA==.Noke:BAAANQAECgIJAgAAAA==.Notakoala:BAACNQAFFIEKAAIQAAQKYhNgDwA9AQAQAAQKYhNgDwA9AQA1AAQKgSsAAhAACQqIICANAFMDABAACQqIICANAFMDAAAA.Nothnx:BAACNQAFFIEFAAIWAAMKwARPFgDVAAAWAAMKwARPFgDVAAA1AAQKgRcAAhYACQpRFgc4AKACABYACQpRFgc4AKACAAAA.Notoriouspat:BAAANQAECgUICQAAAA==.Novia:BAAANQAECgUIBgABNQAECggIIAAYAIAVAA==.Noxeternis:BAABNQAECoEhAAMTAAgKyhqEHAA8AgATAAgKyhqEHAA8AgAUAAIKMgb7HwBOAAAAAA==.Noy:BAAANQADCgMIAwAAAA==.Noyber:BAAANQADCgMIAwAAAA==.Noydin:BAAANQADCgYIBgAAAA==.',
['Ní']='Níghtfall:BAAANQADCgUIBwAAAA==.Nínebreaker:BAAANQAECgEIAQAAAA==.',
Ob='Obern:BAAANQAECgcIDQAAAA==.Oblïna:BAAANQAECgQICAAAAA==.',
Od='Oddishh:BAAANQAECgYIDgAAAA==.',
Ol='Olleg:BAAANQADCgYICQAAAA==.',
Om='Omnicarkel:BAAANQADCgcJDAAAAA==.',
On='Onsen:BAAANQAECgcIEwABNQAECgkJLAAGAAUYAA==.',
Or='Orisys:BAAANQADCgQIBAAAAA==.Orkorc:BAAANQADCgQJBAAAAA==.',
Pa='Pajl:BAABNQAECoEaAAIBAAgKryNTHQA4AwABAAgKryNTHQA4AwABNQAFFAYIDgANAHQbAA==.Pandablaze:BAAANQADCggIKQAAAA==.Pandajoy:BAAANQADCgEIAQAAAA==.Panterarey:BAAANQAECgIIAgAAAA==.Papanurrgle:BAAANQAECgUICQAAAA==.Papazilla:BAAANQAECgMJAwAAAA==.Parakka:BAAANQAECgIIAgAAAA==.Pawp:BAAANQAECgQICwABNQAECgkJKQACANQWAA==.Paxiel:BAAANQAECgQICAAAAA==.',
Pe='Pearagon:BAAANQADCgQIBAABNQAFFAUIDgAHAGcdAA==.Pepsidew:BAAANQAECgcICgAAAA==.Pepsisprite:BAAANQAECgYICwAAAA==.',
Ph='Phdbeef:BAAANQAECgEIAQABNQAECgkJJgAIAOEiAA==.Phlemm:BAAANQADCgEIAQAAAA==.Phuriousdeff:BAAANQAECgIIAgAAAA==.',
Pi='Picklez:BAAANQAECgQIDAAAAA==.',
Po='Porkshamwich:BAAANQADCgQIBAAAAA==.Portwings:BAAANQADCggIDAAAAA==.',
Ps='Psyop:BAAANQADCgcIDgABNQAECgkJMAACAEQhAA==.Psyrax:BAAANQADCgUJBwAAAA==.',
Ra='Ragerade:BAAANQADCgEIAQAAAA==.Ramindeep:BAAANQADCgQIBAAAAA==.Razzberry:BAAANQAECgEIAQAAAA==.',
Re='Rebrowth:BAAANQADCggIDgAAAA==.Redkoala:BAAANQAECgYIBwABNQAFFAQICgAQAGITAA==.Repete:BAAANQAECgIIAwAAAA==.Requis:BAAANQADCgEIAQAAAA==.Resyek:BAABNQAECoFEAAILAAgKTiJXAwDyAgALAAgKTiJXAwDyAgAAAA==.Reven:BAAANQAECgYICAAAAA==.',
Rh='Rhak:BAAANQAECgEIAQAAAA==.',
Ri='Riivan:BAAANQAECgEIAQAAAA==.Rirugiliyang:BAAANQAECgEIAQAAAA==.',
Ro='Roardon:BAAANQADCgYIBgAAAA==.Roguè:BAAANQAECgQICgAAAA==.Rollinburn:BAAANQADCgUJBQAAAA==.Romanoff:BAAANQAECgUIDgAAAA==.Rosearcana:BAAANQAECgEIAQAAAA==.',
['Rô']='Rôx:BAAANQADCgcIBwABNQAECggIRAAPAF4bAA==.',
['Rõ']='Rõx:BAABNQAECoFEAAIPAAgKXhswNAB4AgAPAAgKXhswNAB4AgAAAA==.',
Sa='Sackoss:BAAANQAECgYIDwAAAA==.Saffronspark:BAAANQAECgQICAABNQAECggIIwAZAA4cAA==.Sainsei:BAAANQAECgUICgABNQAECggIIAAYAIAVAA==.Sandwitch:BAABNQAECoFEAAMFAAgKQxQEDgANAgAFAAgKoxIEDgANAgAGAAgKVQ7zbADwAQAAAA==.Sargatanas:BAABNQAECoEdAAIIAAgKnA2DTQCgAQAIAAgKnA2DTQCgAQAAAA==.Sars:BAAANQADCgUIBQABNQAECgQIBwADAAAAAA==.',
Sc='Scarcroww:BAAANQADCgMIAwABNQAECgkJGAAJAC0fAA==.Schrodinger:BAAANQAECgIIBAAAAA==.Scravenhoof:BAAANQADCgYIBgAAAA==.',
Se='Seraphael:BAAANQADCgIIAgAAAA==.Severum:BAABNQAECoEZAAIaAAgK2hLGEgDLAQAaAAgK2hLGEgDLAQAAAA==.',
Sh='Shadrad:BAAANQAECggIDwAAAA==.Shallot:BAABNQAECoEkAAIJAAkKzB5bLQAoAwAJAAkKzB5bLQAoAwAAAA==.Shammoo:BAAANQAECgYICAABNQAFFAQIBgABAJ0RAA==.Shammyd:BAAANQAECgUIBwAAAA==.Shantz:BAAANQAECgUIDwAAAA==.Shiftmypants:BAAANQAECgcIBwAAAA==.Shotmissed:BAAANQADCgEIAQAAAA==.',
Si='Sinterdeath:BAAANQAECgUICQAAAA==.',
Sk='Skatervan:BAAANQADCggJEwABNQAECgkJKAATAD0aAA==.Skylie:BAAANQADCgUIDQAAAA==.',
Sm='Smorthian:BAAANQAECgQIBQAAAA==.',
Sn='Sniffinsteak:BAAANQAECgYJEAAAAA==.Snoosnooftww:BAAANQADCgMIAwAAAA==.',
So='Solas:BAAANQAECgQIBQAAAA==.Soryan:BAAANQAECgUIBQAAAA==.',
Sp='Spankenstine:BAABNQAECoEVAAIBAAcKaReKfQD+AQABAAcKaReKfQD+AQABNQAECggIFQAYAP0LAA==.Sparkyy:BAAANQAECgIIAwAAAA==.Sphaeram:BAAANQAECgUIBQAAAA==.Spicypepsi:BAAANQADCgEIAQAAAA==.Spinfalldown:BAAANQAECgMIAwAAAA==.',
St='Stanfield:BAAANQADCgIIAgAAAA==.Stash:BAABNQAECoEXAAIBAAcKdyHSVABuAgABAAcKdyHSVABuAgAAAA==.Stinkydeathy:BAAANQADCgYJBgABNQAECgIIAgADAAAAAA==.Stinkydragon:BAAANQAECgIIAgAAAA==.Stormknight:BAAANQADCggIIwAAAA==.Stormpoo:BAAANQAECgEIAQAAAA==.',
Su='Suneater:BAAANQAECgYICgAAAA==.Superpi:BAAANQADCgYIBgABNQAECgUICAADAAAAAA==.Superret:BAAANQAECgUICAAAAA==.Suzygreen:BAAANQADCgQIBAAAAA==.',
Sv='Svetllama:BAAANQAECgQIBAAAAA==.',
Sw='Swíper:BAABNQAECoEkAAMEAAkKYCHjBgBQAwAEAAkKYCHjBgBQAwAfAAUKLgsKMwACAQAAAA==.',
Sy='Sylphièl:BAACNQAFFIEHAAMfAAQKGQxoCgD8AAAfAAMKww5oCgD8AAAEAAEKGwQPHABEAAA1AAQKgR8AAwQACQqxDy80AM8BAAQACQrCCS80AM8BAB8ABgp+D+AkAIsBAAAA.',
Ta='Tacoknight:BAAANQADCgEIAQAAAA==.Taela:BAAANQADCgYIBgAAAA==.Talixis:BAAANQADCgYIBgAAAA==.Talwaar:BAAANQADCgMIAwAAAA==.Tandarì:BAABNQAECoEiAAIBAAkKzSG0JgAQAwABAAkKzSG0JgAQAwAAAA==.Tankenstine:BAABNQAECoEVAAIYAAgK/QvzkgDFAQAYAAgK/QvzkgDFAQAAAA==.Tawnii:BAAANQAECgMIBAAAAA==.Taírn:BAAANQADCgUIBgAAAA==.',
Te='Tenderloin:BAAANQAECgQICAAAAA==.',
Th='Thanitose:BAAANQAECgUICAAAAA==.Thevelo:BAAANQAECgIIAgABNQAECgUIBgADAAAAAA==.Theßigshot:BAAANQADCgYIBwAAAA==.Thornwyn:BAAANQADCgYIBgAAAA==.Thorul:BAAANQADCgEIAQAAAA==.Thundurus:BAACNQAFFIEGAAIgAAIKXgEMJABsAAAgAAIKXgEMJABsAAA1AAQKgSwAAiAACQr6E25BAEUCACAACQr6E25BAEUCAAAA.',
Ti='Timmayy:BAAANQAECgIIAgABNQAECggIHgAXAP4YAA==.Tindrill:BAAANQADCgMIAwABNQAECggIIwAhABclAA==.Tinggoskrrah:BAAANQADCggIEgAAAA==.',
To='Toasties:BAAANQAECgQIBAAAAA==.Tomraedisk:BAABNQAECoEZAAIYAAcKKg/3nQCnAQAYAAcKKg/3nQCnAQAAAA==.Toopuretodie:BAAANQADCgYIBgABNQAFFAcIGQAKAEYgAA==.Totemagoat:BAACNQAFFIEJAAMHAAUK1BFBCgCJAQAHAAUK1BFBCgCJAQAgAAEKsQWiKgBFAAA1AAQKgSwAAwcACQr7HEYdANoCAAcACQr7HEYdANoCACAACArmFhZQAAoCAAAA.',
Tr='Treefist:BAAANQADCggIDgAAAA==.Trollietoes:BAAANQADCgcIDAAAAA==.',
Tu='Tummygummy:BAAANQAECgQIBQAAAA==.',
Tw='Twentyfour:BAABNQAECoEkAAIhAAkKGhMjGQBLAgAhAAkKGhMjGQBLAgAAAA==.',
Un='Undeadkiels:BAAANQADCggICAABNQAECgcIEQADAAAAAA==.Undeadmonks:BAAANQADCgYIBgAAAA==.',
Ur='Uraharakun:BAAANQAECgEIAQABNQAECgkJKAABAHYOAA==.',
Va='Vagalion:BAAANQAECgQIBAAAAA==.Vale:BAAANQADCgYICgAAAA==.Valeshot:BAABNQAECoEcAAIWAAkK5Q1nYQApAgAWAAkK5Q1nYQApAgAAAA==.Valimyr:BAAANQABCgMIBAAAAA==.Valkillrie:BAAANQAFFAEIAQAAAA==.Valthyrion:BAAANQAECgIIAgAAAA==.Vanhellsin:BAAANQAECgYIEgAAAA==.',
Ve='Vedbow:BAAANQADCgQIBwABNQAECgkJFgABAPoiAA==.Vedronas:BAABNQAECoEWAAIBAAkK+iIBGQBMAwABAAkK+iIBGQBMAwAAAA==.Veos:BAABNQAECoEkAAILAAgKuhwVBQCiAgALAAgKuhwVBQCiAgAAAA==.Verdict:BAAANQADCgYIEgAAAA==.Vern:BAAANQAECgcIEQAAAA==.Vernah:BAAANQADCgIIAgABNQAECgcIEQADAAAAAA==.',
Vi='Vidar:BAAANQADCgIIAgAAAA==.',
Vo='Volætile:BAAANQAECgQIBQAAAA==.Vorn:BAABNQAECoFEAAIIAAgK3hjaMAAwAgAIAAgK3hjaMAAwAgAAAA==.',
['Vè']='Vèronique:BAAANQADCgMIAwAAAA==.',
Wa='Waambler:BAABNQAECoEZAAIRAAgKGxqkDABfAgARAAgKGxqkDABfAgAAAA==.Waamchifu:BAAANQAECgEJAQAAAA==.Waltersight:BAAANQAECgMIBQAAAA==.Warbritt:BAAANQADCgYJBgAAAA==.Waterwalkerr:BAAANQADCgYIBgAAAA==.',
We='Weggie:BAAANQADCgUIBQAAAA==.',
Wh='Whateley:BAAANQAECgUICQAAAA==.Whatthezug:BAAANQABCgIIAgABNQAECgQIBwADAAAAAA==.Whoforted:BAABNQAECoEYAAMTAAkKOBZmJwDIAQATAAcK6xJmJwDIAQACAAQKcw7TnwD6AAAAAA==.',
Wi='Wisperia:BAAANQADCgQIBAAAAA==.',
Wo='Wormchild:BAAANQADCgIIAgAAAA==.',
Wu='Wulrat:BAAANQAECgcIDwAAAA==.',
Wy='Wyle:BAAANQAECgQIBAAAAA==.',
Xe='Xelí:BAABNQAECoFCAAIHAAgKDhfiRwAXAgAHAAgKDhfiRwAXAgAAAA==.',
Xi='Xil:BAAANQAECgQIBwAAAA==.',
Xp='Xplosiv:BAAANQAECggIEAABNQAFFAUIDgAHAAoVAA==.',
Xt='Xtremes:BAAANQADCggICwABNQAECgkJJwAXAEkZAA==.',
Yo='Youarefail:BAAANQADCgQIBAAAAA==.Youvbendoted:BAAANQAECgEIAQAAAA==.',
Yu='Yudah:BAAANQAECgEIAQABNQAECgQIBAADAAAAAA==.',
Za='Zanghonghua:BAABNQAECoEjAAIZAAgKDhzbFACJAgAZAAgKDhzbFACJAgAAAA==.',
Ze='Zemy:BAABNQAECoEdAAMQAAkKryXcCQByAwAQAAkKryXcCQByAwARAAcK6xgnFwC4AQAAAA==.Zeneca:BAAANQAECgIIAgABNQAECgkJLgATAD4fAA==.',
Zo='Zodstrike:BAAANQAECgYIEwAAAA==.Zooboo:BAABNQAECoENAAIeAAYKmBPZDwCHAQAeAAYKmBPZDwCHAQAAAA==.',
Zu='Zugzuggler:BAABNQAECoEYAAIYAAgK4Rl1WwBdAgAYAAgK4Rl1WwBdAgAAAA==.',
Zy='Zyrick:BAAANQABCgcICQAAAA==.',
['Ät']='Ätticus:BAAANQADCgQIBAABNQAECgQICgADAAAAAA==.',
['Öv']='Överpöwered:BAAANQAECgQICQABNQAECgQICgADAAAAAA==.',
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
